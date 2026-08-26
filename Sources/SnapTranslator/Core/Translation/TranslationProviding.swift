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
    case offline
    case apple
    case openai
    case deepl
    case google

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动（离线优先）"
        case .offline: return "仅离线（纯本地，永不联网）"
        case .apple: return "Apple 系统翻译（离线）"
        case .openai: return "智谱 AI GLM5.2"
        case .deepl: return "DeepL"
        case .google: return "Google（免费）"
        }
    }
}

enum TranslationError: LocalizedError {
    case allFailed([String])
    case timeout
    case emptyResponse
    case noOfflineEngine

    var errorDescription: String? {
        switch self {
        case .allFailed(let errors):
            let detail = errors.joined(separator: "；")
            return "全部引擎失败：\(detail)\n\n建议：\n1. 在设置 → 引擎中点「下载 Apple 翻译语言包」确保本地离线翻译可用\n2. 在设置 → 引擎中填入智谱 AI API Key 使用 GLM5.2 在线翻译\n3. 确认网络连接正常后重试"
        case .timeout:
            return "请求超时（15秒），请检查网络连接后重试"
        case .emptyResponse:
            return "引擎返回了空结果，可能是源语言与目标语言相同或文本内容不支持翻译"
        case .noOfflineEngine:
            return "当前系统不支持 Apple 离线翻译（需 macOS 15+ 并在设置中下载语言包），且「仅离线」模式拒绝联网翻译。请在设置中切换引擎或下载 Apple 语言包。"
        }
    }
}

/// 单个引擎调用超时秒数
let engineTimeoutSeconds: Double = 15
