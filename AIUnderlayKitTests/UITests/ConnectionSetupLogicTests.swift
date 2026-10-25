import XCTest
@testable import AIUnderlayKit

final class ConnectionSetupLogicTests: XCTestCase {
    func test_disabledProviderDoesNotClaimLoginState() {
        let status = ProviderConnectionLogic.status(
            appEnabled: false,
            hasCatalogEntry: true,
            hasEngine: true,
            isChecking: false,
            snapshot: snapshot(.unauthenticated),
            fetchFailed: false
        )
        XCTAssertEqual(status, .disabled)
    }

    func test_staleSnapshotNeverClaimsLoggedIn() {
        let status = ProviderConnectionLogic.status(
            appEnabled: true,
            hasCatalogEntry: true,
            hasEngine: true,
            isChecking: false,
            snapshot: snapshot(.stale),
            fetchFailed: false
        )
        guard case .stale = status else {
            return XCTFail("expected explicit stale status, got \(status)")
        }
        XCTAssertFalse(status.isSuccess)
    }

    func test_realSnapshotStaysUsefulWithoutCatalogMetadata() {
        let status = ProviderConnectionLogic.status(
            appEnabled: true,
            hasCatalogEntry: false,
            hasEngine: true,
            isChecking: false,
            snapshot: snapshot(.valid),
            fetchFailed: false
        )
        XCTAssertEqual(status, .connected)
    }

    func test_missingEngineIsDistinctFromNoData() {
        let status = ProviderConnectionLogic.status(
            appEnabled: true,
            hasCatalogEntry: false,
            hasEngine: false,
            isChecking: false,
            snapshot: nil,
            fetchFailed: false
        )
        XCTAssertEqual(status, .appUnavailable)
    }

    func test_connectionTestWaitsForObservedCompletion() {
        XCTAssertFalse(ConnectionTestLifecycle.shouldComplete(
            isTesting: true,
            didObserveStart: false,
            emittedRefreshing: false
        ))
        XCTAssertTrue(ConnectionTestLifecycle.seesRefreshStart(
            isTesting: true,
            emittedRefreshing: true
        ))
        XCTAssertFalse(ConnectionTestLifecycle.shouldComplete(
            isTesting: true,
            didObserveStart: true,
            emittedRefreshing: true
        ))
        XCTAssertTrue(ConnectionTestLifecycle.shouldComplete(
            isTesting: true,
            didObserveStart: true,
            emittedRefreshing: false
        ))
    }

    func test_proxyValidationAcceptsSupportedSchemesAndNormalizes() {
        XCTAssertEqual(
            ProxyAddressValidator.validate(" http://127.0.0.1:10808 "),
            .valid("http://127.0.0.1:10808")
        )
        XCTAssertNotNil(ProxyAddressValidator.validate("socks5://proxy.local:1080").normalizedValue)
        XCTAssertNotNil(ProxyAddressValidator.validate("https://proxy.local:443").normalizedValue)
        XCTAssertEqual(ProxyAddressValidator.validate("   "), .empty)
    }

    func test_proxyValidationExplainsUnsupportedInput() {
        for value in [
            "proxy.local:8080",
            "ftp://proxy.local:21",
            "http://proxy.local",
            "http://proxy.local:0",
            "http://proxy.local:65536",
            "http://:8080",
            "http://proxy.local:8080/path",
            "http://proxy.local:8080?token=secret",
        ] {
            let result = ProxyAddressValidator.validate(value)
            guard case .invalid(let message) = result else {
                return XCTFail("expected invalid result for \(value), got \(result)")
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.localizedCaseInsensitiveContains("secret"))
        }
    }

    func test_proxyValidationRejectsCredentialsWithoutEchoingThem() {
        let result = ProxyAddressValidator.validate("http://alice:secret@proxy.local:8080")
        guard case .invalid(let message) = result else {
            return XCTFail("expected invalid credentialed proxy")
        }
        XCTAssertFalse(message.contains("alice"))
        XCTAssertFalse(message.contains("secret"))
    }

    private func snapshot(_ availability: DataAvailability) -> ProviderQuotaSnapshot {
        ProviderQuotaSnapshot(
            id: "codex:default",
            providerId: "codex",
            accountKey: nil,
            sourceEngineId: "codexbar",
            windows: [],
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            availability: availability
        )
    }
}
