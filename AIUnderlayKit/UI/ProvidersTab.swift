import SwiftUI

/// 服务商设置：只列出本应用支持的两家（Codex 与 Claude Code）。
/// 额度数据仍来自 CodexBar CLI，因此这里保留「启用上游」入口——Claude 在
/// CodexBar 里默认是关闭的，不启用就拿不到它的额度。
public struct ProvidersTab: View {
    @State private var catalog: [String: ProviderInfo] = [:]
    @State private var snapshots: [String: ProviderQuotaSnapshot] = [:]
    @State private var loading = true
    @State private var message = ""

    public init() {}

    private var providers: [String] { AIUnderlayKit.supportedProviders }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("服务商").font(.title2)
                Spacer()
                Button("测试连接") { refresh(test: true) }
                Button("刷新") { refresh(test: false) }
            }

            Text("本应用目前仅支持 Codex 与 Claude Code。额度数据来自 CodexBar CLI；若某家显示「未在上游启用」，需要先启用它才能取到额度。")
                .font(.caption).foregroundStyle(.secondary)

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(providers, id: \.self) { id in
                    ProviderRowView(
                        id: id,
                        displayName: displayName(for: id),
                        upstreamEnabled: catalog[id]?.enabledInCodexBar ?? false,
                        status: statusText(for: id),
                        windows: windowsText(for: id),
                        onEnableUpstream: { enableUpstream(id) }
                    )
                }
            }

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { refresh(test: false) }
    }

    private func displayName(for id: String) -> String {
        catalog[id]?.displayName ?? DashboardModel.displayName(for: id)
    }

    private func statusText(for id: String) -> String {
        switch snapshots[id]?.availability {
        case .valid, .stale: return "已登录"
        case .unauthenticated: return "未登录"
        case .unsupported: return "不支持"
        case .unavailable: return "不可用"
        default: return "—"
        }
    }

    private func windowsText(for id: String) -> String {
        snapshots[id]?.windowsLongestFirst.map(\.label).joined(separator: " / ") ?? ""
    }

    private func enableUpstream(_ id: String) {
        Task {
            do {
                try await AppCoordinator.shared?.setCodexBarProviderEnabled(id, enabled: true)
                message = "已在上游启用 \(id)。"
                await loadCatalog()
            } catch {
                message = "启用失败：\(CodexBarCLIClient.desensitize("\(error)"))"
            }
        }
    }

    private func refresh(test: Bool) {
        if test { AppCoordinator.shared?.refreshNow() }
        Task { await loadCatalog() }
    }

    private func loadCatalog() async {
        loading = true
        defer { loading = false }
        guard let coordinator = AppCoordinator.shared else { return }
        var list = coordinator.availableProviders
        if list.isEmpty { list = await coordinator.refreshProviderCatalog() }
        catalog = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
        snapshots = coordinator.liveSnapshots
        if list.isEmpty { message = "未能获取服务商目录。" }
    }
}

/// One supported provider: name/id, upstream status, login status, and an
/// "enable upstream" action for providers not yet enabled in CodexBar.
struct ProviderRowView: View {
    let id: String
    let displayName: String
    let upstreamEnabled: Bool
    let status: String
    let windows: String
    let onEnableUpstream: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                Text(id).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if !windows.isEmpty {
                Text(windows).font(.caption2).foregroundStyle(.secondary)
            }

            if upstreamEnabled {
                Text("已在上游启用").font(.caption2).foregroundStyle(.green)
            } else {
                Button("启用上游") { onEnableUpstream() }
                    .controlSize(.small)
                    .help("调用 codexbar config enable，会修改共享配置")
            }

            Text(status)
                .font(.caption2)
                .foregroundStyle(status == "已登录" ? .green : .secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }
}