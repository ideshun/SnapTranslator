import AppKit
import SnapTranslatorCore
import SwiftUI

/// 结果面板数据模型：一次截屏/文本翻译的完整生命周期
@MainActor
final class ResultModel: ObservableObject {
    typealias Tab = PanelTab

    enum Phase: Equatable {
        case idle
        case recognizing
        case translating
        case done
        case failed(String)
    }

    struct Notice: Equatable {
        enum Kind: Equatable {
            case success
            case info
            case warning
            case error
        }
        let id = UUID()
        let text: String
        let kind: Kind
    }

    struct QuickExplainState: Equatable {
        let phrase: String
        var content: String
        var isLoading: Bool
        var errorMessage: String?
    }

    @Published var phase: Phase = .idle
    @Published var tab: PanelTab = .translation

    @Published var image: NSImage?
    /// 每次载入新图生成唯一 UUID，彻底取代不安全的指针地址作为缓存键
    @Published var imageID: UUID = UUID()
    @Published var sourceText = ""
    @Published var rawOCRText = ""
    @Published var smartOCRText = ""
    @Published var translatedText = ""
    @Published var translatedBlocks: [String]?
    @Published var sourceLanguage: Language?
    @Published var targetLanguage: Language = .zhHans
    @Published var providerName = ""
    @Published var fromCache = false

    /// 面板级临时引擎覆盖（切换后立即触发重译）；nil 表示跟随设置
    @Published var engineOverride: PrimaryEngine?
    /// 面板级临时翻译风格覆盖；nil 表示跟随设置
    @Published var styleOverride: TranslationStyle?

    @Published var selectedText = ""
    @Published var leftSelectedText = ""
    @Published var notice: Notice?
    @Published var isLiveTranslating = false

    /// OCR 识别到的行与坐标（供 1:1 渲染与持久化历史回看）
    @Published var ocrLines: [OCRLine] = []

    /// 异步渲染产出的 1:1 覆盖译文图（彻底离开 SwiftUI body 同步路径）
    @Published var renderedCoverImage: NSImage?
    @Published var isRenderingCover = false

    /// 双引擎并排对比状态
    @Published var compareEnabled = false
    @Published var compareTranslatedText = ""
    @Published var compareProviderName = ""
    @Published var isCompareTranslating = false
    @Published var compareError: String?

    /// AI 划词速释浮层
    @Published var quickExplain: QuickExplainState?

    /// 截屏完成后默认聚焦页签
    var defaultDoneTab: PanelTab = .oneToOne

    private var noticeClearTask: Task<Void, Never>?
    private var renderCoverTask: Task<Void, Never>?

    var hasContent: Bool {
        image != nil || !sourceText.isEmpty || !translatedText.isEmpty
    }

    /// 兼容旧诊断访问
    var collectNotice: String {
        get { notice?.text ?? "" }
        set {
            if newValue.isEmpty {
                notice = nil
            } else {
                showNotice(newValue, kind: .info)
            }
        }
    }

    func showNotice(_ text: String, kind: Notice.Kind = .success, duration: Double = 2.5) {
        noticeClearTask?.cancel()
        let item = Notice(text: text, kind: kind)
        notice = item
        noticeClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            if self?.notice?.id == item.id {
                self?.notice = nil
            }
        }
    }

    func begin(image: NSImage, target: Language) {
        reset()
        self.image = image
        self.imageID = UUID()
        self.targetLanguage = target
        self.phase = .recognizing
    }

    func recognized(result: OCRResult, smartMerge: Bool) {
        rawOCRText = result.rawText
        smartOCRText = result.smartMergedText
        sourceText = result.text(smartMerge: smartMerge)
        ocrLines = result.lines
        phase = .translating
    }

    func finished(
        outcome: TranslationOutcome,
        source: Language?,
        translatedBlocks: [String]? = nil,
        preserveTab: Bool = false
    ) {
        translatedText = outcome.translation
        providerName = outcome.provider
        fromCache = outcome.fromCache
        sourceLanguage = source
        self.translatedBlocks = translatedBlocks
        isLiveTranslating = false
        phase = .done

        if !preserveTab {
            tab = defaultDoneTab
        }
        if let fallback = outcome.fallbackNotice, !fallback.isEmpty {
            showNotice(fallback, kind: .warning, duration: 3.5)
        }
        scheduleCoverRender()
    }

    func restore(record: HistoryRecord, image: NSImage?) {
        reset()
        self.image = image
        self.imageID = record.id
        self.sourceText = record.sourceText
        self.rawOCRText = record.sourceText
        self.smartOCRText = record.sourceText
        self.translatedText = record.translatedText
        self.sourceLanguage = record.sourceLanguage
        self.targetLanguage = record.targetLanguage
        self.providerName = record.providerName
        self.ocrLines = record.ocrLines
        self.phase = .done
        if image != nil {
            self.tab = record.ocrLines.isEmpty ? .sideBySide : defaultDoneTab
            scheduleCoverRender()
        } else {
            self.tab = .translation
        }
    }

    /// 在后台线程异步渲染 1:1 译文覆盖图（零主线程卡顿）
    func scheduleCoverRender() {
        renderCoverTask?.cancel()
        guard let image, !translatedText.isEmpty, !ocrLines.isEmpty,
              let cg = image.cgImageFast
        else {
            renderedCoverImage = nil
            isRenderingCover = false
            return
        }

        let pointSize = image.size
        let translation = translatedText
        let lines = ocrLines
        let blocks = translatedBlocks
        let targetImageID = imageID

        isRenderingCover = true
        renderCoverTask = Task { [weak self] in
            let rendered = await Task.detached(priority: .userInitiated) {
                ImageTranslationRenderer.render(
                    cgImage: cg,
                    pointSize: pointSize,
                    translation: translation,
                    ocrLines: lines,
                    translatedBlocks: blocks
                )
            }.value
            guard !Task.isCancelled, let self, self.imageID == targetImageID else { return }
            self.renderedCoverImage = rendered
            self.isRenderingCover = false
        }
    }

    func failed(_ message: String) {
        isLiveTranslating = false
        phase = .failed(message)
    }

    func reset() {
        renderCoverTask?.cancel()
        noticeClearTask?.cancel()
        phase = .idle
        image = nil
        imageID = UUID()
        sourceText = ""
        rawOCRText = ""
        smartOCRText = ""
        translatedText = ""
        translatedBlocks = nil
        renderedCoverImage = nil
        isRenderingCover = false
        isLiveTranslating = false
        sourceLanguage = nil
        providerName = ""
        fromCache = false
        selectedText = ""
        leftSelectedText = ""
        notice = nil
        ocrLines = []
        compareTranslatedText = ""
        compareProviderName = ""
        isCompareTranslating = false
        compareError = nil
        quickExplain = nil
    }
}
