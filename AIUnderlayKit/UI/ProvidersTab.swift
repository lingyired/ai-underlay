import Combine
import SwiftUI

/// Service connection setup. The app-level switch controls rendering and
/// fetching; the upstream switch only controls whether CodexBar may collect
/// quota for that provider.
public struct ProvidersTab: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var coordinator: AppCoordinator
    @State private var catalog: [String: ProviderInfo] = [:]
    @State private var snapshots: [String: ProviderQuotaSnapshot] = [:]
    @State private var isLoading = true
    @State private var isTesting = false
    @State private var testDidStart = false
    @State private var testStartRevision = 0
    @State private var enablingUpstream: Set<String> = []
    @State private var feedback: Feedback?

    private struct Feedback: Equatable {
        enum Kind { case info, success, error }
        let kind: Kind
        let text: String
    }

    public init(store: SettingsStore) {
        self.store = store
        _coordinator = ObservedObject(
            wrappedValue: AppCoordinator.shared ?? AppCoordinator(settings: store)
        )
    }

    private var providers: [String] { AIUnderlayKit.supportedProviders }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("在这里选择要显示的服务商。额度由 CodexBar 读取；应用内开关关闭时，即使 CodexBar 已启用，也不会请求或显示该服务商。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if isLoading {
                loadingState
            } else {
                providerList
            }

            if let feedback {
                feedbackView(feedback)
            }
        }
        .padding()
        .task { await refreshFromCoordinator() }
        .onReceive(coordinator.$dataRevision.dropFirst()) { _ in
            syncFromCoordinator()
        }
        .onReceive(coordinator.$isRefreshingQuota) { refreshing in
            if ConnectionTestLifecycle.seesRefreshStart(
                isTesting: isTesting,
                emittedRefreshing: refreshing
            ) {
                testDidStart = true
            } else if ConnectionTestLifecycle.shouldComplete(
                isTesting: isTesting,
                didObserveStart: testDidStart,
                emittedRefreshing: refreshing
            ) {
                finishConnectionTest()
            }
        }
    }

    private var header: some View {
        HStack {
            Text("先确认 CodexBar 与登录状态，再决定是否显示额度。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if isTesting {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("正在检查服务连接")
            }
            Button("检查连接") { testConnection() }
                .disabled(
                    isLoading
                        || isTesting
                        || coordinator.isRefreshingQuota
                        || !enablingUpstream.isEmpty
                        || coordinator.engineManager.activeEngine == nil
                        || store.settings.enabledProviders.isEmpty
                )
            Button("刷新状态") { Task { await refreshFromCoordinator(forceCatalog: true) } }
                .disabled(isLoading || isTesting || !enablingUpstream.isEmpty)
        }
    }

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在读取 CodexBar 服务商状态…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var providerList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(providers, id: \.self) { id in
                    providerCard(id)
                }
            }
        }
    }

    private func providerCard(_ id: String) -> some View {
        let info = catalog[id]
        let enabled = store.settings.enabledProviders.contains(id)
        let connection = connectionStatus(for: id)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Toggle("", isOn: appEnabledBinding(for: id))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                    .help("在本应用请求并显示此服务商")
                    .accessibilityLabel("在本应用显示 \(displayName(for: id))")
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(for: id)).font(.headline)
                    Text(enabled ? "已在本应用显示" : "不在本应用显示")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(connection.title, systemImage: statusSymbol(connection))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor(connection))
            }

            Text(connection.detail)
                .font(.caption)
                .foregroundStyle(connection.needsAttention ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            if enabled {
                HStack(spacing: 12) {
                    if let windows = windowsText(for: id) {
                        Label(windows, systemImage: "chart.bar.xaxis")
                    }
                    Spacer()
                    if ProviderConnectionLogic.shouldShowUpstreamAction(
                        hasCatalogEntry: info != nil,
                        upstreamEnabled: info?.enabledInCodexBar == true
                    ) {
                        Button {
                            enableUpstream(id)
                        } label: {
                            if enablingUpstream.contains(id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Text("在 CodexBar 中启用")
                            }
                        }
                        .disabled(enablingUpstream.contains(id) || isTesting)
                        .help("修改 CodexBar 的共享服务商设置")
                    } else if let info {
                        Label(
                            info.enabledInCodexBar ? "已在 CodexBar 启用" : "CodexBar 中已关闭",
                            systemImage: info.enabledInCodexBar ? "checkmark.circle" : "minus.circle"
                        )
                        .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator.opacity(0.7))
        }
        .accessibilityElement(children: .contain)
    }

    private func feedbackView(_ feedback: Feedback) -> some View {
        Label(feedback.text, systemImage: feedbackSymbol(feedback.kind))
        .font(.caption)
        .foregroundStyle(feedbackColor(feedback.kind))
        .fixedSize(horizontal: false, vertical: true)
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

    private func displayName(for id: String) -> String {
        catalog[id]?.displayName ?? DashboardModel.displayName(for: id)
    }

    private func connectionStatus(for id: String) -> ProviderConnectionStatus {
        let appEnabled = store.settings.enabledProviders.contains(id)
        if appEnabled, !isTesting, catalog[id] != nil, catalog[id]?.enabledInCodexBar == false {
            return .upstreamDisabled
        }
        return ProviderConnectionLogic.status(
            appEnabled: appEnabled,
            hasCatalogEntry: catalog[id] != nil,
            hasEngine: coordinator.engineManager.activeEngine != nil,
            isChecking: isTesting,
            snapshot: snapshots[id],
            fetchFailed: coordinator.lastErrors[id] != nil
        )
    }

    private func statusSymbol(_ status: ProviderConnectionStatus) -> String {
        switch status {
        case .checking: return "arrow.triangle.2.circlepath"
        case .disabled: return "pause.circle"
        case .notChecked: return "questionmark.circle"
        case .appUnavailable: return "exclamationmark.magnifyingglass"
        case .upstreamDisabled: return "power"
        case .signedOut: return "person.crop.circle.badge.exclamationmark"
        case .unsupported: return "slash.circle"
        case .unavailable, .stale: return "exclamationmark.triangle"
        case .connected: return "checkmark.circle.fill"
        }
    }

    private func statusColor(_ status: ProviderConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .appUnavailable, .signedOut, .unsupported, .unavailable, .stale: return .orange
        case .checking: return .accentColor
        case .disabled, .notChecked, .upstreamDisabled: return .secondary
        }
    }

    private func windowsText(for id: String) -> String? {
        guard let windowLabels = snapshots[id]?.windowsLongestFirst.map({ DashboardModel.label(for: $0) }),
              !windowLabels.isEmpty
        else { return nil }
        return windowLabels.joined(separator: " / ")
    }

    private func appEnabledBinding(for id: String) -> Binding<Bool> {
        Binding(
            get: { store.settings.enabledProviders.contains(id) },
            set: { setEnabled(id, $0) }
        )
    }

    private func setEnabled(_ id: String, _ enabled: Bool) {
        store.update { settings in
            if enabled {
                if !settings.enabledProviders.contains(id) {
                    settings.enabledProviders.append(id)
                }
            } else {
                settings.enabledProviders.removeAll { $0 == id }
            }
        }
        feedback = store.persistenceError.map { Feedback(kind: .error, text: $0) }
    }

    private func testConnection() {
        guard !isTesting else { return }
        isTesting = true
        testDidStart = false
        testStartRevision = coordinator.dataRevision
        feedback = Feedback(kind: .info, text: "正在取得真实额度；完成前不会判定登录成功。")
        coordinator.refreshNow()
    }

    private func finishConnectionTest() {
        guard isTesting, testDidStart else { return }
        guard coordinator.dataRevision > testStartRevision else {
            isTesting = false
            syncFromCoordinator()
            feedback = Feedback(kind: .error, text: "检测没有返回新状态。请确认已启用至少一个服务商，并检查 CodexBar。")
            return
        }
        isTesting = false
        syncFromCoordinator()
        let statuses = providers
            .filter { store.settings.enabledProviders.contains($0) }
            .map { connectionStatus(for: $0) }
        if statuses.contains(where: \.isSuccess) {
            let count = statuses.filter(\.isSuccess).count
            feedback = Feedback(kind: .success, text: "检查完成：\(count) 个服务商取得有效额度。")
        } else {
            feedback = Feedback(kind: .error, text: "检查完成，但没有服务商连接成功。请查看上方原因。")
        }
    }

    private func enableUpstream(_ id: String) {
        guard !enablingUpstream.contains(id) else { return }
        enablingUpstream.insert(id)
        feedback = Feedback(kind: .info, text: "正在启用 \(displayName(for: id))…")
        Task {
            defer { enablingUpstream.remove(id) }
            do {
                try await coordinator.setCodexBarProviderEnabled(id, enabled: true)
                await refreshFromCoordinator(forceCatalog: true)
                feedback = Feedback(kind: .success, text: "CodexBar 已启用 \(displayName(for: id))。现在可检查连接。")
            } catch {
                feedback = Feedback(
                    kind: .error,
                    text: "未能启用 \(displayName(for: id))。\(friendlyError(error))"
                )
            }
        }
    }

    private func refreshFromCoordinator(forceCatalog: Bool = false) async {
        if forceCatalog {
            isLoading = true
        }
        if forceCatalog || coordinator.availableProviders.isEmpty {
            _ = await coordinator.refreshProviderCatalog()
        }
        syncFromCoordinator()
        isLoading = false
        if catalog.isEmpty {
            feedback = Feedback(
                kind: .error,
                text: coordinator.engineManager.activeEngine == nil
                    ? "未找到可用的 CodexBar CLI。请先在“引擎”中完成检测。"
                    : "无法读取服务商目录。请检查网络或代理设置后重试。"
            )
        }
    }

    private func syncFromCoordinator() {
        catalog = Dictionary(
            uniqueKeysWithValues: coordinator.availableProviders.map { ($0.id, $0) }
        )
        snapshots = coordinator.liveSnapshots
    }

    private func friendlyError(_ error: Error) -> String {
        let message: String
        switch error {
        case QuotaEngineError.unavailable:
            message = "未找到可用的 CodexBar CLI。"
        case CodexBarCLIError.timeout:
            message = "CodexBar 响应超时。"
        case CodexBarCLIError.launchFailed:
            message = "无法启动 CodexBar。"
        case CodexBarCLIError.nonZeroExit:
            message = "CodexBar 拒绝了操作。"
        default:
            message = "请稍后重试。"
        }
        return CodexBarCLIClient.desensitize(message)
    }
}
