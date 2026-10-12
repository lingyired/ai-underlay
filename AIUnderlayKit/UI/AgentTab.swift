import SwiftUI

/// Agent 检测设置。安装永远是“预览 → 确认”；应用绝不会自行修改
/// `~/.claude/settings.json` 或 `~/.codex/hooks.json`。
public struct AgentTab: View {
    @State private var preview: HookSetupCoordinator.ChangePreview?
    @State private var previewProvider: HookSetupCoordinator.Provider?
    @State private var installed: [HookSetupCoordinator.Provider: Bool] = [:]
    @State private var status = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent 检测").font(.title2)
            Text("通过官方生命周期 Hook 检测 Codex 与 Claude Code 的“运行中 / 等待”状态。在你确认之前不会安装任何东西。")
                .font(.caption).foregroundStyle(.secondary)

            ForEach(HookSetupCoordinator.Provider.allCases, id: \.self) { provider in
                providerRow(provider)
                if provider != HookSetupCoordinator.Provider.allCases.last {
                    Divider()
                }
            }

            if let preview {
                Text("将新增 \(preview.addedCommands.count) 条 Hook 条目（\(previewProvider?.rawValue ?? "")）。预览：")
                    .font(.caption)
                ScrollView {
                    Text(preview.after)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
            }

            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }

            Text("Codex 的非托管 Hook 首次运行前需要在 Codex 里用 `/hooks` 审核并信任；Claude Code 无需额外步骤。")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: refreshStates)
    }

    @ViewBuilder
    private func providerRow(_ provider: HookSetupCoordinator.Provider) -> some View {
        let coordinator = HookSetupCoordinator(provider: provider)
        let isInstalled = installed[provider] ?? false
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(provider))
                Text(coordinator.settingsURL.path)
                    .font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Button("预览 Hook 改动") {
                preview = try? coordinator.preview()
                previewProvider = provider
                status = ""
            }
            Button(isInstalled ? "卸载 Hook" : "安装 Hook") {
                if isInstalled {
                    try? coordinator.uninstall()
                    status = "已仅移除本应用为 \(displayName(provider)) 添加的 Hook 条目。"
                } else {
                    try? coordinator.install(confirmed: true)
                    status = "已为 \(displayName(provider)) 安装。修改前的设置已备份。"
                }
                preview = nil
                previewProvider = nil
                refreshStates()
            }
            .disabled(!isInstalled && (preview == nil || previewProvider != provider))
        }
    }

    private func displayName(_ provider: HookSetupCoordinator.Provider) -> String {
        switch provider {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    private func refreshStates() {
        installed = Dictionary(uniqueKeysWithValues: HookSetupCoordinator.Provider.allCases.map {
            ($0, HookSetupCoordinator(provider: $0).isInstalled())
        })
    }
}