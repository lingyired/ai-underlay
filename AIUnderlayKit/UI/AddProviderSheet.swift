import SwiftUI

/// 添加服务商。两种方式：
/// - **仅显示**：不改上游配置，只把服务商加到本应用的显示列表（复用你在 CodexBar 里的登录）。
/// - **在本应用启用**：调用 `codexbar config enable` 修改共享配置（需确认）。
struct AddProviderSheet: View {
    let catalog: [ProviderInfo]
    let displayed: [String]
    let onAddDisplay: (String) -> Void
    let onRemoveDisplay: (String) -> Void
    let onEnableUpstream: (String) -> Void
    let onClose: () -> Void

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("添加服务商").font(.headline)
                Spacer()
                Button("完成") { onClose() }
            }

            Text("配置与 CodexBar 共享：在 CodexBar 应用或 codexbar CLI 里启用的服务商，本应用会自动复用。你也可以在这里直接启用。")
                .font(.caption).foregroundStyle(.secondary)

            TextField("搜索…", text: $search)
                .textFieldStyle(.roundedBorder)

            if catalog.isEmpty {
                Text("目录为空。请先到“引擎”页重新检测，或确认 CodexBar CLI 可用。")
                    .foregroundStyle(.secondary)
            } else {
                List(filtered, id: \.id) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.displayName)
                            Text(info.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        // Upstream enablement badge.
                        if info.enabledInCodexBar {
                            Text("已在上游启用")
                                .font(.caption2).foregroundStyle(.green)
                        }
                        // Display toggle (our own list).
                        if displayed.contains(info.id) {
                            Button("移除") { onRemoveDisplay(info.id) }
                        } else {
                            Button("添加") { onAddDisplay(info.id) }
                        }
                        // Upstream enable (shared config) — only when not yet on.
                        if !info.enabledInCodexBar {
                            Button("启用上游") { onEnableUpstream(info.id) }
                                .help("调用 codexbar config enable，会修改共享配置")
                        }
                    }
                }
                .frame(minHeight: 320)
            }
        }
        .padding()
        .frame(width: 480, height: 500)
    }

    private var filtered: [ProviderInfo] {
        guard !search.isEmpty else { return catalog }
        return catalog.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
        }
    }
}