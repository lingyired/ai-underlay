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

    // MARK: - Persistence

    /// A serializable snapshot of the reducer's state, so a restart does not
    /// forget a session that is waiting on the user (those never re-fire an
    /// event, so losing them means losing the light until the user acts).
    public struct Snapshot: Codable, Sendable, Equatable {
        public var sessions: [AgentSession]
        public var lastEventAt: [String: Date]

        public init(sessions: [AgentSession], lastEventAt: [String: Date]) {
            self.sessions = sessions
            self.lastEventAt = lastEventAt
        }
    }

    public func snapshot() -> Snapshot {
        Snapshot(sessions: allSessions(), lastEventAt: lastEventAt)
    }

    /// Replaces the current state with a restored snapshot, dropping entries
    /// older than `maxAge` so a snapshot from days ago cannot resurrect zombie
    /// lights. `running` entries are kept and left to the staleness rule; only
    /// the age cutoff is applied here.
    public func restore(_ snapshot: Snapshot, now: Date = Date(), maxAge: TimeInterval = 6 * 3600) {
        sessions.removeAll()
        lastEventAt.removeAll()
        for session in snapshot.sessions where now.timeIntervalSince(session.observedAt) <= maxAge {
            sessions[session.id] = session
            lastEventAt[session.id] = snapshot.lastEventAt[session.id] ?? session.observedAt
        }
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
        aggregate(sessions, now: Date())
    }

    /// Aggregates with an explicit clock so the staleness rule is testable.
    ///
    /// A `running` session that has gone quiet is *stale*: an agent that stopped
    /// firing events is either idle or blocked, and either way we no longer know
    /// it is working — so it must not keep the bar green. States that ask the
    /// user for something (`waitingInput`, `waitingApproval`, `error`) never go
    /// stale: the whole point of those lights is to survive until the user acts.
    public static func aggregate(_ sessions: [AgentSession], now: Date) -> Aggregate {
        var counts: [AgentState: Int] = [:]
        for session in sessions {
            counts[effectiveState(session, now: now), default: 0] += 1
        }
        let unknownCount = (counts[.unknown] ?? 0) + (counts[.reconnecting] ?? 0)
        let dominant = counts.keys
            .filter { $0 != .unknown && $0 != .reconnecting }
            .max { priority($0) < priority($1) } ?? .idle
        return Aggregate(dominant: dominant, counts: counts, unknownCount: unknownCount)
    }

    /// How long a `running` session may go without a new event before we stop
    /// calling it running. Long enough to survive a slow tool call or a thinking
    /// pause (a build can take minutes), short enough that a finished-but-silent
    /// session — one whose `Stop` we never saw — does not linger green.
    public static let runningStaleness: TimeInterval = 180

    /// The state a session actually contributes right now. Only `running` decays
    /// (to `idle`); every other state is reported as-is.
    public static func effectiveState(_ session: AgentSession, now: Date) -> AgentState {
        guard session.state == .running,
              now.timeIntervalSince(session.observedAt) > runningStaleness
        else { return session.state }
        return .idle
    }
}
