import Foundation

/// 翻译风格预设（主要用于 AI 引擎系统提示词调优）
public enum TranslationStyle: String, CaseIterable, Codable, Identifiable, Sendable {
    case general
    case technical
    case academic
    case concise

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: return "通用自然"
        case .technical: return "技术文档"
        case .academic: return "学术论文"
        case .concise: return "简洁润色"
        }
    }

    public var shortName: String {
        switch self {
        case .general: return "通用"
        case .technical: return "技术"
        case .academic: return "学术"
        case .concise: return "简洁"
        }
    }

    public var promptInstruction: String {
        switch self {
        case .general:
            return "Produce a natural, accurate, idiomatic translation preserving original paragraph structure."
        case .technical:
            return "Translate as technical documentation. Keep code snippets, identifiers, CLI flags, API names, and file paths untouched. Use standard software engineering terminology."
        case .academic:
            return "Translate in a formal, rigorous academic tone with precise domain terminology and clear logical flow."
        case .concise:
            return "Translate clearly and concisely, eliminating redundancy while faithfully retaining the core meaning."
        }
    }
}
