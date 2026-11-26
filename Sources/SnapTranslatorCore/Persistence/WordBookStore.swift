import Foundation

/// 生词本：JSON 文件存储与 CRUD，支持持久化译文/备注/标签与导入备份
@MainActor
public final class WordBookStore: ObservableObject {
    @Published public private(set) var words: [Word] = []

    private let fileURL: URL?

    public init(inMemory: Bool = false, customURL: URL? = nil) {
        if inMemory {
            fileURL = nil
        } else if let customURL {
            fileURL = customURL
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            let directory = support?.appendingPathComponent("SnapTranslator", isDirectory: true)
            if let directory {
                do {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                } catch {
                    AppLogger.persistence.error("生词本目录创建失败: \(error.localizedDescription, privacy: .public)")
                }
            }
            fileURL = directory?.appendingPathComponent("wordbook.json")
        }
        load()
    }

    @discardableResult
    public func add(
        phrase: String,
        context sentence: String,
        translation: String = "",
        source: String,
        target: String
    ) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let index = words.firstIndex(where: { $0.phrase == trimmed }) {
            var updated = words.remove(at: index)
            updated.context = sentence
            if !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                updated.translation = translation
            }
            updated.sourceLanguage = source
            updated.targetLanguage = target
            updated.createdAt = Date()
            words.insert(updated, at: 0)
        } else {
            words.insert(
                Word(
                    phrase: trimmed,
                    context: sentence,
                    translation: translation,
                    sourceLanguage: source,
                    targetLanguage: target
                ),
                at: 0
            )
        }
        return persist()
    }

    @discardableResult
    public func update(
        wordID: Word.ID,
        translation: String? = nil,
        note: String? = nil,
        tags: [String]? = nil
    ) -> Bool {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { return false }
        if let translation { words[index].translation = translation }
        if let note { words[index].note = note }
        if let tags {
            words[index].tags = tags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return persist()
    }

    @discardableResult
    public func importJSON(_ data: Data) throws -> Int {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        let imported = try decoder.decode([Word].self, from: data)
        var count = 0
        for item in imported {
            let trimmed = item.phrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let index = words.firstIndex(where: { $0.phrase == trimmed }) {
                if words[index].translation.isEmpty && !item.translation.isEmpty {
                    words[index].translation = item.translation
                }
                if words[index].note.isEmpty && !item.note.isEmpty {
                    words[index].note = item.note
                }
                words[index].tags = Array(Set(words[index].tags + item.tags)).sorted()
            } else {
                words.append(item)
                count += 1
            }
        }
        words.sort { $0.createdAt > $1.createdAt }
        _ = persist()
        return count
    }

    public func delete(_ word: Word) {
        words.removeAll { $0.id == word.id }
        _ = persist()
    }

    public func deleteAll() {
        words.removeAll()
        _ = persist()
    }

    private func load() {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return }
        do {
            words = try JSONDecoder().decode([Word].self, from: data)
        } catch {
            AppLogger.persistence.error("生词本读取失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persist() -> Bool {
        guard let fileURL else { return true }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(words)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            AppLogger.persistence.error("生词本写入失败: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}
