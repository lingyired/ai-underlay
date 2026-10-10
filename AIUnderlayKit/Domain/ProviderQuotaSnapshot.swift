import Foundation

/// A provider's quota at a point in time. One snapshot per provider+account so
/// multiple accounts never mix.
public struct ProviderQuotaSnapshot: Identifiable, Codable, Sendable, Equatable {
    /// `providerId + accountKey`, stable across refreshes.
    public let id: String
    public let providerId: String
    /// Internal stable account identifier; never a raw email for display.
    public let accountKey: String?
    public let sourceEngineId: String
    /// Windows in provider order. Callers that need the nesting order sort by
    /// duration (longest first) themselves.
    public let windows: [QuotaWindow]
    public let fetchedAt: Date
    public let availability: DataAvailability
    public let diagnosticCode: String?

    public init(
        id: String,
        providerId: String,
        accountKey: String?,
        sourceEngineId: String,
        windows: [QuotaWindow],
        fetchedAt: Date,
        availability: DataAvailability,
        diagnosticCode: String? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.accountKey = accountKey
        self.sourceEngineId = sourceEngineId
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.availability = availability
        self.diagnosticCode = diagnosticCode
    }

    /// Windows ordered longest-duration first, which is the order the nested
    /// gauge consumes (outermost = longest). Windows without a duration sort
    /// last, preserving their relative order.
    public var windowsLongestFirst: [QuotaWindow] {
        windows.enumerated()
            .sorted { lhs, rhs in
                let l = lhs.element.durationSeconds ?? -1
                let r = rhs.element.durationSeconds ?? -1
                if l == r { return lhs.offset < rhs.offset }
                return l > r
            }
            .map(\.element)
    }
}
