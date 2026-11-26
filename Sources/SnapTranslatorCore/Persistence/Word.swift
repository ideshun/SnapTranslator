import Foundation

/// 生词条目：兼容旧版 JSON，并新增持久化译文、备注与标签
public struct Word: Codable, Identifiable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var phrase: String
    public var context: String
    public var translation: String
    public var note: String
    public var tags: [String]
    public var sourceLanguage: String
    public var targetLanguage: String
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        phrase: String,
        context: String,
        translation: String = "",
        note: String = "",
        tags: [String] = [],
        sourceLanguage: String,
        targetLanguage: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.phrase = phrase
        self.context = context
        self.translation = translation
        self.note = note
        self.tags = tags
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, phrase, context, translation, note, tags, sourceLanguage, targetLanguage, createdAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        phrase = try container.decode(String.self, forKey: .phrase)
        context = try container.decodeIfPresent(String.self, forKey: .context) ?? ""
        translation = try container.decodeIfPresent(String.self, forKey: .translation) ?? ""
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        sourceLanguage = try container.decodeIfPresent(String.self, forKey: .sourceLanguage) ?? "auto"
        targetLanguage = try container.decodeIfPresent(String.self, forKey: .targetLanguage) ?? "zh-Hans"
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
}
