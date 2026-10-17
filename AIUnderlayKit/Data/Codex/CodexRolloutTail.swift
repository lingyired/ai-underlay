import Foundation

/// The newest turn boundary written to a rollout file.
public enum CodexRolloutPhase: Equatable, Sendable {
    /// A turn started and has not ended: the session is working right now.
    case running
    /// The last turn finished or was aborted.
    case ended
    /// Nothing readable, or no turn evidence in the scanned region.
    case unknown
}

/// How much a phase claim can be trusted.
public enum CodexRolloutEvidence: Equatable, Sendable {
    /// An explicit turn boundary: `task_started`, `task_complete`,
    /// `turn_aborted`. This is the transcript stating the turn's state.
    case boundary
    /// A record that is only written while a turn is being produced —
    /// `turn_context`, `item_completed`, `token_count`,
    /// `token_usage_record`. It proves the turn was open at that point; it can
    /// never prove the turn ended.
    case activity
    /// Nothing usable: `phase` is `unknown` and no claim is being made.
    case none
}

/// What the transcript currently says about a session's newest turn.
public struct CodexRolloutReading: Equatable, Sendable {
    public let phase: CodexRolloutPhase
    public let evidence: CodexRolloutEvidence

    public init(phase: CodexRolloutPhase, evidence: CodexRolloutEvidence) {
        self.phase = phase
        self.evidence = evidence
    }

    public static let unknown = CodexRolloutReading(phase: .unknown, evidence: .none)

    /// The confidence this reading deserves when reported as a session state.
    /// An activity-only claim is a hedge: it may hold a light open, but it must
    /// never be used to declare a turn finished.
    public var confidence: AgentConfidence {
        switch evidence {
        case .boundary: return .exact
        case .activity: return .inferred
        case .none: return .unknown
        }
    }
}

/// Finds the newest turn boundary in a Codex rollout (`.jsonl`) file.
///
/// A rollout grows from the session's first turn; the record that says whether
/// the *current* turn is still running can be megabytes behind the end of the
/// file (a single long tool call writes nothing in between), so this reads a
/// bounded window from the end rather than the last lines. After the first
/// scan only newly appended bytes are read, so polling a file every few seconds
/// stays cheap even for a 27 MB transcript.
///
/// A single window is not always enough. A long-lived session writes every turn
/// into the *same* file, so a busy day pushes the current turn's
/// `task_started` tens of megabytes back while the turn is still running —
/// exactly the case where the light used to stay dark. When no boundary turns up
/// in the window, the newest turn-scoped record decides instead: anything that
/// only exists while a turn is being written proves the turn is still open.
/// That is a weaker claim than a boundary, so it is reported separately as
/// `CodexRolloutEvidence.activity` and is never allowed to claim `ended`.
public struct CodexRolloutTailReader {
    /// How far back the first scan of an unknown file may look.
    static let scanLimit: UInt64 = 8 * 1024 * 1024
    /// Appended bytes beyond this get a fresh bounded scan instead.
    static let incrementalLimit: UInt64 = 2 * 1024 * 1024
    static let chunkSize: UInt64 = 256 * 1024
    /// Rollout lines that carry full prompts can be large; a boundary record
    /// never is. Oversized lines are skipped, not parsed.
    static let maxLineBytes = 1024 * 1024

    private struct Cursor {
        /// Bytes consumed up to the last complete (newline-terminated) line.
        var offset: UInt64
        var reading: CodexRolloutReading
    }

    private var cursors: [URL: Cursor] = [:]

    public init() {}

    public mutating func reset() { cursors.removeAll() }

    public mutating func forget(_ url: URL) { cursors.removeValue(forKey: url) }

    /// The phase of the session's newest turn, from cached evidence when the
    /// file has not changed since the last call.
    public mutating func phase(of url: URL) -> CodexRolloutPhase {
        reading(of: url).phase
    }

    /// The phase plus how it was established, so a caller can tell an observed
    /// ending from "the transcript says nothing either way".
    public mutating func reading(of url: URL) -> CodexRolloutReading {
        guard let size = Self.fileSize(url) else {
            cursors.removeValue(forKey: url)
            return .unknown
        }
        if let cursor = cursors[url] {
            if cursor.offset == size { return cursor.reading }
            if size > cursor.offset, size - cursor.offset <= Self.incrementalLimit,
               let appended = Self.newestReading(in: url, from: cursor.offset, to: size,
                                                 floorIsLineStart: true) {
                // Appended activity cannot weaken an observed boundary that
                // still describes the same turn; it can only replace a claim
                // about a different (newer) one.
                let reading = Self.stronger(appended.reading ?? cursor.reading, than: cursor.reading)
                cursors[url] = Cursor(offset: max(appended.consumed, cursor.offset), reading: reading)
                return reading
            }
        }
        // First sight, a rewrite, or a burst of growth: one bounded scan back
        // from the end finds the newest boundary wherever it is.
        let floor = size > Self.scanLimit ? size - Self.scanLimit : 0
        let reading = Self.newestReading(in: url, from: floor, to: size,
                                         floorIsLineStart: floor == 0)?.reading ?? .unknown
        cursors[url] = Cursor(offset: size, reading: reading)
        return reading
    }

    /// A boundary already observed still describes the file better than a
    /// freshly appended activity record: Codex flushes some lifecycle records
    /// late, so an `item_completed` can land *after* the `task_complete` that
    /// ended its turn. Only a newer boundary may replace a boundary.
    private static func stronger(
        _ new: CodexRolloutReading, than old: CodexRolloutReading
    ) -> CodexRolloutReading {
        guard old.evidence == .boundary, new.evidence == .activity else { return new }
        return old
    }

    private static func fileSize(_ url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.uint64Value
    }

    /// Scans `[from, to)` from the end and returns the newest turn-scoped
    /// record plus how far the region can be considered consumed (everything
    /// before a trailing partial line, which the next call will re-read once it
    /// is complete).
    ///
    /// Only the newest qualifying record matters: the scan runs newest-first, so
    /// the first one found is the current turn's latest word. A boundary wins by
    /// being newer; when there is none, activity records answer instead.
    ///
    /// `floorIsLineStart` says whether the region begins exactly at a line
    /// boundary — the cursor offset and the file start do; an arbitrary
    /// scan-limit cut does not, and its first segment is half a line.
    private static func newestReading(
        in url: URL, from floor: UInt64, to size: UInt64, floorIsLineStart: Bool
    ) -> (reading: CodexRolloutReading?, consumed: UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var offset = size
        var fragment = Data()
        var consumed = size
        var firstChunk = true
        // A newer activity record does not outrank an older boundary: Codex
        // flushes some lifecycle records late, so an `item_completed` can land
        // after the `task_complete` that ended its turn. Keep the newest
        // activity as a fallback and let any boundary in the window win.
        var newestActivity: CodexRolloutReading?
        while offset > floor {
            let start = max(floor, offset > chunkSize ? offset - chunkSize : 0)
            guard (try? handle.seek(toOffset: start)) != nil,
                  let read = try? handle.read(upToCount: Int(offset - start)) else { return nil }
            var data = read
            data.append(fragment)
            let lines = data.split(separator: 0x0A, omittingEmptySubsequences: false)
            let dropFirst = !(firstChunk && floorIsLineStart)
            if firstChunk {
                firstChunk = false
                // A trailing segment without its newline may still be growing;
                // never consume past it, or the next append would be skipped.
                if let trailing = lines.last, !trailing.isEmpty {
                    consumed = start + UInt64(data.count - trailing.count)
                }
            }
            let candidates: ArraySlice<Data> = dropFirst ? lines.dropFirst() : lines[...]
            for line in candidates.reversed() {
                guard let reading = reading(inLine: line) else { continue }
                if reading.evidence == .boundary { return (reading, consumed) }
                if newestActivity == nil { newestActivity = reading }
            }
            fragment = Data(lines.first ?? Data())
            if fragment.count > maxLineBytes { fragment.removeAll() }
            offset = start
        }
        // The leftover fragment is the first line of the scanned region; it is
        // complete only when the region starts at the file's beginning.
        if floor == 0, let reading = reading(inLine: fragment) {
            // The fragment is the region's oldest line, so any activity already
            // seen is newer evidence about the same file.
            return (newestActivity ?? reading, consumed)
        }
        return (newestActivity, consumed)
    }

    /// Substring prefilter: the JSON parse below is only worth it for records
    /// that can carry a turn claim. Everything else (messages, prompts, tool
    /// output) is skipped without decoding.
    private static let markers = [
        "task_started", "task_complete", "turn_aborted",
        "turn_context", "item_completed", "token_count", "token_usage_record",
    ].map { Data($0.utf8) }

    /// Maps one rollout line to a turn claim: either an explicit boundary, or
    /// the weaker "this turn was being written" evidence. Anything unrelated —
    /// including `thread_settings_applied`, which lands both after a turn ends
    /// and just before the next one starts — returns nil.
    private static func reading(inLine line: Data) -> CodexRolloutReading? {
        guard !line.isEmpty, line.count <= maxLineBytes,
              markers.contains(where: { line.range(of: $0) != nil }),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              let payload = object["payload"] as? [String: Any] else { return nil }
        // Records that identify a turn by id prove that turn was open at the
        // moment they were written; without the id they prove nothing.
        let activity = CodexRolloutReading(phase: .running, evidence: .activity)
        switch object["type"] as? String {
        case "turn_context", "token_usage_record":
            return payload["turn_id"] is String ? activity : nil
        case "event_msg":
            switch payload["type"] as? String {
            case "task_started":
                guard payload["turn_id"] is String else { return nil }
                return CodexRolloutReading(phase: .running, evidence: .boundary)
            case "task_complete", "turn_aborted":
                guard payload["turn_id"] is String else { return nil }
                return CodexRolloutReading(phase: .ended, evidence: .boundary)
            case "item_completed":
                return payload["turn_id"] is String ? activity : nil
            case "token_count":
                // Codex writes counters only while a turn is streaming.
                return activity
            default:
                return nil
            }
        default:
            return nil
        }
    }
}
