import Foundation

/// The whitelisted set of agent lifecycle events we accept. Every event is
/// metadata only — provider, session, event kind, timestamp. Nothing that
/// carries prompt text, tool arguments, or model output is representable here,
/// so conversation content can never reach the overlay or disk.
public enum AgentEventKind: String, Codable, Sendable, CaseIterable {
    case sessionStart
    case sessionEnd
    case userPromptSubmitted
    case toolUseStarted
    case toolUseFinished
    case permissionRequested
    case notification
    case stopped
    case subagentStarted
    case subagentFinished
    /// Anything we received but do not model. Never promoted to a definite state.
    case unknown
}

/// A single normalized agent event. Deliberately minimal.
public struct AgentEvent: Codable, Sendable, Equatable {
    public let providerId: String
    public let sessionId: String
    public let kind: AgentEventKind
    public let at: Date

    public init(providerId: String, sessionId: String, kind: AgentEventKind, at: Date) {
        self.providerId = providerId
        self.sessionId = sessionId
        self.kind = kind
        self.at = at
    }
}

/// The observable state of a session. `unknown` and `reconnecting` exist so we
/// never have to claim a state we cannot actually observe.
public enum AgentState: String, Codable, Sendable, CaseIterable {
    case idle
    case running
    case waitingApproval
    case waitingInput
    case completed
    case error
    case unknown
    case reconnecting
}

/// How sure we are about an `AgentState`. `inferred` states are shown with a
/// hedge; `unknown` is shown as-is and never as `idle`.
public enum AgentConfidence: String, Codable, Sendable {
    case exact
    case inferred
    case unknown
}

/// A session as presented to the overlay. `accountKey` is an internal stable
/// identifier, never a raw email.
public struct AgentSession: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let providerId: String
    public let state: AgentState
    public let confidence: AgentConfidence
    public let observedAt: Date

    public init(
        id: String,
        providerId: String,
        state: AgentState,
        confidence: AgentConfidence,
        observedAt: Date
    ) {
        self.id = id
        self.providerId = providerId
        self.state = state
        self.confidence = confidence
        self.observedAt = observedAt
    }
}
