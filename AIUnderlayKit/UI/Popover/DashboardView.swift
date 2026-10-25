import SwiftUI

/// The menu-bar dashboard popup: one section per enabled provider, each showing
/// its quota windows as bars. Matches the look of the overlay bar's palette.
public struct DashboardView: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var coordinator: AppCoordinator

    private let onRefresh: () -> Void
    private let onOpenSettings: () -> Void

    public init(coordinator: AppCoordinator, store: SettingsStore, onRefresh: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.coordinator = coordinator
        self.store = store
        self.onRefresh = onRefresh
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if store.settings.previewFixture != nil {
                HStack(alignment: .top, spacing: 8) {
                    Label("示例预览 · 非真实额度", systemImage: "eye")
                        .font(.caption)
                    Spacer(minLength: 0)
                    Button("退出") { store.update { $0.previewFixture = nil } }
                        .font(.caption)
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !store.settings.overlayEnabled {
                        Label("菜单栏显示已暂停，额度仍会更新", systemImage: "pause.circle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if sections.isEmpty {
                        ContentUnavailableView {
                            Label("尚未启用服务商", systemImage: "square.stack.3d.up")
                        } description: {
                            Text("打开设置，在「服务商」中启用 Codex 或 Claude Code。")
                        } actions: {
                            Button("打开设置", action: onOpenSettings)
                        }
                    }
                    ForEach(sections) { section in
                        ProviderSectionView(section: section)
                    }
                    if store.settings.downloadMonitorEnabled {
                        DownloadSectionView(
                            snapshot: coordinator.downloadSnapshot,
                            error: coordinator.downloadError,
                            isRefreshing: coordinator.isRefreshingDownloads
                        )
                    }
                    if !sections.isEmpty, sections.allSatisfy({ $0.rows.isEmpty }) {
                        Text(coordinator.engineManager.activeEngine == nil
                             ? "需要 CodexBar 提供额度数据。请打开设置，在「引擎」中检查连接。"
                             : "请打开设置，在「服务商」中检查启用状态与登录信息。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
            }
            .frame(maxHeight: 420)
            Divider()
            footer
        }
        .frame(width: 320)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            Text("额度总览").font(.headline)
            Spacer()
            Button("刷新额度", systemImage: "arrow.clockwise", action: onRefresh)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .disabled(coordinator.isRefreshingQuota || store.settings.previewFixture != nil
                      || coordinator.engineManager.activeEngine == nil || sections.isEmpty)
            .help(store.settings.previewFixture == nil ? "立即刷新真实额度" : "退出示例预览后可刷新真实额度")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(updateLabel(now: context.date))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("设置…") { onOpenSettings() }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var sections: [DashboardSection] {
        let snapshots = coordinator.dashboardSnapshots()
        return DashboardModel.sections(
            providers: coordinator.providers,
            snapshots: snapshots
        ).map { section in
            let summary = coordinator.agentSessionSummary(for: section.providerId)
            return DashboardSection(
                id: section.id, providerId: section.providerId, displayName: section.displayName,
                availability: section.availability, rows: section.rows,
                agentRunning: summary?.running,
                agentTotal: summary.map { $0.running + $0.idle + $0.waiting },
                agentWaiting: summary?.waiting
            )
        }
    }

    private func updateLabel(now: Date) -> String {
        if store.settings.previewFixture != nil { return "正在显示示例数据" }
        if coordinator.isRefreshingQuota { return "正在刷新…" }
        let snapshots = coordinator.dashboardSnapshots()
        guard let oldest = coordinator.providers.compactMap({ snapshots[$0]?.fetchedAt }).min() else {
            return "尚无额度数据"
        }
        let seconds = max(0, Int(now.timeIntervalSince(oldest)))
        if seconds < 60 { return "最近更新：\(seconds) 秒前" }
        if seconds < 3600 { return "最近更新：\(seconds / 60) 分钟前" }
        return "最近更新：\(seconds / 3600) 小时前"
    }
}

/// One provider section: name, status, and a bar per window. When the section
/// has more than one window the header is clickable to collapse/expand, and the
/// open/closed state persists across popup closes.
struct ProviderSectionView: View {
    let section: DashboardSection
    @State private var expanded: Bool

    init(section: DashboardSection) {
        self.section = section
        _expanded = State(initialValue: SectionExpansionStore.isExpanded(section.id))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                guard section.rows.count > 1 else { return }
                expanded.toggle()
                SectionExpansionStore.set(section.id, expanded: expanded)
            } label: {
                HStack {
                    Circle()
                        .fill(paletteColor)
                        .frame(width: 8, height: 8)
                    Text(section.displayName).font(.subheadline).bold()
                    if let running = section.agentRunning, let total = section.agentTotal,
                       let summary = DashboardModel.agentSummaryText(
                           running: running, idle: total - running - (section.agentWaiting ?? 0),
                           waiting: section.agentWaiting ?? 0) {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle((section.agentWaiting ?? 0) > 0
                                             ? Color.orange
                                             : running > 0 ? Color.green : Color.secondary)
                    }
                    Spacer()
                    if section.rows.isEmpty {
                        Text(DashboardModel.emptyStateText(for: section.availability))
                            .font(.caption).foregroundStyle(.secondary)
                    } else if section.availability != .valid {
                        Text(section.availability == .stale ? "缓存数据" : DashboardModel.emptyStateText(for: section.availability))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if section.rows.count > 1 {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(section.rows.count > 1 ? "展开或折叠额度窗口" : "")

            if expanded {
                ForEach(section.rows) { row in
                    MetricRowView(row: row, palette: paletteColor)
                }
            } else if let first = section.rows.first {
                // Collapsed: show only the most important (longest) window.
                MetricRowView(row: first, palette: paletteColor)
            }
        }
    }

    private var paletteColor: Color {
        let c = ProviderPalette.for(providerId: section.providerId).inner
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}

/// Remembers which provider sections are expanded across popup closes.
enum SectionExpansionStore {
    private static let key = "popover.expandedSections"

    static func isExpanded(_ id: String) -> Bool {
        // Default: expanded when never toggled.
        guard let dict = UserDefaults.standard.dictionary(forKey: key) as? [String: Bool] else { return true }
        return dict[id] ?? true
    }

    static func set(_ id: String, expanded: Bool) {
        var dict = (UserDefaults.standard.dictionary(forKey: key) as? [String: Bool]) ?? [:]
        dict[id] = expanded
        UserDefaults.standard.set(dict, forKey: key)
    }
}

/// A single quota window row: label, remaining percent, a bar with a baseline
/// tick, the reset countdown, and a pace note.
struct MetricRowView: View {
    let row: DashboardRow
    let palette: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(row.label).font(.caption)
                if let note = row.paceNote {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(percentText).font(.caption).bold()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.primary.opacity(0.12))
                    if let fraction = row.remainingFraction {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(palette)
                            .frame(width: max(0, min(1, fraction)) * geo.size.width)
                    }
                    // Even-pace baseline tick.
                    if let expected = row.expectedRemainingFraction {
                        Rectangle()
                            .fill(Color.primary.opacity(0.55))
                            .frame(width: 1.5)
                            .offset(x: max(0, min(1, expected)) * geo.size.width)
                    }
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
            if let reset = row.resetLabel() {
                Text(reset).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var percentText: String {
        guard let fraction = row.remainingFraction else { return "—" }
        return "\(Int((fraction * 100).rounded()))% 剩余"
    }
}

/// The landing-page download monitor section: one row per channel with its
/// cumulative count, plus rolling windows when the endpoint reports them.
/// Renders nothing quota-like — these are counts, never percentages.
struct DownloadSectionView: View {
    let snapshot: DownloadMonitorSnapshot?
    let error: String?
    let isRefreshing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.down.circle")
                Text("下载监控").font(.subheadline).bold()
                Spacer()
                if isRefreshing {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在刷新下载监控")
                }
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
            } else if let snapshot, snapshot.availability == .valid {
                ForEach(DownloadChannel.allCases, id: \.rawValue) { channel in
                    if let stat = snapshot.stat(for: channel) {
                        channelRow(stat)
                    }
                }
                if snapshot.total == 0 {
                    Text("尚无下载记录").font(.caption2).foregroundStyle(.secondary)
                }
                Text("更新于 \(snapshot.fetchedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("暂无数据").font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func channelRow(_ stat: DownloadChannelStat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(stat.channel.displayName).font(.caption)
                Spacer()
                Text(DownloadCountFormat.text(stat.total))
                    .font(.caption).bold()
                    .monospacedDigit()
            }
            if let windows = DownloadCountFormat.windowText(stat) {
                Text(windows).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
