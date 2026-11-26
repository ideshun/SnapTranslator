import AppKit
import Foundation

/// 持久化识别历史条目：含压缩截图文件名、原文、译文、OCR 行位置（回看时依然支持 1:1 覆盖渲染）与星标状态
public struct HistoryRecord: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let imageFileName: String?
    public let sourceText: String
    public let translatedText: String
    public let timestamp: Date
    public let sourceLanguage: Language?
    public let targetLanguage: Language
    public let providerName: String
    public let ocrLines: [OCRLine]
    public var isStarred: Bool

    public init(
        id: UUID = UUID(),
        imageFileName: String? = nil,
        sourceText: String,
        translatedText: String,
        timestamp: Date = Date(),
        sourceLanguage: Language?,
        targetLanguage: Language,
        providerName: String,
        ocrLines: [OCRLine] = [],
        isStarred: Bool = false
    ) {
        self.id = id
        self.imageFileName = imageFileName
        self.sourceText = sourceText
        self.translatedText = translatedText
        self.timestamp = timestamp
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.providerName = providerName
        self.ocrLines = ocrLines
        self.isStarred = isStarred
    }
}

/// 识别历史磁盘存储：
/// - 索引存 `Application Support/SnapTranslator/history/index.json`
/// - 图片经安全降采样（最长边 ≤ 1600pt）+ JPEG 压缩落盘，彻底解决内存爆涨与重启丢失
/// - 星标条目在裁剪上限时优先保留，删除时自动清理孤儿图片文件
@MainActor
public final class HistoryStore: ObservableObject {
    /// 保留上限特殊值：-1 表示无限制保留
    public static let unlimitedLimit = -1

    @Published public private(set) var records: [HistoryRecord] = []

    private let baseDirectory: URL?
    private let indexURL: URL?
    private let imagesDirectory: URL?
    /// 内存图片缓存（限制数量，避免大历史列表内存膨胀）
    private var imageCache: [UUID: NSImage] = [:]

    public init(inMemory: Bool = false, customDirectory: URL? = nil) {
        if inMemory {
            baseDirectory = nil
            indexURL = nil
            imagesDirectory = nil
        } else {
            let root: URL?
            if let customDirectory {
                root = customDirectory
            } else {
                root = FileManager.default
                    .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first?
                    .appendingPathComponent("SnapTranslator/history", isDirectory: true)
            }
            baseDirectory = root
            indexURL = root?.appendingPathComponent("index.json")
            imagesDirectory = root?.appendingPathComponent("images", isDirectory: true)

            if let imagesDirectory {
                try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
            }
        }
        load()
    }

    /// 新增一条历史记录并落盘
    @discardableResult
    public func append(
        image: NSImage?,
        sourceText: String,
        translatedText: String,
        sourceLanguage: Language?,
        targetLanguage: Language,
        providerName: String,
        ocrLines: [OCRLine],
        limit: Int
    ) -> HistoryRecord? {
        guard limit != 0 else { return nil }
        let id = UUID()
        var fileName: String?

        if let image {
            let archived = Self.downsampleIfNeeded(image, maxSide: 1600)
            imageCache[id] = archived
            if let imagesDirectory, let jpeg = archived.jpegData(compressionFactor: 0.84) {
                let name = "\(id.uuidString).jpg"
                let url = imagesDirectory.appendingPathComponent(name)
                do {
                    try jpeg.write(to: url, options: .atomic)
                    fileName = name
                } catch {
                    AppLogger.persistence.error("历史图片写入失败: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let record = HistoryRecord(
            id: id,
            imageFileName: fileName,
            sourceText: sourceText,
            translatedText: translatedText,
            timestamp: Date(),
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            providerName: providerName,
            ocrLines: ocrLines,
            isStarred: false
        )
        records.insert(record, at: 0)
        trim(limit: limit)
        persistIndex()
        return record
    }

    public func toggleStar(_ recordID: UUID) {
        guard let idx = records.firstIndex(where: { $0.id == recordID }) else { return }
        records[idx].isStarred.toggle()
        persistIndex()
    }

    public func delete(_ recordID: UUID) {
        if let idx = records.firstIndex(where: { $0.id == recordID }) {
            let removed = records.remove(at: idx)
            removeImageFile(for: removed)
            imageCache.removeValue(forKey: recordID)
            persistIndex()
        }
    }

    public func clearAll(keepStarred: Bool = false) {
        if keepStarred {
            let toRemove = records.filter { !$0.isStarred }
            for item in toRemove {
                removeImageFile(for: item)
                imageCache.removeValue(forKey: item.id)
            }
            records.removeAll { !$0.isStarred }
        } else {
            for item in records {
                removeImageFile(for: item)
            }
            imageCache.removeAll()
            records.removeAll()
        }
        persistIndex()
    }

    /// 裁剪历史数量：limit < 0 表示无限制；星标记录始终豁免清理
    public func trim(limit: Int) {
        if limit < 0 { return }
        if limit == 0 {
            clearAll(keepStarred: true)
            return
        }
        let unstarredCount = records.filter { !$0.isStarred }.count
        guard unstarredCount > limit else { return }

        var keptUnstarred = 0
        var remaining: [HistoryRecord] = []
        for record in records {
            if record.isStarred {
                remaining.append(record)
            } else if keptUnstarred < limit {
                remaining.append(record)
                keptUnstarred += 1
            } else {
                removeImageFile(for: record)
                imageCache.removeValue(forKey: record.id)
            }
        }
        records = remaining
        persistIndex()
    }

    /// 按需读取历史图片（带轻量缓存）
    public func image(for record: HistoryRecord) -> NSImage? {
        if let cached = imageCache[record.id] {
            return cached
        }
        guard let fileName = record.imageFileName,
              let url = imagesDirectory?.appendingPathComponent(fileName),
              let loaded = NSImage(contentsOf: url)
        else { return nil }

        if imageCache.count > 40 {
            imageCache.removeAll()
        }
        imageCache[record.id] = loaded
        return loaded
    }

    // MARK: - 私有辅助

    private func load() {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return }
        do {
            records = try JSONDecoder().decode([HistoryRecord].self, from: data)
        } catch {
            AppLogger.persistence.error("识别历史读取失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func persistIndex() {
        guard let indexURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(records)
            try data.write(to: indexURL, options: .atomic)
        } catch {
            AppLogger.persistence.error("识别历史索引写入失败: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func removeImageFile(for record: HistoryRecord) {
        guard let fileName = record.imageFileName,
              let url = imagesDirectory?.appendingPathComponent(fileName)
        else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 纯 CoreGraphics 降采样（避免已废弃的 NSImage.lockFocus）
    private static func downsampleIfNeeded(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxSide, let cg = image.cgImageFast else { return image }

        let scale = maxSide / longest
        let targetW = max(1, Int((size.width * scale).rounded(.down)))
        let targetH = max(1, Int((size.height * scale).rounded(.down)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: targetW,
            height: targetH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return image }

        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        guard let outCG = ctx.makeImage() else { return image }
        return NSImage(cgImage: outCG, size: NSSize(width: targetW, height: targetH))
    }
}
