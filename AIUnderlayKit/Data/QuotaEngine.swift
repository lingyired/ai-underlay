import Foundation

/// A discovery/probe result for an engine.
public struct EngineProbe: Sendable, Equatable {
    public var isAvailable: Bool
    public var compatibility: Compatibility
    public var version: String?
    public var executableURL: URL?

    public init(isAvailable: Bool, compatibility: Compatibility, version: String?, executableURL: URL?) {
        self.isAvailable = isAvailable
        self.compatibility = compatibility
        self.version = version
        self.executableURL = executableURL
    }
}

public enum QuotaEngineError: Error, Equatable {
    case unavailable
    case notLoggedIn
    case unsupportedProvider(String)
    case decodeFailed(String)
    case execution(CodexBarCLIError)
}

/// A source of quota snapshots. Renderers never see this type — adapters
/// produce domain `ProviderQuotaSnapshot` values.
public protocol QuotaEngine: Sendable {
    var id: String { get }
    func probe() async -> EngineProbe
    func fetch(provider: String, account: String?) async throws -> ProviderQuotaSnapshot
}

/// An engine whose binary this app can install, update, and remove.
public protocol ManagedQuotaEngine: QuotaEngine {
    func install() async throws
    func update() async throws
    func uninstall() async throws
}
