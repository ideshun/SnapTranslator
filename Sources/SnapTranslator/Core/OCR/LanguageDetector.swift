import NaturalLanguage

/// 基于 NLLanguageRecognizer 的语种检测
enum LanguageDetector {
    static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let code = recognizer.dominantLanguage?.rawValue else { return nil }
        if code == "zh" { return .zhHans }
        return Language(rawValue: code)
    }
}
