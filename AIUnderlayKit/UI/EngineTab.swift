import SwiftUI

/// 引擎设置：外部 CLI 探测、兼容性、托管安装/卸载。
public struct EngineTab: View {
    @State private var message = ""
    @State private var proxy = ""

    public init() {}

    public var body: some View {
        Form {
            Section("外部 CLI") {
                if let coordinator = AppCoordinator.shared {
                    let candidates = coordinator.engineManager.candidates
                    if candidates.isEmpty {
                        Text("未找到 CodexBar CLI。").foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates, id: \.url.path) { candidate in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.url.path).font(.system(.caption, design: .monospaced))
                                Text("版本 \(candidate.version ?? "?") · \(Self.compatibilityLabel(candidate.compatibility))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if coordinator.engineManager.hasIncompatibleOnly {
                        Text("找到了 CLI 但版本不兼容。请在下方安装托管版本。")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
            }

            Section("托管 CLI") {
                Text(CLIInventory.managedCLIPath().path)
                    .font(.system(.caption, design: .monospaced))
                HStack {
                    Button("重新检测") {
                        AppCoordinator.shared?.startEngine()
                        message = "已重新检测。"
                    }
                    if DistributionProfile.current() == .github {
                        Button("卸载托管 CLI") {
                            AppCoordinator.shared?.uninstallManagedCLI()
                            message = "已删除仅由本应用安装的二进制。"
                        }
                    }
                }
                if DistributionProfile.current() == .appStore {
                    Text("此构建不会下载可执行文件。请自行安装 CodexBar，本应用会自动检测。")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("托管安装需要固定的发布地址与 SHA-256；启用下载前请先在 CodexBarInstaller.Release 中填写。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("代理") {
                TextField("代理地址（留空则使用系统代理）", text: $proxy, prompt: Text("http://127.0.0.1:10808"))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("保存并重新检测") {
                        AppCoordinator.shared?.settings.update { $0.proxyOverride = proxy.trimmingCharacters(in: .whitespaces) }
                        AppCoordinator.shared?.startEngine()
                        message = "已应用代理设置并重新检测。"
                    }
                    Text("Codex 等需要代理才能联网；GUI 应用默认读不到终端里的代理变量，这里可显式指定。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { proxy = AppCoordinator.shared?.settings.settings.proxyOverride ?? "" }
    }

    private static func compatibilityLabel(_ compatibility: Compatibility) -> String {
        switch compatibility {
        case .compatible: return "兼容"
        case .incompatible: return "不兼容"
        case .notLoggedIn: return "未登录"
        }
    }
}