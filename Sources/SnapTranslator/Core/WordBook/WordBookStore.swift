import Foundation

/// 生词本：JSON 文件存储与 CRUD，重复收藏时更新上下文与时间
/// （CLT 工具链缺少 SwiftData 宏插件，故采用零依赖 JSON 方案，见 ADR-005 修订）
@MainActor
final class WordBookStore: ObservableObject {
    @Published private(set) var words: [Word] = []

    private let fileURL: URL?

    init(inMemory: Bool = false) {
        if inMemory {
            fileURL = nil
        } else {
            let support = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
            let directory = support?.appendingPathComponent("SnapTranslator", isDirectory: true)
            if let directory {
                do {
                    try FileManager.default.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    NSLog("生词本目录创建失败 dir=%@ error=%@",
                          directory.path, error.localizedDescription)
                }
            }
            fileURL = directory?.appendingPathComponent("wordbook.json")
        }
        load()
    }

    /// 收藏词/短语；已存在时刷新上下文与时间
    @discardableResult
    func add(phrase: String, context sentence: String, source: String, target: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if let index = words.firstIndex(where: { $0.phrase == trimmed }) {
            words[index].context = sentence
            words[index].sourceLanguage = source
            words[index].targetLanguage = target
            words[index].createdAt = Date()
        } else {
            words.insert(
                Word(phrase: trimmed, context: sentence, sourceLanguage: source, targetLanguage: target),
                at: 0
            )
        }
        return persist()
    }

    func delete(_ word: Word) {
        words.removeAll { $0.id == word.id }
        persist()
    }

    func deleteAll() {
        words.removeAll()
        persist()
    }

    // MARK: - 持久化

    private func load() {
        guard let fileURL,
              let data = try? Data(contentsOf: fileURL)
        else { return }
        do {
            words = try JSONDecoder().decode([Word].self, from: data)
        } catch {
            NSLog("生词本读取失败 file=%@ error=%@", fileURL.path, error.localizedDescription)
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
            NSLog("生词本写入失败 file=%@ error=%@", fileURL.path, error.localizedDescription)
            return false
        }
    }
}
