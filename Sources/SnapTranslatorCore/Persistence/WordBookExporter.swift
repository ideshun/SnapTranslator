import Foundation

/// 生词本多格式导出：CSV（UTF-8 BOM 兼容 Excel）、JSON 备份、Anki TSV
public enum WordBookExporter {
    public static func csv(for words: [Word]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var rows = ["词,译文,上下文,备注,标签,源语言,目标语言,收藏时间"]
        for word in words {
            rows.append(
                [
                    escape(word.phrase),
                    escape(word.translation),
                    escape(word.context),
                    escape(word.note),
                    escape(word.tags.joined(separator: "; ")),
                    escape(word.sourceLanguage),
                    escape(word.targetLanguage),
                    formatter.string(from: word.createdAt),
                ].joined(separator: ",")
            )
        }
        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    public static func jsonData(for words: [Word]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(words)
    }

    public static func ankiTSV(for words: [Word]) -> String {
        var lines = ["#separator:tab", "#html:false", "#tags column:3"]
        for word in words {
            let front = sanitizeTSV(word.phrase)
            var backParts: [String] = []
            if !word.translation.isEmpty { backParts.append(word.translation) }
            if !word.context.isEmpty && word.context != word.phrase {
                backParts.append("例句：\(word.context)")
            }
            if !word.note.isEmpty { backParts.append("备注：\(word.note)") }
            let back = sanitizeTSV(backParts.joined(separator: " | "))
            let tags = word.tags
                .map { $0.replacingOccurrences(of: " ", with: "_") }
                .joined(separator: " ")
            lines.append("\(front)\t\(back)\t\(tags)")
        }
        return lines.joined(separator: "\n")
    }

    public static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func sanitizeTSV(_ field: String) -> String {
        field
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
