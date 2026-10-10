import SwiftUI

/// Engine tab: external CLI detection, compatibility, managed install/uninstall.
public struct EngineTab: View {
    @State private var message = ""

    public init() {}

    public var body: some View {
        Form {
            Section("External CLI") {
                if let coordinator = AppCoordinator.shared {
                    let candidates = coordinator.engineManager.candidates
                    if candidates.isEmpty {
                        Text("No CodexBar CLI found.").foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.url.path) { candidate in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.url.path).font(.system(.caption, design: .monospaced))
                                Text("version \(candidate.version ?? "?") · \(String(describing: candidate.compatibility))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if coordinator.engineManager.hasIncompatibleOnly {
                        Text("A CLI was found but is not compatible. Install the managed build below.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            Section("Managed CLI") {
                Text(CLIInventory.managedCLIPath().path)
                    .font(.system(.caption, design: .monospaced))
                HStack {
                    Button("Re-detect") {
                        AppCoordinator.shared?.startEngine()
                        message = "Re-detected."
                    }
                    if DistributionProfile.current() == .github {
                        Button("Uninstall Managed CLI") {
                            AppCoordinator.shared?.uninstallManagedCLI()
                            message = "Removed only the app-managed binary."
                        }
                    }
                }
                if DistributionProfile.current() == .appStore {
                    Text("This build does not download executables. Install CodexBar yourself; the app will detect it.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("Managed install requires a pinned release URL and SHA-256; set them in CodexBarInstaller.Release before enabling the download button.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
