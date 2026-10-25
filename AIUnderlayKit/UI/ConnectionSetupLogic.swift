import Foundation

/// Pure presentation logic for the connection settings. Kept separate from
/// SwiftUI so state distinctions and URL validation can be tested directly.
public enum ProviderConnectionStatus: Equatable, Sendable {
    case checking
    case disabled
    case notChecked
    case appUnavailable
    case upstreamDisabled
    case signedOut
    case unsupported
    case unavailable
    case stale(date: Date?)
    case connected

    public var title: String {
        switch self {
        case .checking: return "检测中…"
        case .disabled: return "已关闭"
        case .notChecked: return "尚未检测"
        case .appUnavailable: return "数据源不可用"
        case .upstreamDisabled: return "需先启用"
        case .signedOut: return "未登录"
        case .unsupported: return "不受支持"
        case .unavailable: return "暂不可用"
        case .stale: return "数据已过期"
        case .connected: return "连接正常"
        }
    }

    public var detail: String {
        switch self {
        case .checking:
            return "正在通过 CodexBar 获取最新状态，完成前不会判定为已连接。"
        case .disabled:
            return "本应用不会请求或显示此服务商。"
        case .notChecked:
            return "点击“检查连接”获取额度状态。"
        case .appUnavailable:
            return "未找到可用的 CodexBar。请在“运行引擎”中检查安装与版本兼容性。"
        case .upstreamDisabled:
            return "先在 CodexBar 中启用此服务商，再检查连接。"
        case .signedOut:
            return "CodexBar 尚未取得登录凭据，请在 CodexBar 中登录后重试。"
        case .unsupported:
            return "CodexBar 当前不支持读取此服务商的额度。"
        case .unavailable:
            return "本次获取失败。请检查网络或代理设置后重试。"
        case .stale(let date):
            guard let date else { return "当前额度记录已过期，请重新检查连接。" }
            let formatted = date.formatted(date: .abbreviated, time: .shortened)
            return "当前额度记录已过期，请重新检查连接。记录时间：\(formatted)。"
        case .connected:
            return "已取得有效额度数据。"
        }
    }

    public var isSuccess: Bool {
        self == .connected
    }

    public var needsAttention: Bool {
        switch self {
        case .appUnavailable, .signedOut, .unsupported, .unavailable, .stale:
            return true
        case .checking, .disabled, .notChecked, .upstreamDisabled, .connected:
            return false
        }
    }
}

public enum ProviderConnectionLogic {
    public static func status(
        appEnabled: Bool,
        hasCatalogEntry: Bool,
        hasEngine: Bool,
        isChecking: Bool,
        snapshot: ProviderQuotaSnapshot?,
        fetchFailed: Bool
    ) -> ProviderConnectionStatus {
        guard appEnabled else { return .disabled }
        if isChecking { return .checking }
        guard hasEngine else { return .appUnavailable }
        guard let snapshot else {
            if fetchFailed { return .unavailable }
            return hasCatalogEntry ? .notChecked : .unavailable
        }
        switch snapshot.availability {
        case .valid where !fetchFailed:
            return .connected
        case .valid, .stale:
            return .stale(date: snapshot.fetchedAt)
        case .unauthenticated:
            return .signedOut
        case .unsupported:
            return .unsupported
        case .unavailable, .unknown:
            return .unavailable
        }
    }

    public static func shouldShowUpstreamAction(
        hasCatalogEntry: Bool,
        upstreamEnabled: Bool
    ) -> Bool {
        hasCatalogEntry && !upstreamEnabled
    }
}

public enum ProxyAddressValidation: Equatable, Sendable {
    case empty
    case valid(String)
    case invalid(String)

    public var normalizedValue: String? {
        guard case .valid(let value) = self else { return nil }
        return value
    }

    public var errorMessage: String? {
        guard case .invalid(let message) = self else { return nil }
        return message
    }
}

public enum ProxyAddressValidator {
    public static func validate(_ rawValue: String) -> ProxyAddressValidation {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return .empty }
        guard !containsControlCharacters(value) else {
            return .invalid("代理地址包含不可见控制字符。")
        }
        guard let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              ["http", "https", "socks5", "socks5h"].contains(scheme)
        else {
            return .invalid("请使用 http://、https://、socks5:// 或 socks5h:// 开头的代理地址。")
        }
        guard let host = components.host, !host.isEmpty else {
            return .invalid("代理地址缺少有效主机名或 IP 地址。")
        }
        guard let port = components.port, (1...65535).contains(port) else {
            return .invalid("请填写 1–65535 之间的代理端口，例如 http://127.0.0.1:10808。")
        }
        guard components.user == nil, components.password == nil else {
            return .invalid("为保护凭据，本应用暂不接受带用户名或密码的代理地址。")
        }
        guard components.path.isEmpty || components.path == "/",
              components.query == nil,
              components.fragment == nil
        else {
            return .invalid("代理地址只需填写协议、主机和端口，不要附加路径、查询参数或片段。")
        }

        var normalized = components
        normalized.scheme = scheme
        guard let url = normalized.url else {
            return .invalid("代理地址格式无效。")
        }
        return .valid(url.absoluteString)
    }

    private static func containsControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)
        }
    }
}

public enum HookSettingsStatus: Equatable, Sendable {
    case unknown
    case notInstalled
    case installed
    case updateRequired
    case error(String)

    public var title: String {
        switch self {
        case .unknown: return "正在检查"
        case .notInstalled: return "未启用增强检测"
        case .installed: return "增强检测已启用"
        case .updateRequired: return "需要更新 Hook"
        case .error: return "无法读取设置"
        }
    }
}

public enum ConnectionTestLifecycle {
    public static func seesRefreshStart(
        isTesting: Bool,
        emittedRefreshing: Bool
    ) -> Bool {
        isTesting && emittedRefreshing
    }

    public static func shouldComplete(
        isTesting: Bool,
        didObserveStart: Bool,
        emittedRefreshing: Bool
    ) -> Bool {
        isTesting && didObserveStart && !emittedRefreshing
    }
}
