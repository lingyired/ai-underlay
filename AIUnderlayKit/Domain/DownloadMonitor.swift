import Foundation

/// Where a download came from, as counted by the download monitor.
///
/// The wire values are stable identifiers shared with the stats endpoint; the
/// display names are the user-facing Chinese labels used by the dashboard and
/// the settings page.
public enum DownloadChannel: String, CaseIterable, Codable, Sendable, Equatable {
    case quark
    case baidu
    case github

    public var displayName: String {
        switch self {
        case .quark: return "夸克网盘"
        case .baidu: return "百度网盘"
        case .github: return "GitHub 直链"
        }
    }
}

/// One channel's cumulative download count at a point in time.
///
/// `total` is the all-time count the endpoint reports. `last24h` / `last7d` are
/// optional rolling windows; a channel that cannot report them (e.g. GitHub's
/// release API only knows asset totals) leaves them nil rather than guessing.
public struct DownloadChannelStat: Identifiable, Codable, Sendable, Equatable {
    public let channel: DownloadChannel
    public let total: Int
    public let last24h: Int?
    public let last7d: Int?

    public init(channel: DownloadChannel, total: Int, last24h: Int? = nil, last7d: Int? = nil) {
        self.channel = channel
        self.total = total
        self.last24h = last24h
        self.last7d = last7d
    }

    public var id: String { channel.rawValue }
}

/// A snapshot of download counts across all channels, fetched from the stats
/// endpoint. Mirrors `ProviderQuotaSnapshot`'s role: one coherent reading, with
/// an availability the UI can render instead of inventing numbers.
public struct DownloadMonitorSnapshot: Codable, Sendable, Equatable {
    /// The project the counts belong to (the endpoint's own path segment).
    public let project: String
    /// Channels in the order the endpoint reported them.
    public let channels: [DownloadChannelStat]
    /// When this app received the reading.
    public let fetchedAt: Date
    public let availability: DataAvailability
    /// A short, desensitized reason when `availability` is not `valid`.
    public let diagnosticCode: String?

    public init(
        project: String,
        channels: [DownloadChannelStat],
        fetchedAt: Date,
        availability: DataAvailability,
        diagnosticCode: String? = nil
    ) {
        self.project = project
        self.channels = channels
        self.fetchedAt = fetchedAt
        self.availability = availability
        self.diagnosticCode = diagnosticCode
    }

    /// The stat for one channel, or nil when the endpoint did not report it.
    public func stat(for channel: DownloadChannel) -> DownloadChannelStat? {
        channels.first { $0.channel == channel }
    }

    /// All-time total across channels. Zero when nothing was reported — the UI
    /// shows "暂无数据" from `availability` instead of leaning on this.
    public var total: Int {
        channels.reduce(0) { $0 + $1.total }
    }
}

/// Presentation helpers for download counts. Pure formatting only, so the
/// dashboard and the settings page cannot drift apart.
public enum DownloadCountFormat {
    /// A channel count with thin thousands separators, e.g. "1,234".
    public static func text(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        return formatter.string(from: NSNumber(value: count)) ?? "\(count)"
    }

    /// The rolling-window subtitle for one channel, or nil when the endpoint
    /// reports no windows for it.
    public static func windowText(_ stat: DownloadChannelStat) -> String? {
        var parts: [String] = []
        if let last24h = stat.last24h { parts.append("24 小时 +\(text(last24h))") }
        if let last7d = stat.last7d { parts.append("7 天 +\(text(last7d))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
