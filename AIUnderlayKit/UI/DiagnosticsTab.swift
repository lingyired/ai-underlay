import SwiftUI
import AppKit

/// 诊断：显示实测几何与覆盖层状态，并提供脱敏复制。
public struct DiagnosticsTab: View {
    @State private var snapshot = ""
    @State private var copied = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("排查显示与连接问题时，可复制下方报告。报告不包含额度账户、代理地址或会话内容。")
                .font(.callout).foregroundStyle(.secondary)

            ScrollView {
                Text(snapshot.isEmpty ? "点击“刷新”。" : snapshot)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("刷新报告") { snapshot = collect(); copied = false }
                Button(copied ? "已复制报告" : "复制报告") {
                    NSPasteboard.general.clearContents()
                    copied = NSPasteboard.general.setString(snapshot, forType: .string)
                }
                .disabled(snapshot.isEmpty)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { snapshot = collect() }
    }

    private func collect() -> String {
        var lines: [String] = []
        lines.append("AIUnderlayKit \(AIUnderlayKit.version)")
        lines.append("显示器数量：\(NSScreen.screens.count)")
        for screen in NSScreen.screens {
            let id = MenuBarOverlayController.displayID(for: screen)
            let height = MenuBarOverlayController.menuBarHeight(for: screen)
            let notch = MenuBarGeometry.notchEdges(for: screen)
            lines.append("  显示器 \(id)：frame=\(screen.frame) scale=\(screen.backingScaleFactor)")
            lines.append("    菜单栏高度=\(height) 刘海=\(notch.map { "\($0)" } ?? "无")")
        }
        lines.append("管理的覆盖窗口数：\(AppCoordinator.shared?.overlay.managedBandCount ?? 0)")
        lines.append("屏幕上的覆盖窗口数：\(BandWatchdog.onScreenBandCount())")
        if let coordinator = AppCoordinator.shared {
            let settings = coordinator.settings.settings
            lines.append("菜单栏显示：\(settings.overlayEnabled ? "开启" : "暂停")")
            lines.append("数据模式：\(settings.previewFixture == nil ? "实时" : "示例预览")")
            lines.append("启用服务商：\(coordinator.providers.joined(separator: ", "))")
            lines.append("额度数据源：\(coordinator.engineManager.activeEngine == nil ? "未连接" : "已检测到兼容版本")")
            lines.append("刷新状态：\(coordinator.isRefreshingQuota ? "进行中" : "空闲")")
            lines.append("设置持久化：\(coordinator.settings.persistenceError == nil ? "正常" : "需要重试保存")")
            lines.append("Codex 活动检测：\(coordinator.codexRuntimeStatus.title)（不依赖 Hook）")
            lines.append("Codex 实时检测覆盖会话：\(coordinator.codexRuntimeSessionCount)")
            for provider in coordinator.providers {
                let snapshot = coordinator.liveSnapshots[provider]
                lines.append("  \(DashboardModel.displayName(for: provider))：\(snapshot?.availability.rawValue ?? "unknown")，额度窗口 \(snapshot?.windows.count ?? 0) 个，最近请求\(coordinator.lastErrors[provider] == nil ? "无错误记录" : "失败")")
                if let activity = coordinator.agentSessionSummary(for: provider) {
                    lines.append("    会话状态：运行 \(activity.running)，等待 \(activity.waiting)，空闲 \(activity.idle)")
                }
            }
        }
        return CodexBarCLIClient.desensitize(lines.joined(separator: "\n"))
    }
}
