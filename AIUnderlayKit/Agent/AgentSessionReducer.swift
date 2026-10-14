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
                     state: state, confidence: confidence, observedAt: event.at,
                     pendingQuestion: Self.pendingQuestion(
                        after: event.kind,
                        previous: sessions[event.sessionId]?.pendingQuestion ?? false))
    }

    /// Whether a question is still outstanding once this event has been applied.
    ///
    /// Codex's question tool is non-blocking: the tool call completes the moment
    /// the question is shown, and the agent keeps working while it waits. So the
    /// answer cannot be inferred from the tool's own result — only the user's
    /// next message (`UserPromptSubmit`) or the session ending proves the
    /// question is off the table.
    static func pendingQuestion(after kind: AgentEventKind, previous: Bool) -> Bool {
        switch kind {
        case .userQuestionAsked: return true
        case .userPromptSubmitted, .sessionStart, .sessionEnd: return false
        default: return previous
        }
    }

    static func state(for kind: AgentEventKind) -> (state: AgentState, confidence: AgentConfidence) {
        switch kind {
        case .sessionStart: return (.idle, .exact)
        case .sessionEnd: return (.idle, .exact)
        case .userPromptSubmitted: return (.running, .exact)
        case .toolUseStarted, .toolUseFinished: return (.running, .exact)
        case .permissionRequested: return (.waitingApproval, .exact)
        case .notification: return (.waitingInput, .exact)
        case .userQuestionAsked: return (.waitingInput, .exact)
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
    /// A `completed` light is a transient acknowledgement and decays after its
    /// short sweep window.
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

    /// A completed light is a transient acknowledgement; its overlay plays one
    /// short sweep, then returns to a plain quota bar.
    public static let completedStaleness: TimeInterval = 20

    /// The state a session actually contributes right now. `running` and
    /// `completed` decay to `idle`; every other state is reported as-is.
    public static func effectiveState(_ session: AgentSession, now: Date) -> AgentState {
        let staleness: TimeInterval
        switch session.state {
        case .running: staleness = runningStaleness
        case .completed: staleness = completedStaleness
        default: return session.state
        }
        return now.timeIntervalSince(session.observedAt) > staleness ? .idle : session.state
    }
}

/// What one provider is doing right now, as four independent dimensions.
///
/// Deliberately *not* a single state: a provider with one session waiting
/// for you and another one working must be expressible as both at once
/// (product consensus §4.1). Collapsing them to a `dominant` state is what
/// made a running spectrum disappear whenever anything was waiting.
public struct AgentSignals: Equatable, Sendable {
    public var activeCount: Int
        /// Sessions waiting for a permission decision.
        public var waitingApprovalCount: Int
        /// Sessions waiting for typed input (or any other user answer).
        public var waitingInputCount: Int
    public var errorCount: Int
    /// A finished session whose short acknowledgement sweep has not expired.
    public var completedCount: Int
    /// Unknown / reconnecting sessions: never promoted to a definite state,
    /// and never on their own a reason to show a failure.
    public var unknownCount: Int

    public init(
        activeCount: Int = 0,
            waitingApprovalCount: Int = 0,
            waitingInputCount: Int = 0,
        errorCount: Int = 0,
        completedCount: Int = 0,
        unknownCount: Int = 0
    ) {
        self.activeCount = activeCount
            self.waitingApprovalCount = waitingApprovalCount
            self.waitingInputCount = waitingInputCount
        self.errorCount = errorCount
        self.completedCount = completedCount
        self.unknownCount = unknownCount
    }

        /// Any session waiting on the user, either flavor.
        public var waitingCount: Int { waitingApprovalCount + waitingInputCount }

    public var hasActive: Bool { activeCount > 0 }
    public var hasWaiting: Bool { waitingCount > 0 }
    public var hasError: Bool { errorCount > 0 }
    public var isEmpty: Bool {
        activeCount == 0 && waitingCount == 0 && errorCount == 0
            && completedCount == 0 && unknownCount == 0
    }

    /// The highest-priority state, for callers that can only show one
    /// (menus, diagnostics). Error > Waiting > Active > Completed.
    public var primaryState: AgentState {
        if hasError { return .error }
        if hasWaiting { return .waitingApproval }
        if hasActive { return .running }
        if completedCount > 0 { return .completed }
        if unknownCount > 0 { return .unknown }
        return .idle
    }

    /// Signals for a single observed state — used by the one-state preview
    /// path and to keep `dominant`-style callers working.
    public init(state: AgentState) {
        self.init()
        switch state {
        case .running: activeCount = 1
            case .waitingInput: waitingInputCount = 1
            case .waitingApproval: waitingApprovalCount = 1
        case .error: errorCount = 1
        case .completed: completedCount = 1
        case .unknown, .reconnecting: unknownCount = 1
        case .idle: break
        }
    }

    /// Counts a session list into the four dimensions.
    public static func counting(_ sessions: [AgentSession], now: Date = Date()) -> AgentSignals {
        var signals = AgentSignals()
        for session in sessions {
            let state = AgentActivityAggregator.effectiveState(session, now: now)
            switch state {
            case .running: signals.activeCount += 1
            case .waitingInput: signals.waitingInputCount += 1
            case .waitingApproval: signals.waitingApprovalCount += 1
            case .error: signals.errorCount += 1
            case .completed: signals.completedCount += 1
            case .unknown, .reconnecting: signals.unknownCount += 1
            case .idle: break
            }
            // An unanswered question is a dimension of its own: Codex keeps
            // working (so the session is still `.running`) while it waits for
            // the user. Counting it here, instead of overwriting the state,
            // keeps both the moving effect and the amber "needs you" edges.
            if session.pendingQuestion, state != .waitingInput, state != .waitingApproval {
                signals.waitingInputCount += 1
            }
        }
        return signals
    }

    /// Signals from hook evidence, with the live session list used as a
    /// reality check on "running" only.
    ///
    /// Hooks are the fine-grained source, but they are not proof that the user
    /// can see anything: Codex also fires them for agents that no UI lists
    /// (subagents and background runs have no transcript and never appear as a
    /// thread), and a turn that ends without a `Stop` hook stays "running" until
    /// the staleness window expires. Both lit the bar green while the user had
    /// nothing on screen.
    ///
    /// So a `running` claim is dropped when either:
    /// * the session is unknown to the live session list, or
    /// * the list has written *after* our last hook event for that session and
    ///   still reports it idle, which means the turn really ended.
    ///
    /// States that ask the user for something — waiting, approval, error — are
    /// never gated: they are explicit and rare, and hiding one is worse than an
    /// extra light. Sessions the hooks have never seen are still counted, so a
    /// broken or missing hook install does not go dark.
    public static func reconciled(
        hook hookSessions: [AgentSession],
        polled polledSessions: [AgentSession],
        now: Date = Date()
    ) -> AgentSignals? {
        guard !hookSessions.isEmpty else {
            let polled = counting(polledSessions, now: now)
            return polled.isEmpty ? nil : polled
        }

        var signals = counting(hookSessions, now: now)
        let hookIds = Set(hookSessions.map(\.id))
        if !polledSessions.isEmpty {
            let polledById = Dictionary(polledSessions.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for session in hookSessions
            where AgentActivityAggregator.effectiveState(session, now: now) == .running {
                guard let entry = polledById[session.id] else {
                    signals.activeCount = max(0, signals.activeCount - 1)
                    continue
                }
                if entry.state == .idle, entry.observedAt >= session.observedAt {
                    signals.activeCount = max(0, signals.activeCount - 1)
                }
            }
        }
        if !signals.isEmpty { return signals }

        // Every hook session decayed to idle. A session only the live list
        // knows about still counts, so activity keeps showing when hooks are
        // stale or were never installed.
        let unseen = counting(polledSessions.filter { !hookIds.contains($0.id) }, now: now)
        return unseen.isEmpty ? nil : unseen
    }
}
