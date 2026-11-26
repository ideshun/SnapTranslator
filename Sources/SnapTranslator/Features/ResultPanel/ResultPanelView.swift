import AppKit
import SnapTranslatorCore
import SwiftUI
import UniformTypeIdentifiers

/// 结果面板主视图：一体化毛玻璃标题工具栏 + 细腻分栏卡片内容区 + 拖放图片 + AI 速释浮层 + 状态栏
struct ResultPanelView: View {
    @ObservedObject var model: ResultModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject var historyStore: HistoryStore

    let onStartCapture: () -> Void
    let onStartSilentOCR: () -> Void
    let onRecaptureLastRegion: () -> Void
    let onTranslateClipboard: () -> Void
    let onCollect: (String, String) -> Void
    let onRetry: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onSwapLanguages: () -> Void
    let onOpenWordBook: () -> Void
    let onOpenHistory: () -> Void
    let onLiveTranslate: (String) -> Void
    let onSourceLanguageChange: (Language?) -> Void
    let onTargetLanguageChange: (Language) -> Void
    let onEngineChange: (PrimaryEngine?) -> Void
    let onStyleChange: (TranslationStyle?) -> Void
    let onToggleCompare: () -> Void
    let onQuickExplain: (String, String) -> Void
    let onImportImage: (NSImage) -> Void
    let onPinImage: (NSImage, String) -> Void
    let onRestoreHistory: (HistoryRecord) -> Void
    let onToggleSmartMerge: () -> Void
    let onClear: () -> Void

    @State private var imageScale: CGFloat = 1.0
    @State private var isDropTargeted = false

    private var fitsToViewport: Bool {
        settings.screenshotDisplayMode.fitsToViewport
    }

    var body: some View {
        VStack(spacing: 0) {
            ResultToolbarView(
                model: model,
                settings: settings,
                onStartCapture: onStartCapture,
                onCollect: onCollect,
                onRetry: onRetry,
                onTogglePin: onTogglePin,
                onOpenWordBook: onOpenWordBook,
                onOpenHistory: onOpenHistory,
                onToggleCompare: onToggleCompare
            )

            Divider()

            ZStack {
                STTheme.windowCanvas
                content
                    .animation(nil, value: model.tab)

                // 拖放图片高亮蒙层
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: STTheme.radiusLG, style: .continuous)
                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 4]))
                        .background(
                            RoundedRectangle(cornerRadius: STTheme.radiusLG, style: .continuous)
                                .fill(Color.accentColor.opacity(0.08))
                        )
                        .overlay {
                            VStack(spacing: 8) {
                                Image(systemName: "photo.badge.plus")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundStyle(Color.accentColor)
                                Text("松开即可离线 OCR 并翻译")
                                    .font(.system(size: 13.5, weight: .semibold))
                                Text("支持 PNG / JPG / WebP / HEIC")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .padding(12)
                }

                // AI 划词速释浮层
                if let explain = model.quickExplain {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            QuickExplainCard(
                                state: explain,
                                onCollect: {
                                    onCollect(explain.phrase, explain.content)
                                    model.quickExplain = nil
                                },
                                onCopy: {
                                    NSPasteboard.writeString(explain.content)
                                    model.showNotice("已复制 AI 速释", kind: .success)
                                },
                                onDismiss: { model.quickExplain = nil }
                            )
                        }
                    }
                    .padding(14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }

            Divider()

            ResultStatusBarView(
                model: model,
                settings: settings,
                onSwapLanguages: onSwapLanguages,
                onSourceLanguageChange: onSourceLanguageChange,
                onTargetLanguageChange: onTargetLanguageChange,
                onEngineChange: onEngineChange,
                onStyleChange: onStyleChange,
                onClear: onClear
            )
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.stUIFontSize, settings.uiFontSize)
        .frame(minWidth: 520, minHeight: 340)
        .onChange(of: model.imageID) { _, _ in imageScale = 1.0 }
        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - 主内容区

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .recognizing:
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(STTheme.heroGlow)
                        .frame(width: 64, height: 64)
                    ProgressView()
                        .controlSize(.regular)
                }
                VStack(spacing: 4) {
                    Text("正在离线识别文字…")
                        .font(.system(size: 13.5, weight: .semibold))
                    Text("Apple Vision 端上高精度 OCR")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .failed(let message):
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.14))
                        .frame(width: 56, height: 56)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(.orange)
                }
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 420)
                Button {
                    onRetry()
                } label: {
                    Label("重新尝试", systemImage: "arrow.clockwise")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        default:
            switch model.tab {
            case .translation:
                translationContent
            default:
                if model.phase == .idle {
                    emptyState
                } else if model.phase == .translating && model.translatedText.isEmpty {
                    translatingStatus
                } else {
                    doneContent
                }
            }
        }
    }

    // MARK: - 空闲态欢迎与快捷工作台

    private var emptyState: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 22) {
                    // Hero 标题与主入口
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(STTheme.heroGlow)
                                .frame(width: 72, height: 72)
                            Image(systemName: "character.bubble.fill")
                                .font(.system(size: 30, weight: .medium))
                                .foregroundStyle(STTheme.accentGradient)
                        }

                        VStack(spacing: 5) {
                            Text("SnapTranslator")
                                .font(.system(size: 18, weight: .semibold))
                            Text("随时截屏、粘贴或拖入图片，离线高精度 OCR 与流式翻译即刻呈现")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 10) {
                            QuickActionPill(
                                icon: "viewfinder",
                                title: "截屏翻译",
                                tokens: settings.hotkeyCapture.keyTokens,
                                accent: true,
                                action: onStartCapture
                            )
                            QuickActionPill(
                                icon: "doc.on.clipboard",
                                title: "翻译剪贴板",
                                tokens: settings.hotkeyTranslateClipboard.keyTokens,
                                accent: false,
                                action: onTranslateClipboard
                            )
                        }
                        .padding(.top, 4)
                    }

                    if !historyStore.records.isEmpty {
                        recentHistorySection
                            .frame(maxWidth: 660)
                    } else {
                        // 无历史记录时：展示 2×2 快捷能力卡片 + 拖放/选图区，填补视觉重心且可直接交互
                        emptyQuickLaunchGrid
                            .frame(maxWidth: 580)
                    }

                    // 底部轻量化能力状态条
                    HStack(spacing: 14) {
                        capabilityBadge(icon: "eye", text: "离线 Vision OCR")
                        capabilityBadge(icon: "sparkles.rectangle.stack", text: "1:1 覆盖译文图")
                        capabilityBadge(icon: "pin", text: "桌面悬浮贴图")
                        capabilityBadge(
                            icon: settings.offlineOnlyMode ? "lock.shield.fill" : "bolt.fill",
                            text: settings.offlineOnlyMode ? "纯离线隐私模式" : "\(settings.activeAIProfile.name) · 流式"
                        )
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity, minHeight: max(260, geo.size.height))
            }
        }
    }

    private var emptyQuickLaunchGrid: some View {
        VStack(spacing: 10) {
            // 交互式拖放/选择本地图片卡片
            Button(action: pickImageFile) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 38, height: 38)
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("拖入图片到窗口，或点击选择本地图片")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("支持 PNG / JPG / WebP / HEIC，也可直接按 ⌘V 粘贴截图")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("选择文件")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(STTheme.cardSurface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [5, 3]))
                )
            }
            .buttonStyle(.plain)
            .hoverFeedback("从访达选择一张图片进行 OCR 与翻译")

            // 3 格快捷功能入口
            HStack(spacing: 10) {
                EmptyActionTile(
                    icon: "doc.text.viewfinder",
                    color: .teal,
                    title: "静默截屏 OCR",
                    subtitle: "提取文字直写剪贴板",
                    tokens: settings.hotkeySilentOCR.keyTokens,
                    action: onStartSilentOCR
                )
                EmptyActionTile(
                    icon: "arrow.triangle.2.circlepath",
                    color: .orange,
                    title: "重截上次区域",
                    subtitle: "适合字幕与日志连续翻译",
                    tokens: settings.hotkeyRecapture.keyTokens,
                    action: onRecaptureLastRegion
                )
                EmptyActionTile(
                    icon: "character.bubble",
                    color: .purple,
                    title: "双栏文本翻译",
                    subtitle: "支持实时输入与双引擎对比",
                    tokens: ["⌘", "2"]
                ) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        model.tab = .translation
                    }
                }
            }
        }
    }

    private func capabilityBadge(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Text(text)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func pickImageFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .webP, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url, let img = NSImage(contentsOf: url) else { return }
            Task { @MainActor in onImportImage(img) }
        }
    }

    private var recentHistorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("最近识别", systemImage: "clock")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("查看全部 (\(historyStore.records.count))") { onOpenHistory() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                    .hoverFeedback("打开完整可搜索的识别历史窗口")
            }

            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(historyStore.records.prefix(5)) { record in
                    RecentHistoryRow(record: record, thumbnail: historyStore.image(for: record)) {
                        onRestoreHistory(record)
                    }
                }
            }
        }
    }

    private var translatingStatus: some View {
        STBalancedHSplit {
            VStack(spacing: 0) {
                TextPaneHeaderBar(
                    title: model.sourceLanguage?.displayName ?? "原文",
                    text: model.sourceText,
                    language: model.sourceLanguage,
                    selection: model.leftSelectedText,
                    accentDot: .secondary,
                    onCopied: { model.showNotice("已复制原文", kind: .success) }
                )
                Divider()
                SelectableTextView(text: model.sourceText, fontSize: settings.textFontSize)
            }
        } right: {
            VStack(spacing: 0) {
                TextPaneHeaderBar(
                    title: model.targetLanguage.displayName,
                    text: "",
                    language: model.targetLanguage,
                    selection: "",
                    accentDot: Color.accentColor
                )
                Divider()
                STTranslationSkeleton(targetLanguageName: model.targetLanguage.displayName)
            }
        }
    }

    // MARK: - 翻译页签

    private var translationContent: some View {
        STBalancedHSplit {
            // 左栏：原文可编辑
            VStack(alignment: .leading, spacing: 0) {
                TextPaneHeaderBar(
                    title: model.sourceLanguage?.displayName ?? "原文输入",
                    text: model.sourceText,
                    language: model.sourceLanguage,
                    selection: model.leftSelectedText,
                    accentDot: .secondary.opacity(0.6),
                    onCopied: { model.showNotice("已复制原文", kind: .success) }
                )
                Divider()
                EditableTextView(
                    text: $model.sourceText,
                    fontSize: settings.textFontSize,
                    onChange: onLiveTranslate,
                    onSelectionChange: { model.leftSelectedText = $0 },
                    onCollect: onCollect,
                    onQuickExplain: onQuickExplain,
                    onPasteImage: onImportImage,
                    focusOnAppear: model.phase == .idle
                )
            }
        } right: {
            // 右栏：主译文（支持双引擎上下并排对比）
            if model.compareEnabled {
                VSplitView {
                    primaryTranslationPane.frame(minHeight: 120)
                    secondaryComparePane.frame(minHeight: 110)
                }
                .background(STTheme.secondaryCanvas)
            } else {
                primaryTranslationPane
                    .background(STTheme.secondaryCanvas)
            }
        }
    }

    private var primaryTranslationPane: some View {
        let isWorking = model.isLiveTranslating || model.phase == .translating
        return VStack(alignment: .leading, spacing: 0) {
            TextPaneHeaderBar(
                title: model.targetLanguage.displayName,
                text: model.translatedText,
                language: model.targetLanguage,
                selection: model.selectedText,
                accentDot: Color.accentColor,
                onCopied: { model.showNotice("已复制译文", kind: .success) }
            ) {
                if model.compareEnabled && !model.providerName.isEmpty {
                    Text(model.providerName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(STTheme.subtleFill))
                }
            }
            Divider()

            ZStack {
                if model.translatedText.isEmpty {
                    if isWorking {
                        STTranslationSkeleton(targetLanguageName: model.targetLanguage.displayName)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "text.bubble")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(.tertiary)
                            VStack(spacing: 4) {
                                Text("在左侧输入或粘贴内容，自动实时翻译")
                                    .font(.system(size: settings.uiFontSize, weight: .medium))
                                    .foregroundStyle(.secondary)
                                Text("也可直接拖入截图，或按 \(settings.hotkeyCapture.display) 截屏翻译")
                                    .font(.system(size: max(11, settings.uiFontSize - 1.5)))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } else {
                    SelectableTextView(
                        text: model.translatedText,
                        fontSize: settings.textFontSize,
                        onSelectionChange: { model.selectedText = $0 },
                        onCollect: onCollect,
                        onQuickExplain: onQuickExplain
                    )
                    .opacity(isWorking ? 0.78 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: isWorking)
                }

                if isWorking && !model.translatedText.isEmpty {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 5) {
                                ProgressView().controlSize(.mini).scaleEffect(0.8)
                                Text("流式输出中…")
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .overlay(Capsule().stroke(STTheme.hairlineBorder, lineWidth: 0.6))
                            .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                            .padding(10)
                        }
                        Spacer()
                    }
                }
            }
        }
    }

    private var secondaryComparePane: some View {
        VStack(alignment: .leading, spacing: 0) {
            STPaneHeader(
                title: "对比 · \(model.compareProviderName.isEmpty ? settings.compareSecondaryEngine.shortName : model.compareProviderName)",
                accentDot: .purple
            ) {
                if model.isCompareTranslating {
                    ProgressView().controlSize(.mini)
                } else if !model.compareTranslatedText.isEmpty {
                    SpeechBarButton(systemImage: "doc.on.doc", tooltip: "复制对比译文") {
                        NSPasteboard.writeString(model.compareTranslatedText)
                        model.showNotice("已复制对比译文", kind: .success)
                    }
                }
            }
            Divider()

            if let err = model.compareError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else if model.compareTranslatedText.isEmpty {
                if model.isCompareTranslating {
                    STTranslationSkeleton(targetLanguageName: model.targetLanguage.displayName)
                } else {
                    Text("输入或截屏后将并行请求对比引擎")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                SelectableTextView(
                    text: model.compareTranslatedText,
                    fontSize: settings.textFontSize,
                    onCollect: onCollect,
                    onQuickExplain: onQuickExplain
                )
            }
        }
    }

    // MARK: - 完成态（识别 / 对照 / 1:1 对比）

    @ViewBuilder
    private var doneContent: some View {
        switch model.tab {
        case .recognize:
            if let image = model.image {
                STBalancedHSplit {
                    zoomableImagePane(image: image, title: "原图")
                } right: {
                    recognizeTextPane
                }
            } else {
                recognizeTextPane
            }

        case .translation:
            translationContent

        case .sideBySide:
            if let image = model.image {
                STBalancedHSplit {
                    zoomableImagePane(image: image, title: "原图")
                } right: {
                    sideBySideTextPane
                }
            } else {
                sideBySideTextPane
            }

        case .oneToOne:
            if let image = model.image {
                STBalancedHSplit {
                    zoomableImagePane(image: image, title: "原图", syncGroupID: "oneToOneSync", pinTitle: "原图贴图")
                } right: {
                    oneToOneCoverPane(image: image)
                }
            }
        }
    }

    private var recognizeTextPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextPaneHeaderBar(
                title: model.sourceLanguage?.displayName ?? "识别原文",
                text: model.sourceText,
                language: model.sourceLanguage,
                selection: model.selectedText,
                accentDot: .secondary,
                onCopied: { model.showNotice("已复制识别原文", kind: .success) }
            ) {
                if !model.rawOCRText.isEmpty && model.rawOCRText != model.smartOCRText {
                    Button(action: onToggleSmartMerge) {
                        HStack(spacing: 3) {
                            Image(systemName: settings.ocrSmartMerge ? "text.alignleft" : "list.bullet")
                                .font(.system(size: 9))
                            Text(settings.ocrSmartMerge ? "段落合并" : "原始换行")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Color.accentColor.opacity(0.13)))
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .hoverFeedback("切换 OCR 智能段落合并 / 保留原始换行并重译")
                }
            }
            Divider()

            if !model.sourceText.isEmpty {
                SelectableTextView(
                    text: model.sourceText,
                    fontSize: settings.textFontSize,
                    onSelectionChange: { model.selectedText = $0 },
                    onCollect: onCollect,
                    onQuickExplain: onQuickExplain
                )
            } else {
                Text("未识别到文字")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var sideBySideTextPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextPaneHeaderBar(
                title: model.targetLanguage.displayName,
                text: model.translatedText,
                language: model.targetLanguage,
                selection: model.selectedText,
                accentDot: Color.accentColor,
                onCopied: { model.showNotice("已复制译文", kind: .success) }
            )
            Divider()
            SelectableTextView(
                text: model.translatedText,
                fontSize: settings.textFontSize,
                onSelectionChange: { model.selectedText = $0 },
                onCollect: onCollect,
                onQuickExplain: onQuickExplain
            )
        }
    }

    private func oneToOneCoverPane(image: NSImage) -> some View {
        let displayImage = model.renderedCoverImage ?? image
        return VStack(spacing: 0) {
            STPaneHeader(
                title: "1:1 覆盖译文",
                subtitle: model.isRenderingCover ? "渲染中…" : "\(Int(image.size.width))×\(Int(image.size.height))",
                accentDot: Color.accentColor
            ) {
                if let cover = model.renderedCoverImage {
                    HStack(spacing: 3) {
                        SpeechBarButton(systemImage: "doc.on.doc", tooltip: "复制 1:1 译文图") {
                            NSPasteboard.writeImage(cover)
                            model.showNotice("已复制 1:1 译文图", kind: .success)
                        }
                        SpeechBarButton(systemImage: "square.and.arrow.down", tooltip: "保存 1:1 译文图为 PNG") {
                            saveImageAsPNG(cover)
                        }
                        SpeechBarButton(systemImage: "pin", tooltip: "把 1:1 译文图钉在桌面") {
                            onPinImage(cover, "1:1 译文贴图")
                        }
                    }
                }
            }
            Divider()
            ZStack(alignment: .bottomTrailing) {
                InteractiveImageView(
                    image: displayImage,
                    scale: $imageScale,
                    fitsToViewport: fitsToViewport,
                    syncGroupID: "oneToOneSync"
                )
                .background(STTheme.secondaryCanvas)

                if model.isRenderingCover {
                    STFloatingHUD {
                        ProgressView().controlSize(.mini).scaleEffect(0.8)
                        Text("渲染译文图…")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.white)
                    }
                    .padding(10)
                } else if let cover = model.renderedCoverImage {
                    STFloatingHUD {
                        ZoomBarButton(systemImage: "doc.on.doc", tooltip: "复制译文图") {
                            NSPasteboard.writeImage(cover)
                            model.showNotice("已复制译文图", kind: .success)
                        }
                        ZoomBarButton(systemImage: "square.and.arrow.down", tooltip: "保存为 PNG") {
                            saveImageAsPNG(cover)
                        }
                        ZoomBarButton(systemImage: "pin", tooltip: "钉在桌面") {
                            onPinImage(cover, "1:1 译文贴图")
                        }
                    }
                    .padding(10)
                }
            }
        }
    }

    private func zoomableImagePane(
        image: NSImage,
        title: String,
        syncGroupID: String? = nil,
        pinTitle: String = "原图贴图"
    ) -> some View {
        VStack(spacing: 0) {
            STPaneHeader(
                title: title,
                subtitle: "\(Int(image.size.width))×\(Int(image.size.height))",
                accentDot: .secondary.opacity(0.6)
            ) {
                SpeechBarButton(systemImage: "pin", tooltip: "把原图钉在桌面（悬浮贴图）") {
                    onPinImage(image, pinTitle)
                }
            }
            Divider()
            InteractiveImageView(
                image: image,
                scale: $imageScale,
                fitsToViewport: fitsToViewport,
                syncGroupID: syncGroupID
            )
            .background(STTheme.secondaryCanvas)
            .overlay(alignment: .bottomTrailing) {
                ZoomControlBar(scale: $imageScale) {
                    onPinImage(image, pinTitle)
                }
            }
        }
        .frame(minWidth: 180)
    }

    private func saveImageAsPNG(_ image: NSImage) {
        guard let png = image.pngData() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "SnapTranslator-译文图.png"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                Task { @MainActor in model.showNotice("已保存 \(url.lastPathComponent)", kind: .success) }
            } catch {
                Task { @MainActor in model.showNotice("保存失败：\(error.localizedDescription)", kind: .error) }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else {
                        url = item as? URL
                    }
                    guard let url, let img = NSImage(contentsOf: url) else { return }
                    Task { @MainActor in onImportImage(img) }
                }
                return true
            }
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage else { return }
                    Task { @MainActor in onImportImage(img) }
                }
                return true
            }
        }
        return false
    }
}

/// 空态快捷入口胶囊按钮
private struct QuickActionPill: View {
    let icon: String
    let title: String
    let tokens: [String]
    let accent: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent ? Color.white : Color.accentColor)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent ? Color.white : Color.primary)
                if !accent {
                    KbdShortcutView(tokens: tokens)
                } else {
                    Text(tokens.joined())
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.88))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.18)))
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(accent ? Color.accentColor.opacity(hovered ? 0.9 : 1.0) : STTheme.panelSurface)
                    .shadow(color: (accent ? Color.accentColor : Color.black).opacity(hovered ? 0.22 : 0.08), radius: hovered ? 6 : 3, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(accent ? Color.clear : STTheme.hairlineBorder, lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverFeedback(title)
    }
}

private struct RecentHistoryRow: View {
    let record: HistoryRecord
    let thumbnail: NSImage?
    let onSelect: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 11) {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 54, height: 38)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(STTheme.hairlineBorder, lineWidth: 0.5)
                        )
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 54, height: 38)
                        .overlay(
                            Image(systemName: "text.alignleft")
                                .font(.system(size: 14))
                                .foregroundStyle(Color.accentColor.opacity(0.75))
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        if record.isStarred {
                            Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                        }
                        Text(record.sourceText.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .foregroundStyle(.primary)
                    }
                    HStack(spacing: 6) {
                        Text(record.translatedText.replacingOccurrences(of: "\n", with: " "))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(record.timestamp, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1.0 : 0.25)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isHovered ? STTheme.cardHoverSurface : STTheme.cardSurface)
                    .shadow(color: isHovered ? Color.black.opacity(0.05) : .clear, radius: 4, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isHovered ? STTheme.strongBorder : STTheme.hairlineBorder, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .hoverFeedback("在主面板恢复该条记录")
    }
}

/// 空态快捷能力磁贴卡片
private struct EmptyActionTile: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let tokens: [String]
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    STSidebarBadge(systemImage: icon, color: color, size: 26)
                    Spacer()
                    KbdShortcutView(tokens: tokens)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hovered ? STTheme.cardHoverSurface : STTheme.cardSurface)
                    .shadow(color: Color.black.opacity(hovered ? 0.05 : 0.015), radius: hovered ? 5 : 2, y: 1.5)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(hovered ? STTheme.strongBorder : STTheme.hairlineBorder, lineWidth: 0.7)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .hoverFeedback(title)
    }
}
