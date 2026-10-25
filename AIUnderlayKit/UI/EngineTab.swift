import SwiftUI

/// Engine setup: external CLI discovery, proxy configuration, and removal of
/// files installed by this app. It never presents an unimplemented installer.
public struct EngineTab: View {
    @ObservedObject private var settings: SettingsStore
    @ObservedObject private var coordinator: AppCoordinator
    @State private var proxy = ""
    @State private var feedback: Feedback?
    @State private var isDetecting = false
    @State private var isRemovingManagedCLI = false

    private struct Feedback: Equatable {
        enum Kind { case info, success, error }
        let kind: Kind
        let text: String
    }

    public init() {
        let store = AppCoordinator.shared?.settings ?? SettingsStore()
        let liveCoordinator = AppCoordinator.shared ?? AppCoordinator(settings: store)
        _settings = ObservedObject(wrappedValue: store)
        _coordinator = ObservedObject(wrappedValue: liveCoordinator)
        _proxy = State(initialValue: store.settings.proxyOverride)
    }

    public var body: some View {
        Form {
            detectionSection
            proxySection
            managedSection
            feedbackSection
        }
        .formStyle(.grouped)
        .onChange(of: settings.settings.proxyOverride) { _, newValue in
            proxy = newValue
        }
    }

    private var detectionSection: some View {
        Section("CodexBar 连接") {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if coordinator.engineManager.activeEngine != nil {
                        Label("已找到 CodexBar", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("数据源已就绪；登录与额度状态请在「服务商」中查看。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Label("未找到可用 CLI", systemImage: "exclamationmark.magnifyingglass")
                            .foregroundStyle(.orange)
                        Text("先安装 CodexBar。Homebrew 用户可运行：")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("brew install --cask codexbar")
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                        Link(
                            "打开 CodexBar 官方项目",
                            destination: URL(string: "https://github.com/steipete/CodexBar")!
                        )
                        .font(.caption)
                    }
                }
                Spacer()
                if isDetecting {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在检测 CodexBar")
                }
                Button("重新检测") { detectEngine() }
                    .disabled(isDetecting || isRemovingManagedCLI)
            }

            if !coordinator.engineManager.candidates.isEmpty {
                DisclosureGroup("检测到的 CLI") {
                    ForEach(coordinator.engineManager.candidates, id: \.url.path) { candidate in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(candidate.url.path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                            Text(
                                "\(candidate.version ?? "未知版本") · "
                                    + Self.compatibilityLabel(candidate.compatibility)
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var proxySection: some View {
        Section("网络代理") {
            TextField(
                "代理地址（留空则使用系统代理）",
                text: $proxy,
                prompt: Text("http://127.0.0.1:10808")
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveProxy() }

            if let error = proxyValidation.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else {
                Text("支持 HTTP、HTTPS、SOCKS5。为保护凭据，不接受用户名或密码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("保存代理并重新检测") { saveProxy() }
                    .disabled(isDetecting || isRemovingManagedCLI || proxyValidation.errorMessage != nil)
                Button("使用系统代理") { clearProxy() }
                    .disabled(
                        proxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isDetecting
                            || isRemovingManagedCLI
                    )
            }
        }
    }

    @ViewBuilder
    private var managedSection: some View {
        if managedCLIExists {
            Section("应用安装的 CLI") {
                Label("仅移除此应用安装的副本", systemImage: "internaldrive")
                Text(CLIInventory.managedCLIPath().path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack {
                    Button("卸载应用安装的 CLI", role: .destructive) {
                        uninstallManagedCLI()
                    }
                    .disabled(isDetecting || isRemovingManagedCLI)
                    if isRemovingManagedCLI {
                        ProgressView().controlSize(.small)
                            .accessibilityLabel("正在移除应用安装的 CLI")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let feedback {
            Section {
                Label(feedback.text, systemImage: feedbackSymbol(feedback.kind))
                .font(.caption)
                .foregroundStyle(feedbackColor(feedback.kind))
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func feedbackSymbol(_ kind: Feedback.Kind) -> String {
        switch kind {
        case .info: return "info.circle"
        case .success: return "checkmark.circle"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func feedbackColor(_ kind: Feedback.Kind) -> Color {
        switch kind {
        case .info: return .secondary
        case .success: return .green
        case .error: return .red
        }
    }

    private var proxyValidation: ProxyAddressValidation {
        ProxyAddressValidator.validate(proxy)
    }

    private var managedCLIExists: Bool {
        FileManager.default.fileExists(atPath: CLIInventory.managedCLIPath().path)
    }

    private func detectEngine() {
        guard !isDetecting else { return }
        isDetecting = true
        feedback = Feedback(kind: .info, text: "正在检查 CodexBar CLI…")
        coordinator.startEngine()
        isDetecting = false
        let active = coordinator.engineManager.activeEngine != nil
        feedback = Feedback(
            kind: active ? .success : .error,
            text: active
                ? "已找到 CodexBar CLI；额度与登录状态另行显示。"
                : "检测完成，但没有找到兼容的 CodexBar CLI。"
        )
    }

    private func saveProxy() {
        guard !isDetecting else { return }
        switch proxyValidation {
        case .invalid:
            return
        case .valid(let value):
            settings.update { $0.proxyOverride = value }
            guard settings.persistenceError == nil else {
                feedback = Feedback(
                    kind: .error,
                    text: settings.persistenceError ?? "代理设置未能保存。"
                )
                return
            }
            detectEngine()
        case .empty:
            clearProxy()
        }
    }

    private func clearProxy() {
        guard !isDetecting else { return }
        settings.update { $0.proxyOverride = "" }
        guard settings.persistenceError == nil else {
            feedback = Feedback(
                kind: .error,
                text: settings.persistenceError ?? "代理设置未能保存。"
            )
            return
        }
        detectEngine()
    }

    private func uninstallManagedCLI() {
        guard managedCLIExists, !isRemovingManagedCLI else { return }
        isRemovingManagedCLI = true
        feedback = Feedback(kind: .info, text: "正在移除应用安装的 CLI…")
        defer { isRemovingManagedCLI = false }
        do {
            try coordinator.uninstallManagedCLI()
            feedback = Feedback(kind: .success, text: "已移除应用安装的 CLI，并重新检测可用引擎。")
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            feedback = Feedback(kind: .info, text: "该文件已不存在，无需继续移除。")
        } catch {
            feedback = Feedback(
                kind: .error,
                text: "未能移除应用安装的 CLI。\(friendlyFileError(error))"
            )
        }
    }

    private func friendlyFileError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSFileWriteNoPermissionError:
            return "没有修改权限。请检查文件权限后再试。"
        case NSFileWriteOutOfSpaceError:
            return "磁盘空间不足。"
        default:
            return "请检查文件权限后重试。"
        }
    }

    private static func compatibilityLabel(_ compatibility: Compatibility) -> String {
        switch compatibility {
        case .compatible: return "可用"
        case .incompatible: return "版本不兼容或无法读取版本信息"
        case .notLoggedIn: return "CLI 可用，但尚未登录"
        }
    }
}
