import NaturalLanguage

/// 基于 NLLanguageRecognizer 的语种检测
enum LanguageDetector {
    /// 短文本判定门槛：实测 NLLanguageRecognizer 对短样本不可靠且置信度虚高——
    /// 「你好」→ zh-Hant(0.80)、「hi」→ ca 加泰罗尼亚语(0.80)、「sk-12345…」→ tr(0.72)。
    /// 这类误判会拼出未装包语向（如 zh-Hant→zh-Hans）触发「Unable to Translate」。
    /// 长文本（>12 字符）干净样本置信度通常 ≥0.9，维持 0.5 防线即可。
    private static let shortTextMaxChars = 12
    private static let shortTextMinConfidence = 0.9
    private static let longTextMinConfidence = 0.5

    static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        guard let top = recognizer.languageHypotheses(withMaximum: 1).first else {
            return nil
        }
        // 置信度守卫：短文本用高门槛（0.9），长文本用基础门槛（0.5）。
        // 不确信时返回 nil 交给调用方回退（hint/自动检测），宁可少翻不错翻。
        let threshold = sample.count <= shortTextMaxChars
            ? shortTextMinConfidence : longTextMinConfidence
        guard top.value >= threshold else {
            return nil
        }
        let code = top.key.rawValue

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
