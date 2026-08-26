import Foundation

/// 生词条目：JSON 持久化（轻量，无 SwiftData 宏依赖）
struct Word: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    /// 收藏词/短语，天然去重键
    var phrase: String
    /// 收藏时所在原句（原文或译文上下文）
    var context: String
    var sourceLanguage: String
    var targetLanguage: String
    var createdAt: Date

    init(phrase: String, context: String, sourceLanguage: String, targetLanguage: String) {
        self.phrase = phrase
        self.context = context
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.createdAt = Date()
    }
}
