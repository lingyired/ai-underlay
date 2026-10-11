import SwiftUI

/// 服务商设置：管理显示的服务商，并可从 CodexBar 目录中添加其他服务商。
public struct ProvidersTab: View {
    @State private var rows: [ProviderRow] = []
    @State private var catalog: [ProviderInfo] = []
    @State private var showAdd = false
    @State private var message = ""

    public init() {}

    struct ProviderRow: Identifiable {
        let id: String
        let displayName: String
        let loginState: String
        let lastUpdated: String
        let windows: String
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("服务商").font(.title2)
                Spacer()
                Button("测试连接") { reload(test: true) }
                Button("添加服务商…") { refreshCatalog(); showAdd = true }
            }

            Table(rows) {
                TableColumn("服务商", value: \.displayName)
                TableColumn("登录", value: \.loginState)
                TableColumn("最近更新", value: \.lastUpdated)
                TableColumn("额度窗口", value: \.windows)
            }

            if !message.isEmpty {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            Text("“添加服务商”只改变本应用显示哪些服务商；是否启用某服务商的登录由上游 CodexBar 决定。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { reload(test: false) }
        .sheet(isPresented: $showAdd) {
            AddProviderSheet(
                catalog: catalog,
                displayed: AppCoordinator.shared?.providers ?? [],
                onAdd: { id in
                    AppCoordinator.shared?.setProviderDisplayed(id, displayed: true)
                    reload(test: false)
                    showAdd = false
                },
                onRemove: { id in
                    AppCoordinator.shared?.setProviderDisplayed(id, displayed: false)
                    reload(test: false)
                },
                onClose: { showAdd = false }
            )
        }
    }

    private func reload(test: Bool) {
        guard let coordinator = AppCoordinator.shared else { return }
        if test { coordinator.refreshNow() }
        rows = coordinator.providers.map { provider in
            let snapshot = coordinator.liveSnapshots[provider]
            let login: String
            switch snapshot?.availability {
            case .valid, .stale: login = "已登录"
            case .unauthenticated: login = "未登录"
            case .unsupported: login = "不支持"
            case .unavailable: login = "不可用"
            case .unknown, .none: login = "未知"
            }
            let updated = snapshot.map { Self.relative($0.fetchedAt) } ?? "—"
            let windows = snapshot?.windowsLongestFirst.map(\.label).joined(separator: ", ") ?? "—"
            return ProviderRow(
                id: provider,
                displayName: DashboardModel.displayName(for: provider),
                loginState: login,
                lastUpdated: updated,
                windows: windows
            )
        }
    }

    private func refreshCatalog() {
        catalog = AppCoordinator.shared?.availableProviders ?? []
        if catalog.isEmpty {
            message = "尚未获取到服务商目录，请先到“引擎”页重新检测。"
        }
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) 秒前" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        return "\(seconds / 3600) 小时前"
    }
}

/// Sheet listing every provider CodexBar knows about, with add/remove.
struct AddProviderSheet: View {
    let catalog: [ProviderInfo]
    let displayed: [String]
    let onAdd: (String) -> Void
    let onRemove: (String) -> Void
    let onClose: () -> Void

    @State private var search = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("添加服务商").font(.headline)
                Spacer()
                Button("完成") { onClose() }
            }
            TextField("搜索…", text: $search)
                .textFieldStyle(.roundedBorder)

            if catalog.isEmpty {
                Text("目录为空。请先确认 CodexBar CLI 可用。")
                    .foregroundStyle(.secondary)
            } else {
                List(filtered, id: \.id) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.displayName)
                            Text(info.id).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if displayed.contains(info.id) {
                            Button("移除") { onRemove(info.id) }
                        } else {
                            Button("添加") { onAdd(info.id) }
                        }
                    }
                }
                .frame(minHeight: 320)
            }
        }
        .padding()
        .frame(width: 420, height: 460)
    }

    private var filtered: [ProviderInfo] {
        guard !search.isEmpty else { return catalog }
        return catalog.filter {
            $0.displayName.localizedCaseInsensitiveContains(search)
                || $0.id.localizedCaseInsensitiveContains(search)
        }
    }
}