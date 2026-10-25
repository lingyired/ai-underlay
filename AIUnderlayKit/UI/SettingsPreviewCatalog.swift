/// User-facing names for the built-in renderer fixtures. The fixture keys stay
/// unchanged because they are persisted in settings and consumed by the real
/// renderer; only the labels shown in Settings are translated.
struct SettingsPreviewOption: Identifiable, Equatable {
    let key: String
    let title: String
    let detail: String

    var id: String { key }
}

enum SettingsPreviewCatalog {
    static let options: [SettingsPreviewOption] = [
        .init(key: "full", title: "额度充足", detail: "周额度与 5 小时额度均为 100%。"),
        .init(key: "weekLow", title: "周额度偏低", detail: "周额度剩 20%，5 小时额度剩 90%。"),
        .init(key: "sessionLow", title: "5 小时额度偏低", detail: "周额度剩 80%，5 小时额度剩 10%。"),
        .init(key: "allZero", title: "额度已用完", detail: "周额度与 5 小时额度都已耗尽。"),
        .init(key: "missing", title: "部分数据缺失", detail: "周额度暂时没有数据；5 小时额度正常。"),
        .init(key: "stale", title: "数据已过期", detail: "周额度与 5 小时额度都使用了过期数据。"),
        .init(key: "reset", title: "即将重置", detail: "额度接近恢复，用于检查重置状态。"),
        .init(key: "agentRunning", title: "Agent 正在运行", detail: "显示运行中的动效。"),
        .init(key: "agentWaiting", title: "Agent 等待确认", detail: "显示等待用户处理的提醒。"),
        .init(key: "agentError", title: "Agent 运行失败", detail: "显示最高优先级的错误状态。"),
        .init(key: "agentRunningWaiting", title: "运行中 + 等待确认", detail: "同时显示运行与等待状态。"),
        .init(key: "agentRunningError", title: "运行中 + 运行失败", detail: "同时显示运行与错误状态。"),
        .init(key: "agentUnread", title: "Agent 有未读完成", detail: "显示未读完成提醒。"),
        .init(key: "agentRunningUnread", title: "运行中 + 未读完成", detail: "同时显示运行与未读完成状态。"),
        .init(key: "agentAllSignals", title: "全部 Agent 状态", detail: "检查多种状态同时出现时的优先级。"),
        .init(key: "glassV5", title: "标准配色样例", detail: "使用产品标准配色和额度比例。"),
        .init(key: "notchless", title: "等额额度样例", detail: "周额度与 5 小时额度均为一半。"),
    ]

    static func option(for key: String) -> SettingsPreviewOption {
        options.first { $0.key == key }
            ?? SettingsPreviewOption(
                key: key,
                title: "未知场景",
                detail: "此场景未在当前版本中提供。"
            )
    }
}
