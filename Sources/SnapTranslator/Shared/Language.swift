import Foundation

/// 支持的语言集合，rawValue 同时是 BCP 47 语言码
enum Language: String, CaseIterable, Codable, Identifiable {
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case fr = "fr"
    case de = "de"
    case es = "es"
    case pt = "pt"
    case it = "it"
    case ru = "ru"
    case uk = "uk"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .zhHant: return "繁体中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .pt: return "Português"
        case .it: return "Italiano"
        case .ru: return "Русский"
        case .uk: return "Українська"
        }
    }

    /// Vision OCR 识别语言码
    var visionCode: String {
        switch self {
        case .zhHans: return "zh-Hans"
        case .zhHant: return "zh-Hant"
        case .en: return "en-US"
        case .ja: return "ja-JP"
        case .ko: return "ko-KR"
        case .fr: return "fr-FR"
        case .de: return "de-DE"
        case .es: return "es-ES"
        case .pt: return "pt-BR"
        case .it: return "it-IT"
        case .ru: return "ru-RU"
        case .uk: return "uk-UA"
        }
    }

    /// Google 免费接口语言码
    var googleCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        default: return rawValue
        }
    }

    /// DeepL API 目标语言码
    var deeplCode: String {
        switch self {
        case .zhHans: return "ZH"
        case .zhHant: return "ZH"
        case .uk: return "UK"
        default: return rawValue.uppercased()
        }
    }
}
