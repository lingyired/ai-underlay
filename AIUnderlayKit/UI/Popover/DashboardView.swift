import SwiftUI

/// The menu-bar dashboard popup: one section per enabled provider, each showing
/// its quota windows as bars. Matches the look of the overlay bar's palette.
public struct DashboardView: View {
    @ObservedObject private var store: SettingsStore
    @ObservedObject private var coordinator: AppCoordinator
    @State private var sections: [DashboardSection] = []
    @State private var lastUpdated: Date?

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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(sections) { section in
                        ProviderSectionView(section: section)
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
        .onAppear(perform: reload)
        .onReceive(store.changes) { _ in reload() }
        .onReceive(coordinator.$dataRevision) { _ in reload() }
    }

    private var header: some View {
        HStack {
            Image(systemName: "gauge.with.dots.needle.bottom.50percent")
            Text("额度总览").font(.headline)
            Spacer()
            Button(action: { onRefresh(); reload() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help("立即刷新")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack {
            if let lastUpdated {
                Text("更新于 \(Self.relative(lastUpdated))")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("尚无数据").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("设置…") { onOpenSettings() }
                .buttonStyle(.plain)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func reload() {
        let snapshots = coordinator.dashboardSnapshots()
        sections = DashboardModel.sections(
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
        lastUpdated = snapshots.values.map(\.fetchedAt).max()
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) 秒前" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        return "\(seconds / 3600) 小时前"
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
                    }
                    if section.rows.count > 1 {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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
