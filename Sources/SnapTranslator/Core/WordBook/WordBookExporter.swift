import Foundation

/// 生词本 CSV 导出：UTF-8 BOM 保证 Excel 中文不乱码
enum WordBookExporter {
    static func csv(for words: [Word]) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        var rows = ["词,上下文,源语言,目标语言,收藏时间"]
        for word in words {
            rows.append(
                [
                    escape(word.phrase),
                    escape(word.context),
                    escape(word.sourceLanguage),
                    escape(word.targetLanguage),
                    formatter.string(from: word.createdAt),
                ].joined(separator: ",")
            )
        }
        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    /// CSV 字段转义：含逗号/引号/换行时加引号包裹，引号翻倍
    static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
