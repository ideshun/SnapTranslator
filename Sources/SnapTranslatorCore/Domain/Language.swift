import Foundation

/// 支持的语言集合，rawValue 同时是 BCP 47 语言码
public enum Language: String, CaseIterable, Codable, Identifiable, Sendable, Hashable {
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

    public var id: String { rawValue }

    public var displayName: String {
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

    public var promptName: String {
        switch self {
        case .zhHans: return "Simplified Chinese (简体中文)"
        case .zhHant: return "Traditional Chinese (繁体中文)"
        case .en: return "English"
        case .ja: return "Japanese"
        case .ko: return "Korean"
        case .fr: return "French"
        case .de: return "German"
        case .es: return "Spanish"
        case .pt: return "Portuguese"
        case .it: return "Italian"
        case .ru: return "Russian"
        case .uk: return "Ukrainian"
        }
    }

    public var visionCode: String {
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

    public var googleCode: String {
        switch self {
        case .zhHans: return "zh-CN"
        case .zhHant: return "zh-TW"
        default: return rawValue
        }
    }

    public var deeplSourceCode: String {
        switch self {
        case .zhHans, .zhHant: return "ZH"
        case .uk: return "UK"
        default: return rawValue.uppercased()
        }
    }

    public var deeplTargetCode: String {
        switch self {
        case .zhHans: return "ZH-HANS"
        case .zhHant: return "ZH-HANT"
        case .en: return "EN-US"
        case .pt: return "PT-BR"
        case .uk: return "UK"
        default: return rawValue.uppercased()
        }
    }

    public var deeplCode: String { deeplSourceCode }
}
