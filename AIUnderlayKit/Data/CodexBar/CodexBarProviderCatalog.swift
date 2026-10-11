import Foundation

/// One provider as reported by `codexbar config providers`.
public struct ProviderInfo: Identifiable, Sendable, Equatable {
    public let id: String
    public let displayName: String
    /// Whether the provider is currently enabled in CodexBar's own config.
    public let enabledInCodexBar: Bool
    public let defaultEnabled: Bool

    public init(id: String, displayName: String, enabledInCodexBar: Bool, defaultEnabled: Bool) {
        self.id = id
        self.displayName = displayName
        self.enabledInCodexBar = enabledInCodexBar
        self.defaultEnabled = defaultEnabled
    }
}

/// Lists the providers CodexBar knows about. This is our own view of the
/// catalog; it never changes CodexBar's config by itself.
public enum CodexBarProviderCatalog {
    public static func parse(_ data: Data) throws -> [ProviderInfo] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return array.compactMap { entry in
            guard let id = entry["provider"] as? String else { return nil }
            return ProviderInfo(
                id: id,
                displayName: (entry["displayName"] as? String) ?? id,
                enabledInCodexBar: (entry["enabled"] as? Bool) ?? false,
                defaultEnabled: (entry["defaultEnabled"] as? Bool) ?? false
            )
        }
    }
}

/// A `QuotaEngine` capability: enumerate providers and toggle their enablement
/// in the upstream CLI config.
public protocol ProviderCatalogEngine: Sendable {
    func listProviders() async throws -> [ProviderInfo]
    /// Enables/disables a provider in the upstream CLI config. This **modifies
    /// shared config** and must only be called after explicit user confirmation.
    func setProviderEnabled(_ provider: String, enabled: Bool) async throws
    /// Sets an API key for a provider that supports it, via stdin.
    func setAPIKey(provider: String, key: String) async throws
}

extension CodexBarEngine: ProviderCatalogEngine {
    public func listProviders() async throws -> [ProviderInfo] {
        let env = ProxyEnvironment.mergedEnvironment(override: proxyOverride)
        let data = try await client.run(executable: executableURL,
                                        args: ["config", "providers", "--json", "--no-color"],
                                        timeout: 20, environment: env)
        return try CodexBarProviderCatalog.parse(data)
    }

    public func setProviderEnabled(_ provider: String, enabled: Bool) async throws {
        let env = ProxyEnvironment.mergedEnvironment(override: proxyOverride)
        _ = try await client.run(executable: executableURL,
                                 args: ["config", enabled ? "enable" : "disable", "--provider", provider, "--no-color"],
                                 timeout: 20, environment: env)
    }

    public func setAPIKey(provider: String, key: String) async throws {
        let env = ProxyEnvironment.mergedEnvironment(override: proxyOverride)
        _ = try await client.run(executable: executableURL,
                                 args: ["config", "set-api-key", "--provider", provider, "--stdin", "--no-color"],
                                 timeout: 20, environment: env,
                                 stdin: Data((key + "\n").utf8))
    }
}