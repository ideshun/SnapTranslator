import Foundation

/// 翻译引擎统一协议，source 传 nil 表示自动检测
public protocol TranslationProviding: Sendable {
    /// 用于界面展示与日志的引擎名称
    var name: String { get }
    /// 用于熔断器与缓存的唯一引擎键
    var providerID: String { get }
    /// 当前是否已满足调用前提（例如 API Key / 模型名已配置）
    var isAvailable: Bool { get }
    /// 是否需要联网（供纯离线隐私模式严格过滤）
    var requiresNetwork: Bool { get }
    /// 是否原生支持流式增量回调
    var supportsStreaming: Bool { get }

    func translate(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle
    ) async throws -> String

    func translateStream(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String
}

public extension TranslationProviding {
    var providerID: String { name }
    var requiresNetwork: Bool { true }
    var supportsStreaming: Bool { false }

    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String {
        try await translate(text, from: source, to: target, style: .general)
    }

    func translateStream(
        _ text: String,
        from source: Language?,
        to target: Language,
        style: TranslationStyle,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let result = try await translate(text, from: source, to: target, style: style)
        onPartial(result)
        return result
    }
}

/// 主引擎选择策略
public enum PrimaryEngine: String, CaseIterable, Codable, Identifiable, Sendable {
    case auto
    case apple
    case openai
    case deepl
    case google

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "自动（AI 模型 > Google > 本地）"
        case .apple: return "Apple 系统翻译（本地离线优先）"
        case .openai: return "AI 模型（OpenAI 兼容）"
        case .deepl: return "DeepL"
        case .google: return "Google（免费）"
        }
    }

    /// 状态栏等紧凑位置用的短名
    public var shortName: String {
        switch self {
        case .auto: return "自动"
        case .apple: return "Apple 本地"
        case .openai: return "AI 模型"
        case .deepl: return "DeepL"
        case .google: return "Google"
        }
    }
}

/// 云引擎代理设置：仅作用于在线翻译的 URLSession，Apple 离线翻译不受影响
public struct EngineProxySettings: Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int?

    public init(enabled: Bool = false, host: String = "127.0.0.1", port: Int? = nil) {
        self.enabled = enabled
        self.host = host
        self.port = port
    }

    public var isValid: Bool {
        enabled && !host.isEmpty && (port ?? 0) > 0 && (port ?? 0) <= 65535
    }
}

/// 单次翻译完整结果
public struct TranslationOutcome: Sendable, Equatable {
    public let translation: String
    public let provider: String
    public let fallbackNotice: String?
    public let fromCache: Bool

    public init(
        translation: String,
        provider: String,
        fallbackNotice: String? = nil,
        fromCache: Bool = false
    ) {
        self.translation = translation
        self.provider = provider
        self.fallbackNotice = fallbackNotice
        self.fromCache = fromCache
    }
}

public enum TranslationError: LocalizedError, Sendable {
    case allFailed([String])
    case offlineModeUnavailable
    case timeout
    case emptyResponse
    case rateLimited(String)
    case httpError(provider: String, statusCode: Int, detail: String)

    public var errorDescription: String? {
        switch self {
        case .allFailed(let errors):
            let detail = errors.joined(separator: "；")
            return "全部引擎失败：\(detail)\n\n建议：\n1. 在设置 → 引擎中检查 AI API Key 并点击「测试连接」\n2. 在设置 → 引擎中下载 Apple 离线翻译语言包\n3. 确认网络连接或代理配置正常后重试"
        case .offlineModeUnavailable:
            return "已开启「纯离线隐私模式」，仅允许使用 Apple 本地翻译（需 macOS 15+ 并安装对应语言包）。如需使用云引擎，请在「设置 → 引擎」关闭纯离线模式。"
        case .timeout:
            return "请求超时（\(Int(engineTimeoutSeconds))秒），请检查网络连接后重试"
        case .emptyResponse:
            return "引擎返回了空结果，可能是源语言与目标语言相同或文本内容不支持翻译"
        case .rateLimited(let provider):
            return "\(provider) 触发频率限制（HTTP 429），请稍后重试或切换其他引擎"
        case .httpError(let provider, let statusCode, let detail):
            return "\(provider) 请求失败（HTTP \(statusCode)）：\(detail)"
        }
    }

    /// 某些错误（如不支持的语向、未装包）仅影响当前语向；另一些（如 401/429/超时）影响引擎全局
    public var isLanguagePairScoped: Bool {
        let lower = (errorDescription ?? "").lowercased()
        return lower.contains("语向") || lower.contains("语言包") || lower.contains("unable to translate")
    }
}

/// 单个引擎调用超时秒数
public let engineTimeoutSeconds: Double = 20
