import Foundation
import NaturalLanguage

/// 基于 Unicode 文字系统快速通道 + 常用词汇先验 + NLLanguageRecognizer 的语种检测
public enum LanguageDetector {
    private static let shortTextMaxChars = 12
    private static let shortTextMinConfidence = 0.8
    private static let longTextMinConfidence = 0.5
    private static let latinShortTextMinConfidence = 0.35

    private static let commonShortEnglishWords: Set<String> = [
        "a", "about", "above", "across", "act", "add", "after", "again", "against", "age",
        "ago", "air", "all", "almost", "along", "also", "always", "am", "among", "an",
        "and", "another", "any", "are", "area", "arm", "around", "art", "as", "ask",
        "at", "away", "back", "bad", "bag", "bar", "be", "became", "because", "become",
        "been", "before", "began", "begin", "behind", "being", "below", "best", "better",
        "between", "big", "bird", "bit", "black", "blue", "boat", "body", "book", "both",
        "box", "boy", "bring", "build", "built", "bus", "busy", "but", "buy", "by",
        "call", "came", "can", "car", "care", "carry", "case", "cat", "city", "close",
        "cold", "come", "could", "cut", "dark", "day", "did", "die", "direct", "do",
        "does", "dog", "done", "door", "down", "draw", "dry", "each", "early", "earth",
        "easy", "eat", "end", "even", "ever", "every", "eye", "face", "fact", "fall",
        "family", "far", "fast", "father", "feel", "few", "field", "fill", "find", "fine",
        "fire", "first", "fish", "fit", "five", "fly", "food", "foot", "for", "form",
        "found", "four", "free", "friend", "from", "front", "full", "game", "gave", "get",
        "girl", "give", "glad", "go", "goes", "going", "gold", "gone", "good", "got",
        "great", "green", "ground", "group", "grow", "had", "half", "hand", "hard", "has",
        "have", "he", "head", "hear", "heard", "heart", "heavy", "held", "help", "her",
        "here", "high", "him", "his", "hold", "home", "hope", "hot", "hour", "house",
        "how", "huge", "idea", "if", "in", "into", "is", "it", "its", "job",
        "just", "keep", "kept", "key", "kind", "knew", "know", "land", "large", "last",
        "late", "later", "law", "lay", "lead", "learn", "leave", "left", "less", "let",
        "letter", "life", "light", "like", "line", "list", "little", "live", "long", "look",
        "lot", "love", "low", "made", "main", "make", "man", "many", "map", "mark",
        "may", "me", "mean", "men", "might", "mind", "miss", "money", "more", "most",
        "mother", "move", "much", "must", "my", "name", "near", "need", "never", "new",
        "next", "night", "no", "none", "nor", "not", "note", "nothing", "notice", "now",
        "number", "off", "often", "oil", "old", "on", "once", "one", "only", "open",
        "or", "order", "other", "our", "out", "over", "own", "page", "paper", "part",
        "pass", "past", "pay", "people", "per", "pick", "picture", "piece", "place", "plan",
        "play", "point", "poor", "power", "press", "put", "quick", "quite", "rain", "read",
        "ready", "real", "red", "rest", "right", "river", "road", "rock", "room", "round",
        "rule", "run", "said", "same", "saw", "say", "school", "sea", "second", "see",
        "seem", "seen", "send", "sent", "set", "seven", "several", "shall", "she", "ship",
        "short", "should", "show", "side", "sight", "simple", "since", "six", "size", "sky",
        "small", "so", "some", "son", "soon", "sound", "south", "space", "speak", "stand",
        "start", "state", "stay", "step", "still", "stood", "stop", "story", "strong", "such",
        "sun", "sure", "table", "take", "talk", "tall", "tell", "ten", "than", "that",
        "the", "their", "them", "then", "there", "these", "they", "thing", "think", "third",
        "this", "those", "though", "thought", "three", "through", "time", "to", "today", "together",
        "told", "too", "took", "top", "toward", "town", "tree", "true", "try", "turn",
        "two", "under", "until", "up", "upon", "us", "use", "usual", "van", "very",
        "voice", "wait", "walk", "wall", "want", "war", "warm", "was", "water", "way",
        "we", "week", "well", "went", "were", "west", "what", "when", "where", "which",
        "while", "white", "who", "whole", "why", "wide", "wife", "will", "win", "wind",
        "with", "within", "without", "word", "work", "world", "would", "write", "wrong", "year",
        "yes", "yet", "you", "young", "your", "ok", "hi", "hey", "ice", "tea", "coffee",
    ]

    public static func detect(_ text: String) -> Language? {
        let sample = String(text.prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sample.isEmpty else { return nil }
        let scalars = Array(sample.unicodeScalars)

        if scalars.contains(where: isHangul) { return .ko }
        if scalars.contains(where: isKana) { return .ja }
        if scalars.contains(where: isHan) { return chineseVariant(sample) }
        if scalars.contains(where: isCyrillic) { return cyrillicVariant(sample) }

        let pureLetters = sample.unicodeScalars.filter { isPureAsciiLetter($0) }
        let lettersString = String(String.UnicodeScalarView(pureLetters)).lowercased()
        if !lettersString.isEmpty && commonShortEnglishWords.contains(lettersString) {
            return .en
        }

        let allLatinOrNeutral = scalars.allSatisfy { isLatinLetter($0) || isNeutral($0) }
        let allPureAscii = scalars.allSatisfy { isPureAsciiLetter($0) || isNeutral($0) }

        let recognizer = NLLanguageRecognizer()
        var usedLatinConstraint = false
        if allLatinOrNeutral {
            recognizer.languageConstraints = [.english, .french, .german, .spanish, .portuguese, .italian]
            usedLatinConstraint = true
        }

        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 6)
        guard let top = hypotheses.sorted(by: { $0.value > $1.value }).first else {
            return allPureAscii ? .en : nil
        }

        if allPureAscii && sample.count <= shortTextMaxChars {
            if top.key == .english { return .en }
            let enConfidence = hypotheses[.english] ?? 0
            if enConfidence > 0.08 || sample.count <= 5 {
                return .en
            }
        }

        let threshold: Double
        if sample.count <= shortTextMaxChars {
            threshold = usedLatinConstraint ? latinShortTextMinConfidence : shortTextMinConfidence
        } else {
            threshold = longTextMinConfidence
        }

        if top.value >= threshold {
            let code = top.key.rawValue
            if code == "zh" || code == "zh-Hans" || code == "zh-CN" { return .zhHans }
            if code == "zh-Hant" || code == "zh-TW" || code == "zh-HK" { return .zhHant }
            if code == "en-US" || code == "en-GB" || code == "en-AU" || code == "en-CA" { return .en }
            return Language(rawValue: code)
        }

        if allPureAscii && !lettersString.isEmpty {
            return .en
        }

        return nil
    }

    private static func chineseVariant(_ sample: String) -> Language {
        let converted = NSMutableString(string: sample)
        var updated = NSRange()
        converted.applyTransform(
            StringTransform("Traditional-Simplified"),
            reverse: false,
            range: NSRange(location: 0, length: converted.length),
            updatedRange: &updated
        )
        return (converted as String) == sample ? .zhHans : .zhHant
    }

    private static func cyrillicVariant(_ sample: String) -> Language {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.russian, .ukrainian]
        recognizer.processString(sample)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let ru = hypotheses[.russian] ?? 0
        let uk = hypotheses[.ukrainian] ?? 0
        return uk > ru + 0.1 ? .uk : .ru
    }

    private static func isHangul(_ scalar: Unicode.Scalar) -> Bool {
        (0xAC00...0xD7A3).contains(scalar.value)
            || (0x1100...0x11FF).contains(scalar.value)
            || (0x3130...0x318F).contains(scalar.value)
    }

    private static func isKana(_ scalar: Unicode.Scalar) -> Bool {
        (0x3040...0x309F).contains(scalar.value)
            || (0x30A0...0x30FF).contains(scalar.value)
    }

    private static func isHan(_ scalar: Unicode.Scalar) -> Bool {
        (0x3400...0x4DBF).contains(scalar.value)
            || (0x4E00...0x9FFF).contains(scalar.value)
            || (0xF900...0xFAFF).contains(scalar.value)
    }

    private static func isCyrillic(_ scalar: Unicode.Scalar) -> Bool {
        (0x0400...0x04FF).contains(scalar.value)
    }

    private static func isPureAsciiLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A:
            return true
        default:
            return false
        }
    }

    private static func isLatinLetter(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0x00C0...0x024F:
            return true
        default:
            return false
        }
    }

    private static func isNeutral(_ scalar: Unicode.Scalar) -> Bool {
        let p = scalar.properties
        if p.isWhitespace { return true }
        switch p.generalCategory {
        case .connectorPunctuation, .dashPunctuation, .openPunctuation,
             .closePunctuation, .initialPunctuation, .finalPunctuation,
             .otherPunctuation, .mathSymbol, .currencySymbol,
             .modifierSymbol, .otherSymbol, .decimalNumber,
             .letterNumber, .otherNumber:
            return true
        default:
            return scalar.value <= 0x20 || (scalar.value >= 0x7F && scalar.value <= 0xA0)
        }
    }
}
