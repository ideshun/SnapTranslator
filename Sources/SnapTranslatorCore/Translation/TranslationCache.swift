import CryptoKit
import Foundation

/// 线程安全的内存 LRU 翻译缓存：重复查词、切回历史、反复切语向 0ms 瞬时响应并节省 API Token
public final class TranslationCache: @unchecked Sendable {
    public static let shared = TranslationCache(capacity: 256)

    public struct Entry: Equatable, Sendable {
        public let translation: String
        public let provider: String
        public let cachedAt: Date

        public init(translation: String, provider: String, cachedAt: Date = Date()) {
            self.translation = translation
            self.provider = provider
            self.cachedAt = cachedAt
        }
    }

    private let capacity: Int
    private let lock = NSLock()
    private var storage: [String: Entry] = [:]
    private var accessOrder: [String] = []

    public init(capacity: Int = 256) {
        self.capacity = max(1, capacity)
    }

    public static func makeKey(
        engine: PrimaryEngine,
        profileID: String,
        source: Language?,
        target: Language,
        style: TranslationStyle,
        offlineOnly: Bool,
        text: String
    ) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        let hashHex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(engine.rawValue)|\(profileID)|\(source?.rawValue ?? "auto")->\(target.rawValue)|\(style.rawValue)|\(offlineOnly)|\(hashHex)"
    }

    public func get(_ key: String) -> Entry? {
        lock.lock()
        defer { lock.unlock() }
        guard let entry = storage[key] else { return nil }
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
        return entry
    }

    public func set(_ key: String, translation: String, provider: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[key] = Entry(translation: translation, provider: provider)
        if let idx = accessOrder.firstIndex(of: key) {
            accessOrder.remove(at: idx)
        }
        accessOrder.append(key)
        while accessOrder.count > capacity {
            let evicted = accessOrder.removeFirst()
            storage.removeValue(forKey: evicted)
        }
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
        accessOrder.removeAll()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return storage.count
    }
}
