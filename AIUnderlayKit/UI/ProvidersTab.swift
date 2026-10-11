import SwiftUI

/// 服务商列表：显示每个服务商、来源、登录状态、最近更新时间与额度窗口。
public struct ProvidersTab: View {
    @State private var rows: [ProviderRow] = []

    public init() {}

    struct ProviderRow: Identifiable {
        let id: String
        let providerId: String
        let source: String
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
            }

            Table(rows) {
                TableColumn("服务商", value: \.providerId)
                TableColumn("来源", value: \.source)
                TableColumn("登录", value: \.loginState)
                TableColumn("最近更新", value: \.lastUpdated)
                TableColumn("额度窗口", value: \.windows)
            }

            Text("仅在上游 CLI 明确支持时才会接受 API Key 输入；本应用不会伪造登录流程。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { reload(test: false) }
    }

    private func reload(test: Bool) {
        guard let coordinator = AppCoordinator.shared else { return }
        if test { coordinator.refreshNow() }
        let engine = coordinator.engineManager.activeEngine
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
                providerId: provider,
                source: engine?.id ?? "无",
                loginState: login,
                lastUpdated: updated,
                windows: windows
            )
        }
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) 秒前" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        return "\(seconds / 3600) 小时前"
    }
}
