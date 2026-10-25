import SwiftUI

/// Agent settings. Codex activity is detected automatically and needs no
/// Hook; Claude Code hooks stay optional and always require a preview plus an
/// explicit apply. The only Codex hook interaction left is manual cleanup of
/// entries an older version installed, and it appears strictly when our
/// marker is actually present in the file.
public struct AgentTab: View {
    @ObservedObject private var coordinator: AppCoordinator

    @State private var claudeState: HookSettingsStatus = .unknown
    @State private var codexLegacyHooks: CodexLegacyHookState = .checking
    @State private var isCodexCleanupExpanded = false
    @State private var codexCleanupError: String?
    @State private var preview: HookSetupCoordinator.ChangePreview?
    @State private var isWorking = false
    @State private var feedback: Feedback?

    private enum CodexLegacyHookState: Equatable {
        case checking
        case none
        case present
    }

    private struct Feedback: Equatable {
        enum Kind { case info, success, error }
        let kind: Kind
        let text: String
    }

    public init() {
        let store = AppCoordinator.shared?.settings ?? SettingsStore()
        _coordinator = ObservedObject(
            wrappedValue: AppCoordinator.shared ?? AppCoordinator(settings: store)
        )
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("应用自动读取本地会话与 Codex 运行状态，无需 Hook。实时检测需要 Codex Desktop 正在运行；未运行时会回退到日志检测，只能覆盖有限的等待状态。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                codexCard
                claudeCard

                if let preview {
                    previewCard(preview)
                }

                if let feedback {
                    Label(feedback.text, systemImage: feedbackSymbol(feedback.kind))
                        .font(.caption)
                        .foregroundStyle(feedbackColor(feedback.kind))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Claude Code 的 Hook 改动始终先预览再应用；应用不会自动安装或移除任何 Agent 配置。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .task { refreshStates() }
    }

    // MARK: - Codex

    private var codexCard: some View {
        let status = coordinator.codexRuntimeStatus
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Codex").font(.headline)
                    Text("自动检测，无需 Hook")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    if status == .connecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: codexSymbol(status))
                    }
                    Text(status.title)
                }
                .font(.caption)
                .foregroundStyle(color(for: status))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Codex 检测状态：\(status.title)")
            }

            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if codexLegacyHooks == .present {
                codexLegacyCleanup
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.7))
        }
    }

    private var codexLegacyCleanup: some View {
        DisclosureGroup(isExpanded: $isCodexCleanupExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("检测到旧版本安装的 Codex Hook 条目。它们已不参与状态判定；移除只删除带有本应用标记的条目，并在写入前备份。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let codexCleanupError {
                    Text(codexCleanupError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button("移除旧版 Codex Hook 条目", role: .destructive) {
                    removeCodexLegacyHooks()
                }
                .disabled(isWorking)

                if isWorking {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在移除旧版 Codex Hook 条目")
                }
            }
            .padding(.top, 6)
        } label: {
            Text("旧版 Hook 清理")
                .font(.caption.weight(.semibold))
        }
    }

    private func codexSymbol(_ status: CodexRuntimeStatus) -> String {
        switch status {
        case .connecting: return "arrow.triangle.2.circlepath"
        case .connected: return "checkmark.circle.fill"
        case .fallback: return "clock"
        }
    }

    private func color(for status: CodexRuntimeStatus) -> Color {
        switch status {
        case .connecting: return .secondary
        case .connected: return .green
        case .fallback: return .orange
        }
    }

    // MARK: - Claude Code

    private var claudeCard: some View {
        let state = claudeState
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude Code").font(.headline)
                    Text(claudeCoordinator.settingsURL.path)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Label(state.title, systemImage: symbol(for: state))
                    .font(.caption)
                    .foregroundStyle(color(for: state))
            }

            Text("可选增强：可更及时地发现“等待你回复”和错误状态；不安装不影响基础检测。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if case .error(let message) = state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button(preview == nil ? "预览 Hook 改动" : "重新预览") {
                    makePreview()
                }
                .disabled(isWorking)

                switch state {
                case .installed:
                    Button("移除 Hook", role: .destructive) {
                        uninstallClaude()
                    }
                    .disabled(isWorking)
                case .notInstalled, .updateRequired, .unknown:
                    Button("应用 Hook") {
                        installClaude()
                    }
                    .disabled(isWorking || preview == nil)
                case .error:
                    Button("重新读取") { refreshStates() }
                        .disabled(isWorking)
                }

                if isWorking {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("正在更新 Claude Code Hook")
                }
            }
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator.opacity(0.7))
        }
    }

    private func previewCard(_ preview: HookSetupCoordinator.ChangePreview) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Claude Code Hook 预览")
                    .font(.headline)
                Spacer()
                Button("取消") { self.preview = nil }
                    .disabled(isWorking)
            }
            Text(
                preview.addedCommands.isEmpty
                    ? "当前 Hook 已是最新，无需修改。"
                    : "将新增或更新 \(preview.addedCommands.count) 条 Hook 条目。请确认预览后再应用。"
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            DisclosureGroup("查看更改后的设置") {
                ScrollView {
                    Text(preview.after)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
            .font(.caption)
        }
        .padding(12)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func symbol(for state: HookSettingsStatus) -> String {
        switch state {
        case .unknown: return "clock"
        case .notInstalled: return "circle.dashed"
        case .installed: return "checkmark.circle.fill"
        case .updateRequired: return "arrow.triangle.2.circlepath"
        case .error: return "exclamationmark.triangle"
        }
    }

    private func color(for state: HookSettingsStatus) -> Color {
        switch state {
        case .installed: return .green
        case .updateRequired, .error: return .orange
        case .unknown, .notInstalled: return .secondary
        }
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

    // MARK: - Actions

    private var claudeCoordinator: HookSetupCoordinator {
        HookSetupCoordinator(provider: .claude)
    }

    private var codexCoordinator: HookSetupCoordinator {
        HookSetupCoordinator(provider: .codex)
    }

    private func makePreview() {
        feedback = Feedback(kind: .info, text: "正在读取现有设置并生成预览…")
        do {
            preview = try claudeCoordinator.preview()
            feedback = nil
        } catch {
            preview = nil
            feedback = Feedback(
                kind: .error,
                text: "无法生成 Claude Code Hook 预览。\(hookErrorDescription(error))"
            )
        }
    }

    private func installClaude() {
        guard preview != nil, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try claudeCoordinator.install(confirmed: true)
            preview = nil
            feedback = Feedback(
                kind: .success,
                text: "已为 Claude Code 应用 Hook。修改前的设置已备份。"
            )
        } catch {
            feedback = Feedback(
                kind: .error,
                text: "未能为 Claude Code 应用 Hook。\(hookErrorDescription(error))"
            )
        }
        refreshStates()
    }

    private func uninstallClaude() {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try claudeCoordinator.uninstall()
            preview = nil
            feedback = Feedback(
                kind: .success,
                text: "已仅移除本应用为 Claude Code 添加的 Hook 条目。"
            )
        } catch {
            feedback = Feedback(
                kind: .error,
                text: "未能移除 Claude Code Hook。\(hookErrorDescription(error))"
            )
        }
        refreshStates()
    }

    private func removeCodexLegacyHooks() {
        guard !isWorking else { return }
        isWorking = true
        codexCleanupError = nil
        defer { isWorking = false }
        do {
            try codexCoordinator.uninstall()
            feedback = Feedback(
                kind: .success,
                text: "已移除本应用安装的旧版 Codex Hook 条目。"
            )
        } catch {
            codexCleanupError = "未能移除旧版 Codex Hook。\(hookErrorDescription(error))"
        }
        refreshStates()
    }

    /// Ownership, not file existence, decides the status: an existing file
    /// with only other tools' hooks must not read as "needs update".
    private func refreshStates() {
        do {
            claudeState = AgentSettingsLogic.hookStatus(
                isInstalled: claudeCoordinator.isInstalled(),
                hasManagedEntries: try claudeCoordinator.hasManagedEntries()
            )
        } catch {
            claudeState = .error(hookErrorDescription(error))
        }

        do {
            codexLegacyHooks = try codexCoordinator.hasManagedEntries() ? .present : .none
        } catch {
            // An unreadable file proves no ownership, so no cleanup is offered.
            Log.write("codex legacy hook scan skipped: hooks file unreadable")
            codexLegacyHooks = .none
        }
    }

    private func hookErrorDescription(_ error: Error) -> String {
        switch error {
        case HookSetupCoordinator.HookError.malformedSettings:
            return "Hook 设置文件不是有效的 JSON。请先修复或备份后重试。"
        case HookSetupCoordinator.HookError.notConfirmed:
            return "需要先预览并确认改动。"
        default:
            return "请检查设置文件及其目录权限后重试。"
        }
    }
}
