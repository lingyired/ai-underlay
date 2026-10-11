import SwiftUI
import AppKit

/// 诊断：显示实测几何与覆盖层状态，并提供脱敏复制。
public struct DiagnosticsTab: View {
    @State private var snapshot = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("诊断")
                .font(.title2)

            ScrollView {
                Text(snapshot.isEmpty ? "点击“刷新”。" : snapshot)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 280)

            HStack {
                Button("刷新") { snapshot = collect() }
                Button("复制（已脱敏）") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snapshot, forType: .string)
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
        return CodexBarCLIClient.desensitize(lines.joined(separator: "\n"))
    }
}