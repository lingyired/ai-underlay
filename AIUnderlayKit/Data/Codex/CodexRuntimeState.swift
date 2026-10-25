import Foundation

public enum CodexRuntimeStatus: String, Equatable, Sendable {
    case connecting, connected, fallback

    public var title: String {
        switch self {
        case .connecting: return "正在连接 Codex"
        case .connected: return "自动检测已连接"
        case .fallback: return "正在使用日志检测"
        }
    }

    public var detail: String {
        switch self {
        case .connecting:
            return "正在连接本机 Codex，期间仍会通过会话日志检测活动，无需安装 Hook。"
        case .connected:
            return "已连接 Codex 桌面端，可自动检测运行和待处理状态，无需安装或信任 Hook。未被实时连接覆盖的会话仍使用日志。"
        case .fallback:
            return "会话日志仍可检测基本运行状态，等待回复和批准提示可能不完整。打开 Codex 桌面端后会自动重试，无需配置 Hook。"
        }
    }
}

struct CodexRuntimeSnapshot: Equatable, Sendable {
    let status: CodexRuntimeStatus
    let sessions: [AgentSession]
}

/// Consumes only the sanitized local frames produced by the IPC adapter.
/// No names, paths, prompt text, tool arguments or raw wire frames are retained.
struct CodexRuntimeState {
    static let maximumSessions = 128
    static let heartbeatTimeout: TimeInterval = 45
    private(set) var status: CodexRuntimeStatus = .connecting
    private var lastFrameAt: Date?
    private var excluded: Set<String> = []
    private struct Entry {
        var state: AgentState = .unknown
        var turnID: String?
        var input = false
        var approval = false
        var flagInput = false
        var flagApproval = false
        var available = true
        var changedAt: Date
    }
    private var entries: [String: Entry] = [:]

    mutating func connecting() {
        status = .connecting
    }

    mutating func disconnected() {
        status = .fallback
        for id in entries.keys { entries[id]?.available = false }
    }

    mutating func consume(_ data: Data, at now: Date = Date()) {
        guard data.count <= 2 * 1024 * 1024,
              let frame = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              frame["hostId"] as? String == "local",
              let kind = frame["kind"] as? String else { return }
        lastFrameAt = now
        switch kind {
        case "status":
            if frame["connected"] as? Bool == true { status = .connected }
            else { disconnected() }
        case "runtimeBatch":
            guard let events = frame["events"] as? [[String: Any]], events.count <= 512 else { return }
            for event in events { consumeEvent(event, at: now) }
        case "attention":
            guard let id = Self.id(frame["threadId"]), !excluded.contains(id),
                  let requests = frame["requests"] as? [[String: Any]], requests.count <= 64 else { return }
            var entry = entries[id] ?? Entry(changedAt: now)
            entry.input = requests.contains { $0["kind"] as? String == "input" }
            entry.approval = requests.contains { $0["kind"] as? String == "approval" }
            entry.changedAt = now
            store(entry, id: id)
        case "streamInvalidated":
            if let id = Self.id(frame["threadId"]) { entries[id]?.available = false }
        default: break
        }
    }

    private mutating func consumeEvent(_ event: [String: Any], at now: Date) {
        guard let id = Self.id(event["threadId"]), let method = event["method"] as? String else { return }
        if method == "metadata" {
            let source = (event["source"] as? String ?? "").lowercased()
            if event["parentThreadId"] as? String != nil
                || ["subagent", "guardian_review", "autoreview", "auto_review"].contains(source)
                || (event["model"] as? String ?? "").hasPrefix("codex-auto-review") {
                if excluded.count < Self.maximumSessions { excluded.insert(id) }
                entries.removeValue(forKey: id)
            }
            return
        }
        guard !excluded.contains(id) else { return }
        var entry = entries[id] ?? Entry(changedAt: now)
        switch method {
        case "turn/started", "turn/attached":
            guard let turnID = event["turnId"] as? String, !turnID.isEmpty else { return }
            if entry.turnID != turnID {
                entry.input = false; entry.approval = false
                entry.flagInput = false; entry.flagApproval = false
            }
            entry.turnID = turnID
            entry.state = .running
            entry.available = true
        case "turn/completed":
            guard entry.turnID != nil, event["turnId"] as? String == entry.turnID else { return }
            switch event["status"] as? String {
            case "failed": entry.state = .error
            case "interrupted": entry.state = .idle
            case "completed": entry.state = .completed
            default: return
            }
            entry.input = false; entry.approval = false
            entry.flagInput = false; entry.flagApproval = false
        case "thread/status/changed":
            switch event["status"] as? String {
            case "active":
                // A status flag alone must not manufacture a running turn.
                if entry.turnID != nil, entry.state == .running { entry.available = true }
            case "idle":
                // Idle bookkeeping can precede the actual terminal patch.
                break
            case "notLoaded", "systemError": entry.available = false
            default: break
            }
            let flags = event["flags"] as? [String] ?? []
            entry.flagInput = flags.contains("waitingOnUserInput")
            entry.flagApproval = flags.contains("waitingOnApproval")
        case "stream/released":
            if entry.state != .completed, entry.state != .error { entry.state = .idle }
            entry.available = false
            entry.input = false; entry.approval = false
            entry.flagInput = false; entry.flagApproval = false
        default:
            // Metadata, usage and item timing cannot establish lifecycle.
            return
        }
        entry.changedAt = now
        store(entry, id: id)
    }

    private mutating func store(_ entry: Entry, id: String) {
        if entries[id] == nil, entries.count >= Self.maximumSessions {
            if let oldest = entries.min(by: { $0.value.changedAt < $1.value.changedAt })?.key {
                entries.removeValue(forKey: oldest)
            }
        }
        entries[id] = entry
    }

    func snapshot(at now: Date = Date()) -> CodexRuntimeSnapshot {
        let connected = status == .connected
            && lastFrameAt.map { now.timeIntervalSince($0) <= Self.heartbeatTimeout } == true
        let effectiveStatus: CodexRuntimeStatus = status == .connected && !connected ? .fallback : status
        let sessions = entries.compactMap { id, entry -> AgentSession? in
            let available = connected && entry.available
            let input = entry.input || entry.flagInput
            let approval = entry.approval || entry.flagApproval
            var state = entry.state
            if !available, state == .running || state == .unknown {
                guard input || approval else { return nil }
                state = .unknown
            }
            if approval { state = .waitingApproval }
            else if input, state != .running { state = .waitingInput }
            guard state != .unknown else { return nil }
            if state == .completed, now.timeIntervalSince(entry.changedAt) > AgentActivityAggregator.completedStaleness {
                // Keep the confirmed ending authoritative over an older log.
                state = .idle
            }
            return AgentSession(
                id: id, providerId: "codex", state: state,
                confidence: available ? .exact : .inferred,
                observedAt: available && state == .running ? now : entry.changedAt,
                pendingQuestion: input
            )
        }.sorted { $0.id < $1.id }
        return CodexRuntimeSnapshot(status: effectiveStatus, sessions: sessions)
    }

    private static func id(_ value: Any?) -> String? {
        (value as? String).flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
    }
}

/// Authority is per thread. A connected desktop does not imply that every CLI
/// session has a live owner, so uncovered sessions continue using their logs.
enum CodexActivityResolver {
    static func sessions(runtime: [AgentSession], polled: [AgentSessionInfo]) -> [AgentSession] {
        var result: [String: AgentSession] = [:]
        for session in polled where session.provider == "codex" {
            result[session.id.lowercased()] = session.asAgentSession
        }
        for session in runtime {
            let id = session.id.lowercased()
            if session.confidence == .inferred,
               let log = result[id], log.observedAt >= session.observedAt {
                let waiting = session.pendingQuestion || session.state == .waitingInput || session.state == .waitingApproval
                if !waiting || log.state == .idle { continue }
            }
            result[id] = session
        }
        return result.values.sorted { $0.id < $1.id }
    }
}
