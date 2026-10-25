import SwiftUI

/// Download monitor setup: the landing-page netdisk download counter.
///
/// The counts are not read from the netdisk vendors (neither exposes download
/// numbers to third-party clients) — the landing page reports button clicks to
/// ling's own stats service, which also folds in GitHub release counts. This
/// page only configures the switch, the endpoint, and shows the live state.
public struct DownloadsTab: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var coordinator: AppCoordinator
    @State private var urlText = ""
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
        _urlText = State(initialValue: store.settings.downloadMonitorURL)
    }

    public var body: some View {
        Form {
            switchSection
            endpointSection
            statusSection
            feedbackSection
        }
        .formStyle(.grouped)
        .onChange(of: store.settings.downloadMonitorURL) { _, newValue in
            if urlText != newValue { urlText = newValue }
        }
    }

    private var switchSection: some View {
        Section {
            Toggle("监控落地页网盘下载", isOn: enabledBinding)
            Text("开启后，额度弹窗会显示落地页网盘按钮的点击次数，以及 GitHub 直链的下载次数。数据由 lingai.net 的统计服务聚合，每 5 分钟刷新一次；关闭后不再发起任何网络请求。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var endpointSection: some View {
        Section("统计端点") {
            TextField(
                "默认：\(AIUnderlayKit.downloadMonitorDefaultURL)",
                text: $urlText,
                prompt: Text(AIUnderlayKit.downloadMonitorDefaultURL)
            )
            .textFieldStyle(.roundedBorder)
            .onSubmit { saveURL() }

            HStack {
                Button("保存端点") { saveURL() }
                    .disabled(!urlChanged)
                Button("使用默认端点") { resetURL() }
                    .disabled(!urlChanged)
            }

            Text("留空并使用默认端点。只有你自己的服务需要被轮询；页面本身的点击上报不经过本应用。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        Section("当前状态") {
            if !store.settings.downloadMonitorEnabled {
                Label("未开启", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            } else if let error = coordinator.downloadError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let snapshot = coordinator.downloadSnapshot, snapshot.availability == .valid {
                ForEach(snapshot.channels) { stat in
                    HStack {
                        Text(stat.channel.displayName)
                        Spacer()
                        Text(DownloadCountFormat.text(stat.total))
                            .bold()
                            .monospacedDigit()
                        if let windows = DownloadCountFormat.windowText(stat) {
                            Text(windows)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.callout)
                }
                Text("更新于 \(snapshot.fetchedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if coordinator.isRefreshingDownloads {
                Label("正在获取…", systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Label("尚无数据", systemImage: "circle.dashed")
                    .foregroundStyle(.secondary)
            }

            Button("立即刷新") { coordinator.refreshNow() }
                .disabled(!store.settings.downloadMonitorEnabled || coordinator.isRefreshingDownloads)
        }
    }

    @ViewBuilder
    private var feedbackSection: some View {
        if let feedback {
            Section {
                Label(feedback.text, systemImage: feedbackSymbol(feedback.kind))
                    .font(.caption)
                    .foregroundStyle(feedbackColor(feedback.kind))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var urlChanged: Bool {
        urlText.trimmingCharacters(in: .whitespacesAndNewlines)
            != store.settings.downloadMonitorURL
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { store.settings.downloadMonitorEnabled },
            set: { setEnabled($0) }
        )
    }

    private func setEnabled(_ enabled: Bool) {
        store.update { $0.downloadMonitorEnabled = enabled }
        feedback = store.persistenceError.map { Feedback(kind: .error, text: $0) }
    }

    private func saveURL() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            resetURL()
            return
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            feedback = Feedback(kind: .error, text: "请使用 http:// 或 https:// 开头的完整地址。")
            return
        }
        store.update { $0.downloadMonitorURL = trimmed }
        feedback = store.persistenceError.map { Feedback(kind: .error, text: $0) }
    }

    private func resetURL() {
        urlText = ""
        store.update { $0.downloadMonitorURL = "" }
        feedback = store.persistenceError.map { Feedback(kind: .error, text: $0) }
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
}
