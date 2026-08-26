import NaturalLanguage

/// 基于 NLLanguageRecognizer 的语种检测
enum LanguageDetector {
    static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let code = recognizer.dominantLanguage?.rawValue else { return nil }

        // 统一处理中文变体：zh/zh-Hans → 简体中文，zh-Hant → 繁体中文
        if code == "zh" || code == "zh-Hans" || code == "zh-CN" {
            return .zhHans
        }
        if code == "zh-Hant" || code == "zh-TW" || code == "zh-HK" {
            return .zhHant
        }
        // 英文也可能返回 en-US 或 en-GB 等变体
        if code == "en-US" || code == "en-GB" || code == "en-AU" || code == "en-CA" {
            return .en
        }
        return Language(rawValue: code)
    }
}
