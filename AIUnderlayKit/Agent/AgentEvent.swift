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
    /// An agent paused a turn to ask the user a question (Codex's
    /// `request_user_input` family). Unlike a permission prompt this can be
    /// asked in the background, so it stays pending until the user answers.
    case userQuestionAsked
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
    /// True while a question the agent asked is still unanswered.
    ///
    /// Codex's question tool returns as soon as the question is shown, so the
    /// session keeps working (`.running`) while it waits for the user. The wait
    /// therefore cannot be read off `state` alone — without this flag a later
    /// tool event erases it and the amber "needs you" light never appears.
    public let pendingQuestion: Bool

    public init(
        id: String,
        providerId: String,
        state: AgentState,
        confidence: AgentConfidence,
        observedAt: Date,
        pendingQuestion: Bool = false
    ) {
        self.id = id
        self.providerId = providerId
        self.state = state
        self.confidence = confidence
        self.observedAt = observedAt
        self.pendingQuestion = pendingQuestion
    }

    /// Snapshots written before `pendingQuestion` existed must still load;
    /// a missing key means "no question pending".
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        providerId = try container.decode(String.self, forKey: .providerId)
        state = try container.decode(AgentState.self, forKey: .state)
        confidence = try container.decode(AgentConfidence.self, forKey: .confidence)
        observedAt = try container.decode(Date.self, forKey: .observedAt)
        pendingQuestion = try container.decodeIfPresent(Bool.self, forKey: .pendingQuestion) ?? false
    }
}