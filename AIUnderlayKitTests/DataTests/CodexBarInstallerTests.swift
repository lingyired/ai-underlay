import XCTest
import CryptoKit
@testable import AIUnderlayKit

@MainActor
final class CodexBarInstallerTests: XCTestCase {
    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func makeInstaller(
        home: URL,
        payload: Data,
        declaredSHA: String,
        profile: DistributionProfile = .github,
        downloadFails: Bool = false
    ) -> CodexBarInstaller {
        let release = CodexBarInstaller.Release(
            version: "0.58.0",
            arm64URL: URL(string: "https://example.com/arm64")!,
            x86URL: URL(string: "https://example.com/x86")!,
            sha256Arm64: declaredSHA,
            sha256X86: declaredSHA
        )
        return CodexBarInstaller(
            release: release, profile: profile, home: home,
            downloader: { _ in
                if downloadFails { throw InstallerError.downloadFailed("network") }
                return payload
            }
        )
    }

    func test_install_writesExecutableAtManagedPath() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ih-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let payload = Data("#!/bin/sh\necho 'CodexBar 0.58.0'\n".utf8)
        let installer = makeInstaller(home: home, payload: payload, declaredSHA: sha256(payload))

        try await installer.install()
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installer.installURL.path))
        XCTAssertEqual(try Data(contentsOf: installer.installURL), payload)
    }

    func test_install_checksumMismatch_doesNotWrite() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ih-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let payload = Data("real".utf8)
        let installer = makeInstaller(home: home, payload: payload, declaredSHA: sha256(Data("other".utf8)))

        do {
            try await installer.install()
            XCTFail("expected checksum mismatch")
        } catch let error as InstallerError {
            if case .checksumMismatch = error {} else { XCTFail("wrong error: \(error)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.installURL.path))
    }

    func test_install_networkFailure_keepsPreviousBinary() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ih-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        // Pre-install a working binary.
        let managed = CLIInventory.managedCLIPath(home: home)
        try FileManager.default.createDirectory(at: managed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("old".utf8).write(to: managed)

        let installer = makeInstaller(home: home, payload: Data("new".utf8),
                                      declaredSHA: sha256(Data("new".utf8)), downloadFails: true)
        do {
            try await installer.install()
            XCTFail("expected download failure")
        } catch {}
        // The previous binary must still be there, unchanged.
        XCTAssertEqual(try Data(contentsOf: managed), Data("old".utf8))
    }

    func test_install_disabledInAppStoreProfile() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ih-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let payload = Data("x".utf8)
        let installer = makeInstaller(home: home, payload: payload,
                                      declaredSHA: sha256(payload), profile: .appStore)
        do {
            try await installer.install()
            XCTFail("expected disabled")
        } catch let error as InstallerError {
            XCTAssertEqual(error, .managedInstallDisabled)
        }
    }

    func test_uninstall_onlyRemovesManagedBinary() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ih-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        let payload = Data("#!/bin/sh\necho 'CodexBar 0.58.0'\n".utf8)
        let installer = makeInstaller(home: home, payload: payload, declaredSHA: sha256(payload))
        try await installer.install()
        XCTAssertTrue(FileManager.default.fileExists(atPath: installer.installURL.path))
        installer.uninstall()
        XCTAssertFalse(FileManager.default.fileExists(atPath: installer.installURL.path))
    }
}
