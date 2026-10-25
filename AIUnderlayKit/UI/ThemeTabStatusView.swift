import SwiftUI

struct ThemeTabStatusMessage: Equatable {
    var text: String
    var warning: Bool
}

/// Top inset feedback: visible from any form action, with persistence recovery.
struct ThemeTabStatusView: View {
    let status: ThemeTabStatusMessage
    let persistenceError: String?
    let retrySave: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: status.warning
                  ? "exclamationmark.triangle.fill"
                  : "checkmark.circle.fill")
                .foregroundStyle(status.warning ? Color.orange : Color.green)
                .accessibilityHidden(true)
            Text(status.text)
                .font(.callout)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            if persistenceError != nil {
                Button("重试保存", action: retrySave)
                    .buttonStyle(.borderless)
            }
            Button("关闭提示", systemImage: "xmark", action: dismiss)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .help("关闭提示")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Divider() }
    }
}
