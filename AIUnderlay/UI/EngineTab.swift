import SwiftUI
import AIUnderlayKit

/// Engine tab. Filled in during P2 (external CLI detection, managed install).
struct EngineTab: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Engine")
                .font(.title2)
            Text("CodexBar CLI detection and managed install arrive in P2.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}