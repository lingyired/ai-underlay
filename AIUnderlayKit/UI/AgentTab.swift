import SwiftUI

/// Agent 检测设置。安装永远是“预览 → 确认”；应用绝不会自行修改
/// `~/.claude/settings.json`。
public struct AgentTab: View {
    @State private var preview: HookSetupCoordinator.ChangePreview?
    @State private var installed = false
    @State private var status = ""

    private let coordinator = HookSetupCoordinator()

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Agent 检测").font(.title2)
            Text("检测 Claude Code（以及 Codex 在宿主支持时）的生命周期，以便菜单栏显示“运行中 / 等待”状态。在你确认之前不会安装任何东西。")
                .font(.caption).foregroundStyle(.secondary)

            HStack {
                Button("预览 Hook 改动") {
                    preview = try? coordinator.preview()
                    status = ""
                }
                Button(installed ? "卸载 Hook" : "安装 Hook") {
                    if installed {
                        try? coordinator.uninstall()
                        installed = coordinator.isInstalled()
                        status = "已仅移除本应用添加的 Hook 条目。"
                    } else {
                        try? coordinator.install(confirmed: true)
                        installed = coordinator.isInstalled()
                        status = "已安装。修改前的设置已备份。"
                    }
                    preview = nil
                }
                .disabled(preview == nil && !installed)
            }

            if let preview {
                Text("将新增 \(preview.addedCommands.count) 条 Hook 条目。预览：")
                    .font(.caption)
                ScrollView {
                    Text(preview.after)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            }

            if !status.isEmpty {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { installed = coordinator.isInstalled() }
    }
}