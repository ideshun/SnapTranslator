import AppKit
import SwiftUI

/// 结果面板数据模型：一次截屏翻译的完整生命周期
@MainActor
final class ResultModel: ObservableObject {
    enum Phase: Equatable {
        case idle
        case recognizing
        case translating
        case done
        case failed(String)
    }

    enum Tab: String, CaseIterable, Identifiable {
        case recognize = "识别"
        case translation = "翻译"
        case sideBySide = "对照"
        case oneToOne = "1:1"

        var id: String { rawValue }
    }

    @Published var phase: Phase = .idle
    @Published var tab: Tab = .sideBySide
    @Published var image: NSImage?
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var sourceLanguage: Language?
    @Published var targetLanguage: Language = .zhHans
    @Published var providerName = ""
    /// 当前文本选区（供收藏按钮），非空时工具条显示「收藏选中」
    @Published var selectedText = ""
    /// 收藏成功后的短暂提示
    @Published var collectNotice = ""
    /// OCR 识别到的每行文字及其在图像中的归一化位置（用于翻译覆盖定位）
    @Published var ocrLines: [(text: String, rect: CGRect)] = []

    /// 识别历史记录
    @Published var history: [HistoryEntry] = []

    /// 重试所需的上次请求内容
    private(set) var retryImage: NSImage?
    private(set) var retrySourceText = ""

    struct HistoryEntry: Identifiable, Equatable {
        let id = UUID()
        let image: NSImage
        let sourceText: String
        let translatedText: String
        let timestamp: Date
        let sourceLanguage: Language?
        let targetLanguage: Language
        let providerName: String

        static func == (lhs: HistoryEntry, rhs: HistoryEntry) -> Bool {
            lhs.id == rhs.id
        }
    }

    func begin(image: NSImage, target: Language) {
        reset()
        self.image = image
        retryImage = image
        targetLanguage = target
        phase = .recognizing
    }

    func recognized(text: String, lines: [(text: String, rect: CGRect)] = []) {
        sourceText = text
        retrySourceText = text
        ocrLines = lines
        phase = .translating
    }

    func finished(translation: String, provider: String, source: Language?) {
        translatedText = translation
        providerName = provider
        sourceLanguage = source
        phase = .done

        // 记录识别历史
        if let image {
            let entry = HistoryEntry(
                image: image,
                sourceText: sourceText,
                translatedText: translation,
                timestamp: Date(),
                sourceLanguage: source,
                targetLanguage: targetLanguage,
                providerName: provider
            )
            history.insert(entry, at: 0)
        }
    }

    func failed(_ message: String) {
        phase = .failed(message)
    }

    func reset() {
        phase = .idle
        image = nil
        sourceText = ""
        translatedText = ""
        sourceLanguage = nil
        providerName = ""
        selectedText = ""
        collectNotice = ""
        retrySourceText = ""
        ocrLines = []
    }
}
