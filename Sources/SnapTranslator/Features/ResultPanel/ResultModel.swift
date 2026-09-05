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
        case oneToOne = "对比"

        var id: String { rawValue }
    }

    @Published var phase: Phase = .idle
    /// 默认聚焦「翻译」页签，支持输入内容实时翻译
    @Published var tab: Tab = .translation
    @Published var image: NSImage?
    @Published var sourceText = ""
    @Published var translatedText = ""
    @Published var sourceLanguage: Language?
    @Published var targetLanguage: Language = .zhHans
    @Published var providerName = ""
    /// 面板级临时引擎覆盖（左下角切换）：仅影响本面板后续翻译，不改设置里的主引擎；
    /// nil 表示跟随设置
    @Published var engineOverride: PrimaryEngine?
    /// 右侧文本选区（供收藏按钮），非空时工具条显示「收藏选中」
    @Published var selectedText = ""
    /// 左侧文本选区（供左侧朗读时优先朗读选中内容）
    @Published var leftSelectedText = ""
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

    /// 翻译完成后默认聚焦的页签（由设置页配置，AppDelegate 在截屏入口同步）
    var defaultDoneTab: Tab = .oneToOne

    /// 翻译完成回调
    /// - Parameters:
    ///   - preserveTab: 是否保留当前 tab（用于语言切换后的重新翻译），默认 false 切换到默认页签
    ///   - addHistory: 是否记录历史，默认 true
    func finished(
        translation: String,
        provider: String,
        source: Language?,
        preserveTab: Bool = false,
        addHistory: Bool = true
    ) {
        translatedText = translation
        providerName = provider
        sourceLanguage = source
        phase = .done
        if !preserveTab {
            // 翻译完成后聚焦默认页签（设置里可配，默认「对比」）
            tab = defaultDoneTab
        }

        // 记录识别历史
        if addHistory, let image {
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
        engineOverride = nil
        selectedText = ""
        leftSelectedText = ""
        collectNotice = ""
        retrySourceText = ""
        ocrLines = []
    }

    /// 是否有内容（截图/原文/译文），用于判断首次启动 vs 截图识别后的窗口大小
    var hasContent: Bool {
        image != nil || !sourceText.isEmpty || !translatedText.isEmpty
    }
}
