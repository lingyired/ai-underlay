import Foundation

/// Folds a stream of `AgentEvent`s into per-session state.
///
/// It must survive out-of-order and duplicate delivery: an event older than the
/// state it would overwrite is ignored, so a late `toolUseFinished` can never
/// flip a session that has already stopped back to running, and a stale event
/// can never turn a session into `completed`. Unknown event kinds leave the
/// session in `unknown` rather than guessing.
public final class AgentSessionReducer {
    private var sessions: [String: AgentSession] = [:]
    /// Last event timestamp seen per session, to reject stale deliveries.
    private var lastEventAt: [String: Date] = [:]

    public init() {}

    public func reduce(_ event: AgentEvent) -> AgentSession {
        // Reject events older than what we have already applied.
        if let last = lastEventAt[event.sessionId], event.at < last {
            return sessions[event.sessionId] ?? make(event, state: .unknown, confidence: .unknown)
        }
        lastEventAt[event.sessionId] = max(lastEventAt[event.sessionId] ?? .distantPast, event.at)

        let state = Self.state(for: event.kind)
        let session = make(event, state: state.state, confidence: state.confidence)
        sessions[event.sessionId] = session
        return session
    }

    public func session(id: String) -> AgentSession? { sessions[id] }

    public func allSessions() -> [AgentSession] { Array(sessions.values) }

    /// Removes a session (e.g. on explicit end) so it stops contributing to
    /// the aggregate.
    public func remove(id: String) {
        sessions.removeValue(forKey: id)
        lastEventAt.removeValue(forKey: id)
    }

    private func make(_ event: AgentEvent, state: AgentState, confidence: AgentConfidence) -> AgentSession {
        AgentSession(id: event.sessionId, providerId: event.providerId,
                     state: state, confidence: confidence, observedAt: event.at)
    }

    static func state(for kind: AgentEventKind) -> (state: AgentState, confidence: AgentConfidence) {
        switch kind {
        case .sessionStart: return (.idle, .exact)
        case .sessionEnd: return (.idle, .exact)
        case .userPromptSubmitted: return (.running, .exact)
        case .toolUseStarted, .toolUseFinished: return (.running, .exact)
        case .permissionRequested: return (.waitingApproval, .exact)
        case .notification: return (.waitingInput, .exact)
        case .stopped: return (.completed, .exact)
        case .subagentStarted, .subagentFinished: return (.running, .inferred)
        case .unknown: return (.unknown, .unknown)
        }
    }
}

/// Aggregates sessions into a single displayed state using a fixed priority.
/// Unknown sessions are counted separately and never folded into `idle`.
public enum AgentActivityAggregator {
    /// Higher wins.
    public static func priority(_ state: AgentState) -> Int {
        switch state {
        case .error: return 6
        case .waitingApproval: return 5
        case .waitingInput: return 4
        case .running: return 3
        case .completed: return 2
        case .idle: return 1
        case .unknown, .reconnecting: return 0
        }
    }

    public struct Aggregate: Equatable {
        public var dominant: AgentState
        public var counts: [AgentState: Int]
        public var unknownCount: Int

        public init(dominant: AgentState, counts: [AgentState: Int], unknownCount: Int) {
            self.dominant = dominant
            self.counts = counts
            self.unknownCount = unknownCount
        }
    }

    public static func aggregate(_ sessions: [AgentSession]) -> Aggregate {
        var counts: [AgentState: Int] = [:]
        for session in sessions {
            counts[session.state, default: 0] += 1
        }
        let unknownCount = (counts[.unknown] ?? 0) + (counts[.reconnecting] ?? 0)
        let dominant = counts.keys
            .filter { $0 != .unknown && $0 != .reconnecting }
            .max { priority($0) < priority($1) } ?? .idle
        return Aggregate(dominant: dominant, counts: counts, unknownCount: unknownCount)
    }
}
