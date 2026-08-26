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
        case .auto: return "自动（离线优先）"
        case .apple: return "Apple 系统翻译（离线）"
        case .openai: return "OpenAI 兼容接口"
        case .deepl: return "DeepL"
        case .google: return "Google（免费）"
        }
    }
}

enum TranslationError: LocalizedError {
    case allFailed([String])
    case timeout
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .allFailed(let errors):
            return "全部引擎失败：" + errors.joined(separator: "；")
        case .timeout:
            return "请求超时"
        case .emptyResponse:
            return "引擎返回了空结果"
        }
    }
}

/// 单个引擎调用超时秒数
let engineTimeoutSeconds: Double = 15
