import SwiftUI
import AIUnderlayKit

/// Provider list: shows each configured provider, its source, login state and
/// last successful update, with a per-provider test.
struct ProvidersTab: View {
    @State private var rows: [ProviderRow] = []

    struct ProviderRow: Identifiable {
        let id: String
        let providerId: String
        let source: String
        let loginState: String
        let lastUpdated: String
        let windows: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Providers").font(.title2)
                Spacer()
                Button("Test Connection") { reload(test: true) }
            }

            Table(rows) {
                TableColumn("Provider", value: \.providerId)
                TableColumn("Source", value: \.source)
                TableColumn("Login", value: \.loginState)
                TableColumn("Last update", value: \.lastUpdated)
                TableColumn("Windows", value: \.windows)
            }

            Text("API keys are only accepted for providers the upstream CLI explicitly supports; the app never invents a login flow.")
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
            case .valid, .stale: login = "signed in"
            case .unauthenticated: login = "not signed in"
            case .unsupported: login = "unsupported"
            case .unavailable: login = "unavailable"
            case .unknown, .none: login = "unknown"
            }
            let updated = snapshot.map { Self.relative($0.fetchedAt) } ?? "—"
            let windows = snapshot?.windowsLongestFirst.map(\.label).joined(separator: ", ") ?? "—"
            return ProviderRow(
                id: provider,
                providerId: provider,
                source: engine?.id ?? "none",
                loginState: login,
                lastUpdated: updated,
                windows: windows
            )
        }
    }

    private static func relative(_ date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}