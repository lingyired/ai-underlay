import Foundation

/// The newest turn boundary written to a rollout file.
public enum CodexRolloutPhase: Equatable, Sendable {
    /// A turn started and has not ended: the session is working right now.
    case running
    /// The last turn finished or was aborted.
    case ended
    /// Nothing readable, or no boundary in the scanned region.
    case unknown
}

/// Finds the newest turn boundary in a Codex rollout (`.jsonl`) file.
///
/// A rollout grows from the session's first turn; the record that says whether
/// the *current* turn is still running can be megabytes behind the end of the
/// file (a single long tool call writes nothing in between), so this reads a
/// bounded window from the end rather than the last lines. After the first
/// scan only newly appended bytes are read, so polling a file every few seconds
/// stays cheap even for a 27 MB transcript.
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
        var phase: CodexRolloutPhase
    }

    private var cursors: [URL: Cursor] = [:]

    public init() {}

    public mutating func reset() { cursors.removeAll() }

    public mutating func forget(_ url: URL) { cursors.removeValue(forKey: url) }

    /// The phase of the session's newest turn, from cached evidence when the
    /// file has not changed since the last call.
    public mutating func phase(of url: URL) -> CodexRolloutPhase {
        guard let size = Self.fileSize(url) else {
            cursors.removeValue(forKey: url)
            return .unknown
        }
        if let cursor = cursors[url] {
            if cursor.offset == size { return cursor.phase }
            if size > cursor.offset, size - cursor.offset <= Self.incrementalLimit,
               let appended = Self.newestBoundary(in: url, from: cursor.offset, to: size,
                                                  floorIsLineStart: true) {
                let phase = appended.phase ?? cursor.phase
                cursors[url] = Cursor(offset: max(appended.consumed, cursor.offset), phase: phase)
                return phase
            }
        }
        // First sight, a rewrite, or a burst of growth: one bounded scan back
        // from the end finds the newest boundary wherever it is.
        let floor = size > Self.scanLimit ? size - Self.scanLimit : 0
        let phase = Self.newestBoundary(in: url, from: floor, to: size,
                                        floorIsLineStart: floor == 0)?.phase ?? .unknown
        cursors[url] = Cursor(offset: size, phase: phase)
        return phase
    }

    private static func fileSize(_ url: URL) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        return (attributes[.size] as? NSNumber)?.uint64Value
    }

    /// Scans `[from, to)` from the end and returns the newest boundary plus how
    /// far the region can be considered consumed (everything before a trailing
    /// partial line, which the next call will re-read once it is complete).
    ///
    /// `floorIsLineStart` says whether the region begins exactly at a line
    /// boundary — the cursor offset and the file start do; an arbitrary
    /// scan-limit cut does not, and its first segment is half a line.
    private static func newestBoundary(
        in url: URL, from floor: UInt64, to size: UInt64, floorIsLineStart: Bool
    ) -> (phase: CodexRolloutPhase?, consumed: UInt64)? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var offset = size
        var fragment = Data()
        var consumed = size
        var firstChunk = true
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
                if let phase = phase(inLine: line) { return (phase, consumed) }
            }
            fragment = Data(lines.first ?? Data())
            if fragment.count > maxLineBytes { fragment.removeAll() }
            offset = start
        }
        // The leftover fragment is the first line of the scanned region; it is
        // complete only when the region starts at the file's beginning.
        if floor == 0, let phase = phase(inLine: fragment) { return (phase, consumed) }
        return (nil, consumed)
    }

    /// Maps one rollout line to a turn boundary, ignoring everything else.
    private static let markers = ["task_started", "task_complete", "turn_aborted"].map { Data($0.utf8) }

    private static func phase(inLine line: Data) -> CodexRolloutPhase? {
        guard !line.isEmpty, line.count <= maxLineBytes,
              markers.contains(where: { line.range(of: $0) != nil }),
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "event_msg",
              let payload = object["payload"] as? [String: Any],
              payload["turn_id"] is String,
              let kind = payload["type"] as? String else { return nil }
        switch kind {
        case "task_started": return .running
        case "task_complete", "turn_aborted": return .ended
        default: return nil
        }
    }
}
