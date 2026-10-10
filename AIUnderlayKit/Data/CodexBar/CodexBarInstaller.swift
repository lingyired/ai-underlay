import Foundation
import CryptoKit

/// Which distribution channel this build targets. App Store builds must not
/// download or execute binaries at runtime, so the managed-install capability is
/// compiled in but disabled by profile.
public enum DistributionProfile: String, Sendable {
    /// GitHub / Developer ID: managed install is allowed.
    case github
    /// Mac App Store: managed install is disabled; external CLI only.
    case appStore

    /// Resolved from an Info.plist key so the same source can ship both ways.
    public static func current(bundle: Bundle = .main) -> DistributionProfile {
        let raw = bundle.object(forInfoDictionaryKey: "AIUnderlayDistributionProfile") as? String
        return DistributionProfile(rawValue: raw ?? "") ?? .github
    }
}

public enum InstallerError: Error, Equatable {
    case managedInstallDisabled
    case downloadFailed(String)
    case checksumMismatch(expected: String, actual: String)
    case extractionFailed(String)
    case rollbackFailed(String)
}

/// Downloads, verifies, and installs the managed CodexBar CLI into the app's own
/// Application Support directory. Never touches /usr/local/bin, never needs
/// sudo, and never upgrades an external CLI the user already has.
@MainActor
public final class CodexBarInstaller {
    /// A pinned, tested release. Update deliberately, never "latest".
    public struct Release: Sendable, Equatable {
        public var version: String
        public var arm64URL: URL
        public var x86URL: URL
        public var sha256Arm64: String
        public var sha256X86: String

        public init(version: String, arm64URL: URL, x86URL: URL, sha256Arm64: String, sha256X86: String) {
            self.version = version
            self.arm64URL = arm64URL
            self.x86URL = x86URL
            self.sha256Arm64 = sha256Arm64
            self.sha256X86 = sha256X86
        }
    }

    public typealias Downloader = @Sendable (URL) async throws -> Data

    private let release: Release
    private let profile: DistributionProfile
    private let home: URL
    private let downloader: Downloader

    public init(
        release: Release,
        profile: DistributionProfile = .current(),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        downloader: @escaping Downloader = CodexBarInstaller.urlSessionDownloader
    ) {
        self.release = release
        self.profile = profile
        self.home = home
        self.downloader = downloader
    }

    public var installURL: URL { CLIInventory.managedCLIPath(home: home) }

    /// Downloads and installs. On any failure the previous binary (if any) is
    /// restored, so a partial install never leaves a broken CLI.
    public func install() async throws {
        guard profile == .github else { throw InstallerError.managedInstallDisabled }

        let isArm = ProcessInfo.processInfo.machineArchitectureIsARM64
        let url = isArm ? release.arm64URL : release.x86URL
        let expectedSHA = isArm ? release.sha256Arm64 : release.sha256X86

        let data: Data
        do {
            data = try await downloader(url)
        } catch {
            throw InstallerError.downloadFailed("\(error)")
        }

        let actualSHA = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actualSHA == expectedSHA.lowercased() else {
            throw InstallerError.checksumMismatch(expected: expectedSHA.lowercased(), actual: actualSHA)
        }

        try FileManager.default.createDirectory(
            at: installURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let backup = installURL.appendingPathExtension("bak")
        let hadExisting = FileManager.default.fileExists(atPath: installURL.path)
        if hadExisting {
            try? FileManager.default.removeItem(at: backup)
            try FileManager.default.moveItem(at: installURL, to: backup)
        }

        do {
            try data.write(to: installURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installURL.path)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            // Roll back to the previous binary.
            if hadExisting {
                try? FileManager.default.removeItem(at: installURL)
                do { try FileManager.default.moveItem(at: backup, to: installURL) }
                catch { throw InstallerError.rollbackFailed("\(error)") }
            }
            throw InstallerError.extractionFailed("\(error)")
        }
    }

    public func uninstall() {
        // Only remove what we manage.
        try? FileManager.default.removeItem(at: installURL)
        try? FileManager.default.removeItem(at: installURL.appendingPathExtension("bak"))
    }

    /// Real downloader using URLSession.
    public static let urlSessionDownloader: Downloader = { url in
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw InstallerError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        return data
    }
}

extension ProcessInfo {
    var machineArchitectureIsARM64: Bool {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafeBytes(of: &sysinfo.machine) { raw -> String in
            let bytes = raw.prefix { $0 != 0 }
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine == "arm64"
    }
}
