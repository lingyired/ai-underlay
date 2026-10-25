import Foundation

/// Failures the download monitor reports. Messages are deliberately generic —
/// a URL or credential never appears in an error, so logs and diagnostics stay
/// desensitized the same way the CLI path stays desensitized.
public enum DownloadMonitorError: Error, Equatable, Sendable {
    /// The configured endpoint is not a usable URL.
    case invalidURL
    /// The request never completed (DNS, TLS, timeout, connection reset).
    case transport
    /// A non-2xx HTTP status.
    case httpStatus(Int)
    /// The body was not the expected JSON shape.
    case decodeFailed
    /// The JSON parsed but reported no usable channel.
    case emptyChannels
}

/// Fetches landing-page download counts from the stats endpoint.
///
/// The endpoint is ling's own service on lingai.net: the landing page reports
/// netdisk button clicks to it, and it aggregates those with GitHub release
/// counts. One call returns every channel, so the app polls a single URL.
///
/// A GUI app has no shell proxy variables, so an explicit proxy override is
/// honoured the same way the quota CLI path honours one; an empty override
/// leaves the macOS system proxy settings in charge.
public struct DownloadMonitorClient: Sendable {
    private let session: URLSession

    public init(proxyOverride: String? = nil, session: URLSession? = nil) {
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.connectionProxyDictionary = Self.proxyDictionary(from: proxyOverride)
            self.session = URLSession(configuration: configuration)
        }
    }

    /// Fetches and decodes one snapshot. Throws `DownloadMonitorError` with a
    /// desensitized reason; the caller's retry policy treats every case alike.
    public func fetch(url: URL) async throws -> DownloadMonitorSnapshot {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DownloadMonitorError.transport
        }
        guard let http = response as? HTTPURLResponse else {
            throw DownloadMonitorError.httpStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DownloadMonitorError.httpStatus(http.statusCode)
        }
        return try Self.decode(data, projectFallback: url.lastPathComponent)
    }

    // MARK: - Decoding

    /// Tolerant wire shape: an unknown channel or a missing count is skipped,
    /// never guessed. A response that yields nothing usable is an error, so the
    /// scheduler's retry/backoff applies instead of showing a silent zero.
    private struct WireResponse: Decodable {
        let project: String?
        let channels: [WireChannel]?
    }

    private struct WireChannel: Decodable {
        let channel: String
        let total: Int?
        let last24h: Int?
        let last7d: Int?
    }

    static func decode(_ data: Data, projectFallback: String) throws -> DownloadMonitorSnapshot {
        let wire: WireResponse
        do {
            wire = try JSONDecoder().decode(WireResponse.self, from: data)
        } catch {
            throw DownloadMonitorError.decodeFailed
        }
        let stats: [DownloadChannelStat] = (wire.channels ?? []).compactMap { entry in
            guard let channel = DownloadChannel(rawValue: entry.channel),
                  let total = entry.total, total >= 0
            else { return nil }
            func window(_ value: Int?) -> Int? {
                guard let value, value >= 0 else { return nil }
                return value
            }
            return DownloadChannelStat(
                channel: channel,
                total: total,
                last24h: window(entry.last24h),
                last7d: window(entry.last7d)
            )
        }
        guard !stats.isEmpty else { throw DownloadMonitorError.emptyChannels }
        return DownloadMonitorSnapshot(
            project: wire.project ?? projectFallback,
            channels: stats,
            fetchedAt: Date(),
            availability: .valid
        )
    }

    // MARK: - Proxy

    /// Maps an explicit proxy override onto a `URLSessionConfiguration`
    /// dictionary. Returns nil for empty/invalid input, which leaves the
    /// system proxy settings in charge. The app's proxy field always carries
    /// an explicit port (enforced by `ProxyAddressValidator`), so a portless
    /// URL never reaches this path.
    static func proxyDictionary(from rawOverride: String?) -> [AnyHashable: Any]? {
        guard case .valid(let normalized) = ProxyAddressValidator.validate(rawOverride ?? ""),
              let components = URLComponents(string: normalized),
              let host = components.host, !host.isEmpty,
              let port = components.port
        else { return nil }

        let scheme = components.scheme?.lowercased() ?? "http"
        let proxyType: CFString
        switch scheme {
        case "http": proxyType = kCFProxyTypeHTTP
        case "https": proxyType = kCFProxyTypeHTTPS
        default: proxyType = kCFProxyTypeSOCKS
        }
        return [
            kCFProxyTypeKey: proxyType,
            kCFProxyHostNameKey: host,
            kCFProxyPortNumberKey: port,
        ]
    }
}
