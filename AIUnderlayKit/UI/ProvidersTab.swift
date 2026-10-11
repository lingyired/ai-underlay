import SwiftUI

/// 服务商设置：直接列出 CodexBar 支持的全部服务商，勾选即显示。
/// 配置与 CodexBar 共享——在 CodexBar 或 CLI 里启用的服务商这里会显示“已在上游启用”。
public struct ProvidersTab: View {
    @State private var providers: [ProviderInfo] = []
    @State private var displayed: Set<String> = []
    @State private var snapshots: [String: ProviderQuotaSnapshot] = [:]
    @State private var search = ""
    @State private var loading = true
    @State private var message = ""

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("服务商").font(.title2)
                Spacer()
                Button("测试连接") { refresh(test: true) }
                Button("刷新目录") { refresh(test: false) }
            }

            Text("勾选即在覆盖层与弹窗中显示。配置与 CodexBar 共享：在 CodexBar 应用或 codexbar CLI 里启用的服务商，这里会标记为“已在上游启用”并可直接复用。")
                .font(.caption).foregroundStyle(.secondary)

            TextField("搜索服务商…", text: $search)
                .textFieldStyle(.roundedBorder)

            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if providers.isEmpty {
                Text("目录为空。请确认 CodexBar CLI 可用，然后点“刷新目录”。")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(filtered, id: \.id) { info in
                    ProviderRowView(
                        info: info,
                        isDisplayed: displayed.contains(info.id),
                        status: statusText(for: info.id),
                        windows: windowsText(for: info.id),
                        onToggleDisplay: { on in toggleDisplay(info.id, on: on) },
                        onEnableUpstream: { enableUpstream(info.id) }
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

    private var filtered: [ProviderInfo] {
        guard !search.isEmpty else { return providers }
        return providers.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
        }
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

    private func toggleDisplay(_ id: String, on: Bool) {
        if on { displayed.insert(id) } else { displayed.remove(id) }
        AppCoordinator.shared?.setProviderDisplayed(id, displayed: on)
    }

    private func enableUpstream(_ id: String) {
        Task {
            do {
                try await AppCoordinator.shared?.setCodexBarProviderEnabled(id, enabled: true)
                AppCoordinator.shared?.setProviderDisplayed(id, displayed: true)
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
        if let coordinator = AppCoordinator.shared {
            var list = coordinator.availableProviders
            if list.isEmpty { list = await coordinator.refreshProviderCatalog() }
            providers = list
            displayed = Set(coordinator.providers)
            snapshots = coordinator.liveSnapshots
            if list.isEmpty { message = "未能获取服务商目录。" }
        }
    }
}

/// One row: a checkbox, the name/id, upstream + login status, and an
/// "enable upstream" action for providers not yet enabled.
struct ProviderRowView: View {
    let info: ProviderInfo
    let isDisplayed: Bool
    let status: String
    let windows: String
    let onToggleDisplay: (Bool) -> Void
    let onEnableUpstream: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(get: { isDisplayed }, set: onToggleDisplay))
                .labelsHidden()
                .toggleStyle(.checkbox)

            VStack(alignment: .leading, spacing: 1) {
                Text(info.displayName)
                Text(info.id).font(.caption2).foregroundStyle(.secondary)
            }

            Spacer()

            if !windows.isEmpty {
                Text(windows).font(.caption2).foregroundStyle(.secondary)
            }

            if info.enabledInCodexBar {
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