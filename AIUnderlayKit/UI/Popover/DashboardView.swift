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
        .onReceive(store.$settings) { _ in reload() }
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
        sections = DashboardModel.sections(
            providers: coordinator.providers,
            snapshots: coordinator.liveSnapshots
        )
        lastUpdated = coordinator.liveSnapshots.values.map(\.fetchedAt).max()
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds) 秒前" }
        if seconds < 3600 { return "\(seconds / 60) 分钟前" }
        return "\(seconds / 3600) 小时前"
    }
}

/// One provider section: name, status, and a bar per window.
struct ProviderSectionView: View {
    let section: DashboardSection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(paletteColor)
                    .frame(width: 8, height: 8)
                Text(section.displayName).font(.subheadline).bold()
                Spacer()
                if section.rows.isEmpty {
                    Text(DashboardModel.emptyStateText(for: section.availability))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(section.rows) { row in
                MetricRowView(row: row, palette: paletteColor)
            }
        }
    }

    private var paletteColor: Color {
        let c = ProviderPalette.for(providerId: section.providerId).inner
        return Color(red: c.red, green: c.green, blue: c.blue)
    }
}

/// A single quota window row: label, remaining percent, reset time, and a bar.
struct MetricRowView: View {
    let row: DashboardRow
    let palette: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(row.label).font(.caption)
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