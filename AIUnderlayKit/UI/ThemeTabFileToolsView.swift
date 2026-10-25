import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// File actions stay out of the main settings flow until requested.
struct ThemeTabFileToolsView: View {
    let themes: ThemeStore
    let reportStatus: ((text: String, warning: Bool)) -> Void
    @State private var expanded = false

    var body: some View {
        Section {
            DisclosureGroup(isExpanded: $expanded) {
                Text(themes.directoryURL.path)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("打开主题文件夹") {
                        NSWorkspace.shared.open(themes.directoryURL)
                    }
                    Button("重新载入", action: reload)
                }
                HStack {
                    Button("导出示例主题…", action: exportExample)
                    Button("复制主题编写说明", action: copyGuide)
                }
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Label("主题文件工具", systemImage: "folder")
                    Text("打开安装位置、重新载入、导出示例或复制编写说明")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func reload() {
        themes.reload()
        if themes.lastError == nil {
            reportStatus(("已重新载入 \(themes.themes.count) 个主题。", false))
        } else {
            reportStatus(("已载入可用主题；部分文件需要修正。", true))
        }
    }

    private func copyGuide() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(ThemePresets.authoringGuide, forType: .string)
        reportStatus(("主题编写说明已复制。", false))
    }

    private func exportExample() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(ThemePresets.selectedGlassV5.id).json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(ThemePresets.exampleJSON.utf8).write(to: url, options: .atomic)
            reportStatus(("示例主题已导出到「\(url.lastPathComponent)」。", false))
        } catch {
            reportStatus(("导出失败：\(error.localizedDescription)", true))
        }
    }
}
