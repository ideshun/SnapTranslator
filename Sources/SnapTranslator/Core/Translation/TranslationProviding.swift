import Foundation

/// 翻译引擎统一协议，source 传 nil 表示自动检测
protocol TranslationProviding {
    var name: String { get }
    var isAvailable: Bool { get }
    func translate(_ text: String, from source: Language?, to target: Language) async throws -> String
}

/// 主引擎选择策略
enum PrimaryEngine: String, CaseIterable, Codable, Identifiable {
    case auto
    case apple
    case openai
    case deepl
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动（AI 模型 > Google > 本地）"
        case .apple: return "Apple 系统翻译（本地离线优先）"
        case .openai: return "智谱 AI"
        case .deepl: return "DeepL"
        case .google: return "Google（免费）"
        }
    }

    /// 状态栏等紧凑位置用的短名：完整 displayName 过长，会被截断显示不全
    var shortName: String {
        switch self {
        case .auto: return "自动"
        case .apple: return "Apple 本地"
        case .openai: return "智谱 AI"
        case .deepl: return "DeepL"
        case .google: return "Google"
        }
    }
}

/// 云引擎代理设置：仅作用于在线翻译的 URLSession，Apple 离线翻译不受影响
struct EngineProxySettings: Equatable {
    var enabled: Bool = false
    var host: String = "127.0.0.1"
    var port: Int?

    var isValid: Bool {
        enabled && !host.isEmpty && (port ?? 0) > 0 && (port ?? 0) <= 65535
    }

    /// 按设置生成 URLSession；未启用/无效时返回共享会话
    static func makeSession(_ settings: EngineProxySettings?) -> URLSession {
        guard let settings, settings.isValid else { return .shared }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.connectionProxyDictionary = [
            kCFNetworkProxiesHTTPEnable as String: true,
            kCFNetworkProxiesHTTPProxy as String: settings.host,
            kCFNetworkProxiesHTTPPort as String: settings.port!,
            kCFNetworkProxiesHTTPSEnable as String: true,
            kCFNetworkProxiesHTTPSProxy as String: settings.host,
            kCFNetworkProxiesHTTPSPort as String: settings.port!,
        ]
        return URLSession(configuration: config)
    }
}

enum TranslationError: LocalizedError {
    case allFailed([String])
    case timeout
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .allFailed(let errors):
            let detail = errors.joined(separator: "；")
            return "全部引擎失败：\(detail)\n\n建议：\n1. 在设置 → 引擎中点「下载 Apple 翻译语言包」确保本地离线翻译可用\n2. 在设置 → 引擎中填入智谱 AI API Key 使用云引擎在线翻译\n3. 确认网络连接正常（或在设置中配置代理）后重试"
        case .timeout:
            return "请求超时（15秒），请检查网络连接后重试"
        case .emptyResponse:
            return "引擎返回了空结果，可能是源语言与目标语言相同或文本内容不支持翻译"
        }
    }
}

/// 单个引擎调用超时秒数
let engineTimeoutSeconds: Double = 15

/// 引擎熔断：某引擎失败后短时间内直接跳过，避免自动链每次翻译都先等它
/// 超时/报错（实测 Google 被 429 限流时每次白等 ~1.5s 才轮到下一个引擎）
enum EngineBreaker {
    /// 熔断冷却时长
    static let cooldown: TimeInterval = 90

    private static let lock = NSLock()
    private static var blockedUntil: [String: Date] = [:]

    /// 该引擎是否处于熔断期
    static func isBlocked(_ name: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let until = blockedUntil[name] else { return false }
        if until < Date() {
            blockedUntil[name] = nil
            return false
        }
        return true
    }

    /// 记录一次失败，进入冷却期
    static func recordFailure(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        blockedUntil[name] = Date().addingTimeInterval(cooldown)
    }
}
