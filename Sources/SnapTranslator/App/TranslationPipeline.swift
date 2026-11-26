import AppKit
import SnapTranslatorCore

/// 统一翻译编排管线：
/// 彻底取代旧版 AppDelegate 中 4 套重复的翻译实现，统一收敛：
/// - 截屏/导入图片 OCR → 流式翻译 → 1:1 编号块对齐 → 持久化历史
/// - 左侧编辑实时防抖翻译（真 Task.cancel() 终止底层网络请求）
/// - 切换源/目标语言、切换引擎、切换风格、双引擎并排对比、AI 划词速释
/// - 静默 OCR（识别后直接复制剪贴板，不打扰主面板）
@MainActor
final class TranslationPipeline {
    private let settings: SettingsStore
    private let historyStore: HistoryStore
    private let ocrService = VisionOCRService()
    private let translationHost: TranslationHostWindowController
    let model: ResultModel

    /// 面板级临时源语言锁定（仅当前内容有效，新截屏自动解除）
    private(set) var sessionSourceOverride: Language?
    private var lastOCRResult: OCRResult?
    private var lastCapturedImage: NSImage?

    private var activeOCRTask: Task<Void, Never>?
    private var activeTranslateTask: Task<Void, Never>?
    private var activeCompareTask: Task<Void, Never>?
    private var activeExplainTask: Task<Void, Never>?
    private var liveDebounceTask: Task<Void, Never>?
    private var activeHostCount = 0

    init(
        settings: SettingsStore,
        historyStore: HistoryStore,
        translationHost: TranslationHostWindowController,
        model: ResultModel
    ) {
        self.settings = settings
        self.historyStore = historyStore
        self.translationHost = translationHost
        self.model = model
    }

    // MARK: - 1. 图片截屏 / 拖放 / 粘贴入口

    func processCapturedImage(_ image: NSImage, preserveTab: Bool = false, addHistory: Bool = true) {
        cancelOngoingWork()
        lastCapturedImage = image
        if addHistory {
            sessionSourceOverride = nil
            model.defaultDoneTab = settings.defaultDoneTab
            model.begin(image: image, target: settings.targetLanguage)
        } else {
            model.phase = .recognizing
        }

        let preferredLang = sessionSourceOverride ?? settings.persistentSourceLanguage
        let languages = VisionOCRService.recognitionLanguages(preferring: preferredLang)
        let smartMerge = settings.ocrSmartMerge

        activeOCRTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.ocrService.recognize(image, languages: languages)
                guard !Task.isCancelled else { return }
                let text = result.text(smartMerge: smartMerge)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    self.model.failed("未识别到文字，请调整选区后重试")
                    return
                }
                self.lastOCRResult = result
                self.model.recognized(result: result, smartMerge: smartMerge)
                self.runImageTranslation(
                    text: text,
                    ocrResult: result,
                    image: image,
                    preserveTab: preserveTab,
                    addHistory: addHistory
                )
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.model.failed("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    /// 静默截屏 OCR：不展示主面板，直接将识别文字写入剪贴板并返回文字供轻量 HUD 提示
    func silentOCR(image: NSImage) async -> String? {
        let languages = VisionOCRService.recognitionLanguages(preferring: settings.persistentSourceLanguage)
        do {
            let result = try await ocrService.recognize(image, languages: languages)
            let text = result.text(smartMerge: settings.ocrSmartMerge).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            NSPasteboard.writeString(text)
            return text
        } catch {
            AppLogger.ocr.error("静默 OCR 失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - 2. 文本直接翻译 / 实时防抖翻译

    func scheduleLiveTranslate(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        liveDebounceTask?.cancel()

        if trimmed.isEmpty {
            activeTranslateTask?.cancel()
            activeCompareTask?.cancel()
            model.translatedText = ""
            model.compareTranslatedText = ""
            model.compareError = nil
            model.isLiveTranslating = false
            return
        }

        model.isLiveTranslating = true
        liveDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self?.runTextTranslation(text: trimmed, isLive: true)
        }
    }

    func translateTextImmediately(_ text: String, addHistory: Bool = false) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        liveDebounceTask?.cancel()
        model.sourceText = trimmed
        model.tab = .translation
        model.phase = .translating
        runTextTranslation(text: trimmed, isLive: false, addHistory: addHistory)
    }

    // MARK: - 3. 语向 / 引擎 / 风格 / OCR 合并切换与重试

    func setSourceLanguage(_ lang: Language?) {
        sessionSourceOverride = lang
        retranslateCurrent()
    }

    func setTargetLanguage(_ lang: Language) {
        settings.targetLanguage = lang
        retranslateCurrent()
    }

    func setEngineOverride(_ engine: PrimaryEngine?) {
        model.engineOverride = engine
        retranslateCurrent()
    }

    func setStyleOverride(_ style: TranslationStyle?) {
        model.styleOverride = style
        retranslateCurrent()
    }

    func toggleSmartMerge() {
        settings.ocrSmartMerge.toggle()
        if let ocr = lastOCRResult {
            let nextText = ocr.text(smartMerge: settings.ocrSmartMerge)
            model.sourceText = nextText
            retranslateCurrent()
        }
    }

    func toggleCompareMode() {
        model.compareEnabled.toggle()
        if model.compareEnabled, !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let resolved = resolveLanguages(for: model.sourceText)
            runCompareTranslation(text: model.sourceText, source: resolved.source, target: resolved.target)
        } else if !model.compareEnabled {
            activeCompareTask?.cancel()
            model.compareTranslatedText = ""
            model.compareError = nil
            model.isCompareTranslating = false
        }
    }

    func swapLanguages() {
        let pair = LanguagePolicy.swapped(
            currentSource: sessionSourceOverride ?? settings.persistentSourceLanguage ?? model.sourceLanguage,
            currentTarget: model.targetLanguage,
            fallbackText: model.sourceText
        )
        sessionSourceOverride = pair.source
        settings.targetLanguage = pair.target
        model.sourceLanguage = pair.source
        model.targetLanguage = pair.target
        model.showNotice("已切换语向：\(pair.source.displayName) → \(pair.target.displayName)", kind: .info, duration: 2.0)

        if (model.tab == .translation || model.image == nil) && !model.translatedText.isEmpty {
            let nextSourceText = model.translatedText
            model.sourceText = nextSourceText
            model.translatedText = ""
            runTextTranslation(text: nextSourceText, isLive: true)
            return
        }
        retranslateCurrent()
    }

    func retry() {
        if let image = lastCapturedImage ?? model.image {
            processCapturedImage(image, preserveTab: true, addHistory: false)
        } else if !model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            runTextTranslation(text: model.sourceText, isLive: false)
        }
    }

    func retranslateCurrent() {
        let trimmed = model.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let image = model.image, let ocr = lastOCRResult {
            model.phase = .translating
            runImageTranslation(text: trimmed, ocrResult: ocr, image: image, preserveTab: true, addHistory: false)
        } else if let image = model.image {
            model.phase = .translating
            let ocr = OCRResult(lines: model.ocrLines)
            runImageTranslation(text: trimmed, ocrResult: ocr, image: image, preserveTab: true, addHistory: false)
        } else {
            runTextTranslation(text: trimmed, isLive: model.phase == .idle)
        }
    }

    /// 生词本词条翻译（严格尊重词条自身记录的源/目标语言）
    func translateForWordBook(text: String, source: Language?, target: Language?) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let resolved: ResolvedLanguagePair
        if let target {
            resolved = ResolvedLanguagePair(source: source ?? LanguageDetector.detect(trimmed), target: target)
        } else {
            resolved = LanguagePolicy.resolve(
                text: trimmed,
                sessionSourceOverride: source,
                persistentSourceLock: nil,
                preferredTarget: settings.targetLanguage
            )
        }

        beginHostUsage()
        defer { endHostUsage() }

        let service = makeService()
        do {
            let outcome = try await service.translate(trimmed, from: resolved.source, to: resolved.target)
            return outcome.translation
        } catch {
            return "翻译失败：\(error.localizedDescription)"
        }
    }

    /// 轻量 AI 划词速释
    func quickExplain(phrase: String, context: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        activeExplainTask?.cancel()

        let target = model.targetLanguage
        model.quickExplain = .init(phrase: trimmed, content: "", isLoading: true, errorMessage: nil)

        let service = makeService()
        activeExplainTask = Task { [weak self] in
            guard let self else { return }
            do {
                let explanation = try await service.quickExplain(phrase: trimmed, context: context, target: target)
                guard !Task.isCancelled else { return }
                self.model.quickExplain = .init(phrase: trimmed, content: explanation, isLoading: false, errorMessage: nil)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.model.quickExplain = .init(
                    phrase: trimmed,
                    content: "",
                    isLoading: false,
                    errorMessage: error.localizedDescription
                )
            }
        }
    }

    func cancelOngoingWork() {
        liveDebounceTask?.cancel()
        activeOCRTask?.cancel()
        activeTranslateTask?.cancel()
        activeCompareTask?.cancel()
        activeExplainTask?.cancel()
    }

    // MARK: - 内部执行实现

    private func resolveLanguages(for text: String) -> ResolvedLanguagePair {
        LanguagePolicy.resolve(
            text: text,
            sessionSourceOverride: sessionSourceOverride,
            persistentSourceLock: settings.persistentSourceLanguage,
            preferredTarget: settings.targetLanguage
        )
    }

    private func makeService(primaryOverride: PrimaryEngine? = nil) -> TranslationService {
        TranslationService(
            config: settings.makeTranslationConfig(
                primaryOverride: primaryOverride ?? model.engineOverride,
                styleOverride: model.styleOverride,
                anchor: translationHost.anchor
            )
        )
    }

    private func runImageTranslation(
        text: String,
        ocrResult: OCRResult,
        image: NSImage,
        preserveTab: Bool,
        addHistory: Bool
    ) {
        activeTranslateTask?.cancel()
        let resolved = resolveLanguages(for: text)
        model.sourceLanguage = resolved.source
        model.targetLanguage = resolved.target
        model.isLiveTranslating = true

        AppLogger.translation.info(
            "translate(image) src=\(resolved.source?.rawValue ?? "auto", privacy: .public) tgt=\(resolved.target.rawValue, privacy: .public) blocks=\(ocrResult.blocks.count)"
        )

        let service = makeService()
        let blockTexts = ocrResult.blocks.map(\.mergedText)

        if model.compareEnabled {
            runCompareTranslation(text: text, source: resolved.source, target: resolved.target)
        }

        beginHostUsage()
        activeTranslateTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endHostUsage() }
            do {
                // 若有多个视觉段落块且 AI 引擎可用，优先走编号块翻译，既拿到完整译文又获得 1:1 块级精准映射
                var alignedBlocks: [String]?
                let outcome: TranslationOutcome
                let effectiveEngine = self.model.engineOverride ?? self.settings.primaryEngine
                let prefersAIBlocks = !self.settings.offlineOnlyMode
                    && self.settings.hasConfiguredAI
                    && (effectiveEngine == .openai || effectiveEngine == .auto)
                    && blockTexts.count >= 2 && blockTexts.count <= 24

                if prefersAIBlocks,
                   let blocksResult = await service.translateBlocks(blockTexts, from: resolved.source, to: resolved.target) {
                    alignedBlocks = blocksResult
                    outcome = TranslationOutcome(
                        translation: blocksResult.joined(separator: "\n\n"),
                        provider: self.settings.activeAIProfile.name,
                        fallbackNotice: nil,
                        fromCache: false
                    )
                } else {
                    outcome = try await service.translate(
                        text,
                        from: resolved.source,
                        to: resolved.target,
                        onPartial: { [weak self] partial in
                            Task { @MainActor [weak self] in
                                guard let self, !Task.isCancelled else { return }
                                self.model.translatedText = partial
                            }
                        }
                    )
                }

                guard !Task.isCancelled else { return }
                self.model.finished(
                    outcome: outcome,
                    source: resolved.source,
                    translatedBlocks: alignedBlocks,
                    preserveTab: preserveTab
                )
                if addHistory {
                    self.historyStore.append(
                        image: image,
                        sourceText: text,
                        translatedText: outcome.translation,
                        sourceLanguage: resolved.source,
                        targetLanguage: resolved.target,
                        providerName: outcome.provider,
                        ocrLines: ocrResult.lines,
                        limit: self.settings.historyLimit
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.model.failed("翻译失败：\(error.localizedDescription)")
            }
        }
    }

    private func runTextTranslation(text: String, isLive: Bool, addHistory: Bool = false) {
        activeTranslateTask?.cancel()
        let resolved = resolveLanguages(for: text)
        model.sourceLanguage = resolved.source
        model.targetLanguage = resolved.target
        model.isLiveTranslating = true

        if model.compareEnabled {
            runCompareTranslation(text: text, source: resolved.source, target: resolved.target)
        }

        let service = makeService()
        beginHostUsage()
        activeTranslateTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endHostUsage() }
            do {
                let outcome = try await service.translate(
                    text,
                    from: resolved.source,
                    to: resolved.target,
                    onPartial: { [weak self] partial in
                        Task { @MainActor [weak self] in
                            guard let self, !Task.isCancelled else { return }
                            self.model.translatedText = partial
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                self.model.translatedText = outcome.translation
                self.model.providerName = outcome.provider
                self.model.fromCache = outcome.fromCache
                self.model.isLiveTranslating = false
                if !isLive {
                    self.model.phase = .done
                }
                if let fallback = outcome.fallbackNotice {
                    self.model.showNotice(fallback, kind: .warning, duration: 3.5)
                }
                if addHistory {
                    self.historyStore.append(
                        image: nil,
                        sourceText: text,
                        translatedText: outcome.translation,
                        sourceLanguage: resolved.source,
                        targetLanguage: resolved.target,
                        providerName: outcome.provider,
                        ocrLines: [],
                        limit: self.settings.historyLimit
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.model.isLiveTranslating = false
                if isLive {
                    self.model.showNotice("实时翻译失败：\(error.localizedDescription)", kind: .error, duration: 4.5)
                } else {
                    self.model.failed("翻译失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func runCompareTranslation(text: String, source: Language?, target: Language) {
        activeCompareTask?.cancel()
        let secondary = settings.compareSecondaryEngine
        model.isCompareTranslating = true
        model.compareError = nil
        model.compareProviderName = secondary == .openai ? settings.activeAIProfile.name : secondary.shortName

        let service = makeService()
        beginHostUsage()
        activeCompareTask = Task { [weak self] in
            guard let self else { return }
            defer { self.endHostUsage() }
            do {
                let outcome = try await service.translateWithSpecificEngine(secondary, text: text, from: source, to: target)
                guard !Task.isCancelled else { return }
                self.model.compareTranslatedText = outcome.translation
                self.model.compareProviderName = outcome.provider
                self.model.isCompareTranslating = false
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.model.compareError = error.localizedDescription
                self.model.isCompareTranslating = false
            }
        }
    }

    private func beginHostUsage() {
        activeHostCount += 1
        translationHost.show()
    }

    private func endHostUsage() {
        activeHostCount = max(0, activeHostCount - 1)
        if activeHostCount == 0 {
            translationHost.hide()
        }
    }
}
