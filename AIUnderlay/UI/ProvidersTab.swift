import SwiftUI
import AIUnderlayKit

/// Provider list. Filled in during P2; shows discovered providers and their
/// source/login state.
struct ProvidersTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Providers")
                .font(.title2)
            Text("Provider discovery and account selection arrive in P2.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}