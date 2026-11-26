import Foundation

/// 语向决策结果
public struct ResolvedLanguagePair: Equatable, Sendable {
    public let source: Language?
    public let target: Language
    public let wasAutoFlipped: Bool

    public init(source: Language?, target: Language, wasAutoFlipped: Bool = false) {
        self.source = source
        self.target = target
        self.wasAutoFlipped = wasAutoFlipped
    }
}

/// 唯一语向决策策略（纯函数，全应用与诊断工具共用）
public enum LanguagePolicy {
    private static let zhVariants: Set<Language> = [.zhHans, .zhHant]

    public static func resolve(
        text: String,
        sessionSourceOverride: Language?,
        persistentSourceLock: Language?,
        preferredTarget: Language
    ) -> ResolvedLanguagePair {
        let hasExplicitLock = (sessionSourceOverride != nil) || (persistentSourceLock != nil)
        let source = sessionSourceOverride ?? persistentSourceLock ?? LanguageDetector.detect(text)

        guard !hasExplicitLock, let detected = source else {
            return ResolvedLanguagePair(source: source, target: preferredTarget, wasAutoFlipped: false)
        }

        if detected == preferredTarget {
            let flipped: Language = (preferredTarget == .en) ? .zhHans : .en
            return ResolvedLanguagePair(source: detected, target: flipped, wasAutoFlipped: true)
        }

        if zhVariants.contains(detected) && zhVariants.contains(preferredTarget) {
            return ResolvedLanguagePair(source: detected, target: .en, wasAutoFlipped: true)
        }

        return ResolvedLanguagePair(source: detected, target: preferredTarget, wasAutoFlipped: false)
    }

    public static func swapped(
        currentSource: Language?,
        currentTarget: Language,
        fallbackText: String
    ) -> (source: Language, target: Language) {
        let effectiveSource = currentSource
            ?? (!fallbackText.isEmpty ? LanguageDetector.detect(fallbackText) : nil)
            ?? (currentTarget == .zhHans ? .en : .zhHans)

        let newSource = currentTarget
        var newTarget = effectiveSource
        if newSource == newTarget {
            newTarget = (newSource == .zhHans) ? .en : .zhHans
        }
        return (newSource, newTarget)
    }
}
