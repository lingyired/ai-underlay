import Foundation

/// How current usage compares to a constant-rate burn. Neutral wording only.
public enum PaceVerdict: Equatable, Sendable {
    /// Remaining is below the even-pace expectation — burning faster than even.
    case fast
    /// Remaining is above expectation — a cushion.
    case surplus
    /// Close to even.
    case onTrack
    /// Not enough information.
    case unknown
}

/// One metric row in the dashboard: a quota window rendered as a bar.
public struct DashboardRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    /// 0...1, or nil when unknown (rendered as an empty bar, never as 0%).
    public let remainingFraction: Double?
    /// Where remaining *should* be at even pace, for the baseline tick.
    public let expectedRemainingFraction: Double?
    public let resetAt: Date?
    public let availability: DataAvailability

    public init(
        id: String,
        label: String,
        remainingFraction: Double?,
        expectedRemainingFraction: Double? = nil,
        resetAt: Date?,
        availability: DataAvailability
    ) {
        self.id = id
        self.label = label
        self.remainingFraction = remainingFraction
        self.expectedRemainingFraction = expectedRemainingFraction
        self.resetAt = resetAt
        self.availability = availability
    }

    /// Comparison of actual vs even-pace remaining.
    public var verdict: PaceVerdict {
        guard let actual = remainingFraction, let expected = expectedRemainingFraction else { return .unknown }
        let diff = actual - expected
        if diff < -0.05 { return .fast }
        if diff > 0.05 { return .surplus }
        return .onTrack
    }

    /// A neutral one-line pace note, or nil when there is nothing to say.
    public var paceNote: String? {
        switch verdict {
        case .fast: return "消耗偏快（低于匀速基准）"
        case .surplus: return "仍有富余（高于匀速基准）"
        case .onTrack: return "接近匀速消耗"
        case .unknown: return nil
        }
    }

    /// A short human reset label, e.g. "3 小时 25 分后重置".
    public func resetLabel(now: Date = Date()) -> String? {
        guard let resetAt else { return nil }
        let seconds = Int(resetAt.timeIntervalSince(now))
        if seconds <= 0 { return "即将重置" }
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        if days > 0 { return "\(days) 天 \(hours) 小时后重置" }
        if hours > 0 { return "\(hours) 小时 \(minutes) 分后重置" }
        return "\(minutes) 分钟后重置"
    }
}

/// A provider section in the dashboard.
public struct DashboardSection: Identifiable, Equatable, Sendable {
    public let id: String
    public let providerId: String
    public let displayName: String
    public let availability: DataAvailability
    public let rows: [DashboardRow]
    /// Live agent sessions for this provider (running / total), if any.
    public let agentRunning: Int?
    public let agentTotal: Int?

    public init(
        id: String, providerId: String, displayName: String, availability: DataAvailability,
        rows: [DashboardRow], agentRunning: Int? = nil, agentTotal: Int? = nil
    ) {
        self.id = id
        self.providerId = providerId
        self.displayName = displayName
        self.availability = availability
        self.rows = rows
        self.agentRunning = agentRunning
        self.agentTotal = agentTotal
    }
}

/// Builds dashboard sections from quota snapshots. Pure and testable.
public enum DashboardModel {
    public static func displayName(for providerId: String) -> String {
        switch providerId.lowercased() {
        case "codex": return "Codex"
        case "claude", "claude-code", "claudecode": return "Claude Code"
        default: return providerId.capitalized
        }
    }

    /// Window label localized to Chinese.
    public static func label(for window: QuotaWindow) -> String {
        switch window.kind {
        case .session: return "5 小时"
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .custom: return window.label
        }
    }

    /// Sections for the given snapshots, in the order the providers were listed.
    /// A provider with no windows still yields a section (so the UI can show
    /// "未登录"/"无数据" rather than vanishing).
    public static func sections(
        providers: [String],
        snapshots: [String: ProviderQuotaSnapshot]
    ) -> [DashboardSection] {
        providers.map { provider in
            let snapshot = snapshots[provider]
            let rows = (snapshot?.windowsLongestFirst ?? []).map { window in
                DashboardRow(
                    id: "\(provider)-\(window.id)",
                    label: label(for: window),
                    remainingFraction: window.remainingFraction,
                    expectedRemainingFraction: QuotaPace.expectedRemaining(window: window),
                    resetAt: window.resetAt,
                    availability: window.availability
                )
            }
            return DashboardSection(
                id: provider,
                providerId: provider,
                displayName: displayName(for: provider),
                availability: snapshot?.availability ?? .unknown,
                rows: rows
            )
        }
    }

    /// A one-line status for a section with no usable data.
    public static func emptyStateText(for availability: DataAvailability) -> String {
        switch availability {
        case .unauthenticated: return "未登录"
        case .unsupported: return "不支持"
        case .unavailable: return "暂无数据"
        case .stale: return "数据已过期"
        case .unknown: return "未知"
        case .valid: return "暂无数据"
        }
    }
}