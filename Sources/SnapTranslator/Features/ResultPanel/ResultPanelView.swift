import AppKit
import SwiftUI

/// 结果面板主视图：工具条 + 内容区（识别结果/翻译/对照/1:1 + 各阶段状态）
struct ResultPanelView: View {
    @ObservedObject var model: ResultModel
    @ObservedObject var settings: SettingsStore
    @ObservedObject private var speech = SpeechManager.shared

    let onCollect: (String, String) -> Void
    let onRetry: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onSwapLanguages: () -> Void
    let onOpenWordBook: () -> Void
    /// 编辑翻译页签左侧原文后触发实时翻译
    let onLiveTranslate: (String) -> Void
    /// 切换源语言/目标语言
    var onSourceLanguageChange: ((Language?) -> Void)?
    var onTargetLanguageChange: ((Language) -> Void)?
    /// 清空左侧内容
    var onClear: (() -> Void)?

    @Namespace private var tabAnimation
    @State private var justCopied = false
    @State private var retryAngle: Double = 0
    @State private var swapAngle: Double = 0
    @State private var hoveredTab: ResultModel.Tab?

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
                .animation(nil, value: model.tab)
            Divider()
            statusBar
        }
        .frame(minWidth: 420, minHeight: 280)
        .onChange(of: model.phase) { _, _ in
            // 新截图/新翻译开始时重置缩放
            imageScale = 1.0
        }
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 8) {
            tabBar

            Spacer()

            if model.phase == .done {
                // 划词收藏
                ToolbarButton(
                    title: "收藏",
                    systemImage: "bookmark",
                    tooltip: "收藏选中的文字",
                    isDisabled: model.selectedText.isEmpty
                ) {
                    let phrase = model.selectedText.isEmpty ? model.sourceText : model.selectedText
                    onCollect(phrase, model.sourceText)
                }

                // 收藏整句
                ToolbarButton(
                    title: "收藏整句",
                    systemImage: "text.badge.star",
                    tooltip: "收藏整句原文",
                ) {
                    let text = model.sourceText.isEmpty ? model.translatedText : model.sourceText
                    onCollect(text, text)
                }
            }

            // 生词本按钮
            ToolbarIconButton(
                systemImage: "books.vertical",
                tooltip: "生词本"
            ) {
                onOpenWordBook()
            }

            // 复制按钮（带成功微动效）
            ToolbarIconButton(
                systemImage: justCopied ? "checkmark" : "doc.on.doc",
                tooltip: "复制译文或原文",
                iconColor: justCopied ? .green : nil,
                isDisabled: model.translatedText.isEmpty && model.sourceText.isEmpty
            ) {
                let copiedTranslation = !model.translatedText.isEmpty
                let text = copiedTranslation ? model.translatedText : model.sourceText
                NSPasteboard.writeString(text)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) {
                    justCopied = true
                }
                showNotice(copiedTranslation ? "已复制译文" : "已复制原文")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                        justCopied = false
                    }
                }
            }

            // 置顶窗口按钮
            ToolbarIconButton(
                systemImage: settings.alwaysOnTop ? "pin.fill" : "pin",
                tooltip: settings.alwaysOnTop ? "取消置顶" : "置顶窗口",
                isActive: settings.alwaysOnTop
            ) {
                onTogglePin()
            }

            // 重试按钮（带平滑回旋动效）
            ToolbarIconButton(
                systemImage: "arrow.clockwise",
                tooltip: "重新识别与翻译",
                rotationAngle: retryAngle,
                isDisabled: model.image == nil && model.sourceText.isEmpty
            ) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) {
                    retryAngle += 360
                }
                onRetry()
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
    }

    /// 精美现代胶囊 Tab 切换栏：各 Tab 独立专属悬浮提示与高质感滑动胶囊
    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(ResultModel.Tab.allCases) { tab in
                let isSelected = model.tab == tab
                let isEnabled = (model.phase == .done || model.phase == .idle)
                let isHovered = hoveredTab == tab

                Button {
                    guard isEnabled else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        model.tab = tab
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: 10.5, weight: isSelected ? .semibold : .regular))
                        Text(tab.rawValue)
                            .font(.system(size: 11.5, weight: isSelected ? .medium : .regular))
                    }
                    .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary : Color.secondary))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background {
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color(nsColor: .controlBackgroundColor))
                                    .shadow(color: Color.black.opacity(0.12), radius: 2, x: 0, y: 1)
                                    .matchedGeometryEffect(id: "activeTabBackground", in: tabAnimation)
                            } else if isHovered && isEnabled {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.primary.opacity(0.05))
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1.0 : 0.45)
                .onHover { inside in
                    if isEnabled {
                        hoveredTab = inside ? tab : nil
                    }
                }
                .hoverFeedback(tab.tooltip)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlColor).opacity(0.55))
        )
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .recognizing:
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.regular)
                Text("正在精确识别文字…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

        case .failed(let message):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("重试") {
                    onRetry()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

        default:
            switch model.tab {
            case .translation:
                // 翻译页签：输入/翻译中/完成共用同一个 HSplitView（见 translationContent），
                // phase 变化不重建分栏，分隔线位置保持稳定
                translationContent
            default:
                if model.phase == .idle {
                    emptyState
                } else if model.phase == .translating {
                    translatingStatus
                } else {
                    doneContent
                }
            }
        }
    }

    /// 空闲态（非翻译页签）：欢迎语 + 识别历史
    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.18), Color.accentColor.opacity(0.04)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                    Image(systemName: "character.bubble")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }

                HStack(spacing: 6) {
                    Text("按下")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    KbdShortcutView(keys: settings.hotkeyCapture.display)

                    Text("截屏翻译")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 16)

            if !model.history.isEmpty {
                historySection
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 翻译中（非翻译页签）：原文 + 底部进度行
    private var translatingStatus: some View {
        VStack(spacing: 0) {
            SelectableTextView(
                text: model.sourceText,
                paragraphSpacing: 4,
                lineSpacing: 2
            )
            Divider()
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("翻译中…（\(model.targetLanguage.displayName)）")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        }
    }

    /// 翻译页签内容：左栏原文（可编辑，实时翻译）+ 右栏译文。
    private var translationContent: some View {
        HSplitView {
            // 左栏：原文编辑
            VStack(alignment: .leading, spacing: 0) {
                speechToolbar(
                    text: model.sourceText,
                    language: model.sourceLanguage,
                    selection: model.leftSelectedText
                )
                Divider()
                EditableTextView(
                    text: $model.sourceText,
                    paragraphSpacing: 4,
                    lineSpacing: 2,
                    onChange: { onLiveTranslate($0) },
                    onSelectionChange: { model.leftSelectedText = $0 },
                    focusOnAppear: model.phase == .idle
                )
            }
            .frame(minWidth: 160)

            // 右栏：译文
            VStack(alignment: .leading, spacing: 0) {
                speechToolbar(
                    text: model.translatedText,
                    language: model.targetLanguage,
                    selection: model.selectedText
                )
                Divider()
                ZStack {
                    let isWorking = model.isLiveTranslating || model.phase == .translating
                    if model.translatedText.isEmpty {
                        if isWorking {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在翻译…（\(model.targetLanguage.displayName)）")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        } else {
                            VStack(spacing: 8) {
                                Image(systemName: "arrow.left.circle")
                                    .font(.system(size: 24))
                                    .foregroundStyle(.tertiary)
                                Text("在左侧输入或粘贴内容，自动实时翻译")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        SelectableTextView(
                            text: model.translatedText,
                            onSelectionChange: { model.selectedText = $0 },
                            onCollect: onCollect,
                            paragraphSpacing: 4,
                            lineSpacing: 2
                        )
                        .opacity(isWorking ? 0.55 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: isWorking)
                    }

                    // 修改已有文本时，右上角浮现小巧的“更新翻译中…”指示胶囊
                    if isWorking && !model.translatedText.isEmpty {
                        VStack {
                            HStack {
                                Spacer()
                                HStack(spacing: 5) {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("更新翻译中…")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3.5)
                                .background(
                                    Capsule()
                                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.94))
                                        .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                                        .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.5))
                                )
                                .padding(8)
                            }
                            Spacer()
                        }
                        .transition(.opacity)
                    }
                }
            }
            .frame(minWidth: 160)
        }
    }

    // MARK: - 识别历史

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("识别历史")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("最多保留 \(settings.historyLimit) 条")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(model.history.prefix(settings.historyLimit)) { entry in
                        HistoryRowButton(entry: entry) {
                            model.image = entry.image
                            model.sourceText = entry.sourceText
                            model.translatedText = entry.translatedText
                            model.sourceLanguage = entry.sourceLanguage
                            model.targetLanguage = entry.targetLanguage
                            model.providerName = entry.providerName
                            model.ocrLines = []
                            model.phase = .done
                            model.tab = .sideBySide
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
            }
            .frame(maxHeight: 180)
        }
    }

    // MARK: - 完成态内容

    @ViewBuilder
    private var doneContent: some View {
        switch model.tab {
        case .recognize:
            HSplitView {
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                VStack(alignment: .leading, spacing: 0) {
                    speechToolbar(
                        text: model.sourceText,
                        language: model.sourceLanguage,
                        selection: model.selectedText
                    )
                    Divider()
                    if !model.sourceText.isEmpty {
                        SelectableTextView(
                            text: model.sourceText,
                            onSelectionChange: { model.selectedText = $0 },
                            onCollect: onCollect,
                            paragraphSpacing: 4,
                            lineSpacing: 2
                        )
                    } else {
                        Text("未识别到文字")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minWidth: 160)
            }

        case .translation:
            translationContent

        case .sideBySide:
            HSplitView {
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                VStack(alignment: .leading, spacing: 0) {
                    speechToolbar(
                        text: model.translatedText,
                        language: model.targetLanguage,
                        selection: model.selectedText
                    )
                    Divider()
                    SelectableTextView(
                        text: model.translatedText,
                        onSelectionChange: { model.selectedText = $0 },
                        onCollect: onCollect,
                        paragraphSpacing: 4,
                        lineSpacing: 2
                    )
                }
                .frame(minWidth: 160)
            }

        case .oneToOne:
            HSplitView {
                if let image = model.image {
                    zoomableImagePane(image: image, syncGroupID: "oneToOneSync")
                }
                if let image = model.image, !model.translatedText.isEmpty {
                    oneToOneView(image: image, translation: model.translatedText, ocrLines: model.ocrLines, syncGroupID: "oneToOneSync")
                } else if let image = model.image {
                    InteractiveImageView(
                        image: image,
                        scale: $imageScale,
                        fitsToViewport: true,
                        syncGroupID: "oneToOneSync"
                    )
                    .frame(minWidth: 160)
                }
            }
        }
    }

    // MARK: - 朗读控制条

    /// 朗读控制条：朗读/暂停/继续/停止/静音 + 律动反馈
    private func speechToolbar(text: String, language: Language?, selection: String) -> some View {
        let isSpeakingActive = speech.isSpeaking && !speech.isPausedState

        return HStack(spacing: 6) {
            // 朗读按钮
            SpeechBarButton(
                systemImage: "speaker.wave.2",
                tooltip: selection.isEmpty ? "朗读全文" : "朗读选中部分",
                isActive: isSpeakingActive,
                isDisabled: text.isEmpty
            ) {
                let speakText = selection.isEmpty ? text : selection
                speech.speak(speakText, language: language)
            }

            // 暂停/继续
            SpeechBarButton(
                systemImage: speech.isPausedState ? "play.fill" : "pause.fill",
                tooltip: speech.isPausedState ? "继续朗读" : "暂停朗读",
                isDisabled: !speech.isSpeaking
            ) {
                speech.togglePause()
            }

            // 停止
            SpeechBarButton(
                systemImage: "stop.fill",
                tooltip: "停止朗读",
                isDisabled: !speech.isSpeaking
            ) {
                speech.stop()
            }

            // 静音
            SpeechBarButton(
                systemImage: speech.isMutedState ? "speaker.slash.fill" : "speaker.fill",
                tooltip: speech.isMutedState ? "取消静音" : "静音",
                isActive: speech.isMutedState
            ) {
                speech.toggleMute()
            }

            Spacer()

            if !selection.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "selection.pin.in.out")
                        .font(.system(size: 9))
                    Text("选中: \(selection.prefix(12))…")
                        .font(.system(size: 10))
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
        }
        .frame(height: 24)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    // MARK: - 图片视图

    @State private var imageScale: CGFloat = 1.0

    @ViewBuilder
    private func zoomableImagePane(image: NSImage, syncGroupID: String? = nil) -> some View {
        InteractiveImageView(image: image, scale: $imageScale, fitsToViewport: true, syncGroupID: syncGroupID)
            .overlay(alignment: .bottomTrailing) {
                zoomControlBar
            }
            .frame(minWidth: 160)
    }

    @ViewBuilder
    private func oneToOneView(
        image: NSImage,
        translation: String,
        ocrLines: [(text: String, rect: CGRect)],
        syncGroupID: String? = nil
    ) -> some View {
        if let coveredImage = Self.renderPositionedCoverImage(
            image: image,
            translation: translation,
            ocrLines: ocrLines
        ) {
            InteractiveImageView(
                image: coveredImage,
                scale: $imageScale,
                fitsToViewport: true,
                syncGroupID: syncGroupID
            )
            .frame(minWidth: 160)
        } else {
            InteractiveImageView(
                image: image,
                scale: $imageScale,
                fitsToViewport: true,
                syncGroupID: syncGroupID
            )
            .frame(minWidth: 160)
        }
    }

    /// 缩放控制按钮组
    private var zoomControlBar: some View {
        HStack(spacing: 4) {
            ZoomBarButton(systemImage: "minus.magnifyingglass", tooltip: "缩小") {
                withAnimation(.easeOut(duration: 0.15)) {
                    imageScale = max(0.2, imageScale / 1.25)
                }
            }

            ZoomBarButton(systemImage: "plus.magnifyingglass", tooltip: "放大") {
                withAnimation(.easeOut(duration: 0.15)) {
                    imageScale = max(0.2, imageScale * 1.25)
                }
            }

            ZoomBarButton(systemImage: "arrow.counterclockwise", tooltip: "重置缩放") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    imageScale = 1.0
                }
            }
        }
        .padding(4)
        .background(Color.black.opacity(0.65))
        .clipShape(Capsule())
        .padding(8)
    }

    // MARK: - 图片渲染

    /// 对 OCR 识别行按视觉层级与行高突变切分成独立的段落块（如大标题 vs 小正文，避免混淆字号）
    private struct OcrVisualSection {
        let lines: [(text: String, rect: CGRect)]
        let unionRect: CGRect
        let avgLineHeight: CGFloat
        let isProminent: Bool
    }

    private static func clusterOcrSections(_ sortedLines: [(text: String, rect: CGRect)]) -> [OcrVisualSection] {
        guard !sortedLines.isEmpty else { return [] }
        let overallAvgH = sortedLines.map(\.rect.height).reduce(0, +) / CGFloat(sortedLines.count)

        var groups: [[(text: String, rect: CGRect)]] = []
        for line in sortedLines {
            if let lastGroup = groups.last, let lastLine = lastGroup.last {
                let h1 = lastLine.rect.height
                let h2 = line.rect.height
                let heightDiff = abs(h1 - h2) / max(h1, h2)
                let vGap = lastLine.rect.minY - (line.rect.origin.y + line.rect.height)
                let avgH = (h1 + h2) / 2

                // 行高差异在 16% 以内，且垂直紧凑，视为同一折行正文块；若行高突变（如标题 vs 说明），则拆分为独立块
                if heightDiff <= 0.16 && vGap >= -0.005 && vGap < avgH * 1.35 {
                    groups[groups.count - 1].append(line)
                    continue
                }
            }
            groups.append([line])
        }

        return groups.map { lines in
            let union = lines.reduce(lines[0].rect) { $0.union($1.rect) }
            let secAvgH = lines.map(\.rect.height).reduce(0, +) / CGFloat(lines.count)
            return OcrVisualSection(
                lines: lines,
                unionRect: union,
                avgLineHeight: secAvgH,
                isProminent: secAvgH > overallAvgH * 1.15
            )
        }
    }

    /// 从原图采样指定区域周边的背景颜色
    private static func sampleBackgroundColor(from image: NSImage, pixelRect: CGRect) -> NSColor {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let cgImage = rep.cgImage else {
            return NSColor(calibratedWhite: 0.98, alpha: 1.0)
        }
        let w = cgImage.width
        let h = cgImage.height
        guard w > 0, h > 0 else { return NSColor.windowBackgroundColor }

        let cgY = max(0, min(h - 1, Int(CGFloat(h) - pixelRect.maxY)))
        let cgX = max(0, min(w - 1, Int(pixelRect.origin.x)))

        let samplePoints = [
            (max(0, cgX - 3), max(0, cgY - 2)),
            (min(w - 1, cgX + Int(pixelRect.width) + 2), max(0, cgY - 2)),
            (max(0, cgX - 2), min(h - 1, cgY + 2)),
        ]

        guard let dataProvider = cgImage.dataProvider,
              let data = dataProvider.data,
              let ptr = CFDataGetBytePtr(data) else {
            return NSColor(calibratedWhite: 0.98, alpha: 1.0)
        }

        let bytesPerPixel = max(4, cgImage.bitsPerPixel / 8)
        let bytesPerRow = cgImage.bytesPerRow

        for (sx, sy) in samplePoints {
            let offset = sy * bytesPerRow + sx * bytesPerPixel
            if offset + 3 < CFDataGetLength(data) {
                let r = CGFloat(ptr[offset]) / 255.0
                let g = CGFloat(ptr[offset + 1]) / 255.0
                let b = CGFloat(ptr[offset + 2]) / 255.0
                return NSColor(calibratedRed: r, green: g, blue: b, alpha: 1.0)
            }
        }
        return NSColor(calibratedWhite: 0.98, alpha: 1.0)
    }

    /// 渲染译文覆盖图：按原图物理行高与字号对齐覆盖，支持标题与正文字号分级自适应，杜绝重叠与裁切
    private static func renderPositionedCoverImage(
        image: NSImage,
        translation: String,
        ocrLines: [(text: String, rect: CGRect)]
    ) -> NSImage? {
        guard !translation.isEmpty, !ocrLines.isEmpty else { return nil }

        let transLines = translation
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !transLines.isEmpty else { return nil }

        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return nil }

        let canvas = NSImage(size: image.size)
        canvas.lockFocus()

        // 绘制原图作为底图背景
        image.draw(in: NSRect(x: 0, y: 0, width: imgW, height: imgH))

        // Vision 归一化坐标从上到下排序
        let sortedOcrLines = ocrLines.sorted { $0.rect.midY > $1.rect.midY }
        let overallAvgH = sortedOcrLines.map(\.rect.height).reduce(0, +) / CGFloat(sortedOcrLines.count)

        if transLines.count == sortedOcrLines.count {
            // 场景 ①：行级 1 对 1 精准对齐（每行字号、粗细完全跟随原图对应行）
            for i in 0..<sortedOcrLines.count {
                let ocrLine = sortedOcrLines[i]
                let text = transLines[i]
                let isProminent = ocrLine.rect.height > overallAvgH * 1.15
                renderSingleLineCover(
                    text: text,
                    ocrBox: ocrLine.rect,
                    imgW: imgW,
                    imgH: imgH,
                    image: image,
                    isProminent: isProminent
                )
            }
        } else {
            // 场景 ②：译文行数不一致时按视觉层级/段落独立排版（各段落独立保持自身行高字号，标题大字加粗，正文小字细腻）
            let sections = clusterOcrSections(sortedOcrLines)
            let sectionTexts = mapTranslationToSections(transLines: transLines, sectionCount: sections.count)

            for i in 0..<sections.count {
                let section = sections[i]
                let text = sectionTexts[i]
                guard !text.isEmpty else { continue }
                renderSectionCover(
                    text: text,
                    section: section,
                    imgW: imgW,
                    imgH: imgH,
                    image: image
                )
            }
        }

        canvas.unlockFocus()
        return canvas
    }

    /// 映射翻译文本到各个视觉段落
    private static func mapTranslationToSections(transLines: [String], sectionCount: Int) -> [String] {
        guard sectionCount > 0 else { return [] }
        if sectionCount == 1 {
            return [transLines.joined(separator: "\n")]
        }
        if sectionCount == transLines.count {
            return transLines
        }
        if transLines.count < sectionCount {
            var res: [String] = []
            for i in 0..<sectionCount {
                res.append(i < transLines.count ? transLines[i] : "")
            }
            return res
        } else {
            var res: [String] = []
            for i in 0..<(sectionCount - 1) {
                res.append(transLines[i])
            }
            res.append(transLines[(sectionCount - 1)...].joined(separator: "\n"))
            return res
        }
    }

    /// 单行精准覆盖绘制
    private static func renderSingleLineCover(
        text: String,
        ocrBox: CGRect,
        imgW: CGFloat,
        imgH: CGFloat,
        image: NSImage,
        isProminent: Bool
    ) {
        let pixelX = ocrBox.origin.x * imgW
        let pixelY = ocrBox.origin.y * imgH
        let pixelW = ocrBox.size.width * imgW
        let pixelH = ocrBox.size.height * imgH
        guard pixelW > 4, pixelH > 2 else { return }

        let sampledBg = sampleBackgroundColor(from: image, pixelRect: CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH))
        let brightness = (sampledBg.redComponent * 0.299 + sampledBg.greenComponent * 0.587 + sampledBg.blueComponent * 0.114)
        let textColor = brightness > 0.55 ? NSColor.black.withAlphaComponent(0.88) : NSColor.white

        var fontSize = max(10.0, pixelH * (isProminent ? 0.78 : 0.72))
        let fontWeight: NSFont.Weight = isProminent ? .semibold : .medium
        let minFontSize = max(9.0, fontSize * 0.65)

        let maxDrawW = max(pixelW + 12, min(imgW - pixelX - 4, pixelW * 1.35))
        var font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        var measured = (text as NSString).size(withAttributes: [.font: font])

        while measured.width > maxDrawW && fontSize > minFontSize {
            fontSize -= 0.5
            font = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
            measured = (text as NSString).size(withAttributes: [.font: font])
        }

        let padH: CGFloat = 2.5
        let padW: CGFloat = 4.0
        let actualDrawW = max(pixelW, measured.width) + padW * 2
        let actualCoverW = min(imgW - max(0, pixelX - padW), actualDrawW)

        let coverRect = CGRect(
            x: max(0, pixelX - padW),
            y: max(0, pixelY - padH),
            width: actualCoverW,
            height: pixelH + padH * 2
        )

        sampledBg.setFill()
        NSBezierPath(roundedRect: coverRect, xRadius: 2.5, yRadius: 2.5).fill()

        let textDrawY = coverRect.midY - (measured.height / 2)
        let textRect = CGRect(
            x: coverRect.origin.x + padW,
            y: textDrawY,
            width: actualCoverW - padW * 2,
            height: measured.height
        )

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    /// 段落级覆盖绘制
    private static func renderSectionCover(
        text: String,
        section: OcrVisualSection,
        imgW: CGFloat,
        imgH: CGFloat,
        image: NSImage
    ) {
        let pixelX = section.unionRect.origin.x * imgW
        let pixelY = section.unionRect.origin.y * imgH
        let pixelW = section.unionRect.size.width * imgW
        let pixelH = section.unionRect.size.height * imgH
        guard pixelW > 4, pixelH > 2 else { return }

        let sampledBg = sampleBackgroundColor(from: image, pixelRect: CGRect(x: pixelX, y: pixelY, width: pixelW, height: pixelH))
        let brightness = (sampledBg.redComponent * 0.299 + sampledBg.greenComponent * 0.587 + sampledBg.blueComponent * 0.114)
        let textColor = brightness > 0.55 ? NSColor.black.withAlphaComponent(0.88) : NSColor.white

        let baseLineH = section.avgLineHeight * imgH
        var fontSize = max(10.0, baseLineH * (section.isProminent ? 0.78 : 0.72))
        let fontWeight: NSFont.Weight = section.isProminent ? .semibold : .medium
        let minFontSize = max(9.0, fontSize * 0.65)

        let paraStyle = NSMutableParagraphStyle()
        paraStyle.lineBreakMode = .byWordWrapping
        paraStyle.lineSpacing = max(2.0, baseLineH * 0.12)

        let availWidth = max(pixelW + 8, min(imgW - pixelX - 4, pixelW * 1.3))
        var fittedHeight = pixelH
        var fittedFont = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)

        while fontSize >= minFontSize {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: fittedFont,
                .paragraphStyle: paraStyle
            ]
            let measured = (text as NSString).boundingRect(
                with: CGSize(width: availWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: attrs
            )
            fittedHeight = measured.height
            if fittedHeight <= pixelH + 8 || fontSize <= minFontSize {
                break
            }
            fontSize -= 0.5
            fittedFont = NSFont.systemFont(ofSize: fontSize, weight: fontWeight)
        }

        let paddingH: CGFloat = 3.0
        let paddingW: CGFloat = 4.0
        let blockTopY = min(imgH, pixelY + pixelH)
        let totalNeededHeight = max(pixelH, fittedHeight) + paddingH * 2

        let coverMaxY = min(imgH, blockTopY + paddingH)
        let coverMinY = max(0, coverMaxY - totalNeededHeight)
        let coverX = max(0, pixelX - paddingW)
        let coverW = min(imgW - coverX, availWidth + paddingW * 2)

        let coverRect = CGRect(x: coverX, y: coverMinY, width: coverW, height: coverMaxY - coverMinY)

        sampledBg.setFill()
        NSBezierPath(roundedRect: coverRect, xRadius: 3.0, yRadius: 3.0).fill()

        let textDrawY = max(coverRect.origin.y + paddingH, coverMaxY - paddingH - fittedHeight)
        let textDrawRect = CGRect(
            x: coverRect.origin.x + paddingW,
            y: textDrawY,
            width: max(8, coverRect.width - paddingW * 2),
            height: fittedHeight
        )

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: fittedFont,
            .foregroundColor: textColor,
            .paragraphStyle: paraStyle
        ]
        (text as NSString).draw(in: textDrawRect, withAttributes: textAttrs)
    }

    // MARK: - 状态栏

    private func showNotice(_ text: String) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
            model.collectNotice = text
        }
        Task { [weak model] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if model?.collectNotice == text {
                withAnimation(.easeOut(duration: 0.2)) {
                    model?.collectNotice = ""
                }
            }
        }
    }

    private var showLanguageBar: Bool {
        model.phase == .done || (model.phase == .idle && model.tab == .translation)
    }

    private var switchableEngines: [PrimaryEngine] {
        PrimaryEngine.allCases.filter { engine in
            switch engine {
            case .openai: return !settings.openaiAPIKey.isEmpty
            case .deepl: return !settings.deeplAPIKey.isEmpty
            default: return true
            }
        }
    }

    private var engineDisplayName: String {
        if let override = model.engineOverride {
            return override.shortName
        }
        return model.providerName.isEmpty ? settings.primaryEngine.shortName : model.providerName
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if showLanguageBar {
                // 统一语向控制胶囊（源语言 + 交换 + 目标语言）
                languagePairControl

                // 翻译引擎选择胶囊
                engineControl

                // 清空按钮
                ClearActionButton(isDisabled: !model.hasContent) {
                    onClear?()
                }
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 10))
                        .foregroundStyle(Color.accentColor)
                    Text("SnapTranslator")
                        .font(.system(size: 11, weight: .medium))
                }
            }

            Spacer()

            if !model.collectNotice.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.green)
                    Text(model.collectNotice)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.green.opacity(0.12))
                        .overlay(Capsule().stroke(Color.green.opacity(0.3), lineWidth: 0.5))
                )
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.9).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.95))
    }

    /// 语向联动控制胶囊：源语言 + 翻转交换 + 目标语言
    private var languagePairControl: some View {
        HStack(spacing: 0) {
            // 源语言 Menu
            Menu {
                Button("自动检测") {
                    model.sourceLanguage = nil
                    onSourceLanguageChange?(nil)
                }
                Divider()
                ForEach(Language.allCases) { lang in
                    Button(lang.displayName) {
                        model.sourceLanguage = lang
                        onSourceLanguageChange?(lang)
                    }
                }
            } label: {
                HStack(spacing: 3.5) {
                    Text(model.sourceLanguage?.displayName ?? "自动")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(model.sourceLanguage == nil ? Color.secondary : Color.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.65))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverFeedback("选择源语言")

            // 交换按钮（180度回旋微动效）
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                    swapAngle += 180
                }
                onSwapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(Color.secondary)
                    .rotationEffect(.degrees(swapAngle))
                    .frame(width: 22, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverFeedback("交换源语言/目标语言")

            // 目标语言 Menu
            Menu {
                ForEach(Language.allCases) { lang in
                    Button(lang.displayName) {
                        model.targetLanguage = lang
                        onTargetLanguageChange?(lang)
                    }
                }
            } label: {
                HStack(spacing: 3.5) {
                    Text(model.targetLanguage.displayName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.primary)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.65))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverFeedback("选择目标语言")
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: Color.black.opacity(0.06), radius: 1.5, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
        )
    }

    /// 翻译引擎选择胶囊
    private var engineControl: some View {
        Menu {
            Button {
                model.engineOverride = nil
            } label: {
                Text(model.engineOverride == nil ? "✓ 跟随主引擎设置" : "跟随主引擎设置")
            }
            Divider()
            ForEach(switchableEngines) { engine in
                Button {
                    model.engineOverride = engine
                } label: {
                    Text(model.engineOverride == engine ? "✓ \(engine.displayName)" : engine.displayName)
                }
            }
        } label: {
            HStack(spacing: 4) {
                if model.isLiveTranslating || model.phase == .translating {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.65)
                        .frame(width: 8, height: 8)
                } else {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 5, height: 5)
                }
                Text(engineDisplayName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.65))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .shadow(color: Color.black.opacity(0.06), radius: 1.5, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverFeedback("切换翻译引擎")
    }
}

// MARK: - 辅助微交互组件

/// 清空按钮微交互
private struct ClearActionButton: View {
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 10))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.35) : (isHovered ? Color.red : Color.secondary))
                .frame(width: 22, height: 21)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered && !isDisabled ? Color.red.opacity(0.12) : Color.primary.opacity(0.04))
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .hoverFeedback("清空内容")
    }
}

/// 工具栏图标按钮（带悬停胶囊背景与弹性缩放反馈）
private struct ToolbarIconButton: View {
    let systemImage: String
    let tooltip: String
    var iconColor: Color? = nil
    var rotationAngle: Double = 0
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconColor ?? (isActive ? Color.accentColor : Color.primary))
                .rotationEffect(.degrees(rotationAngle))
                .frame(width: 26, height: 26)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                    } else if isHovered && !isDisabled {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    }
                }
                .scaleEffect(isPressed ? 0.92 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1.0)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .hoverFeedback(tooltip)
    }
}

/// 工具栏文字/图标按钮
private struct ToolbarButton: View {
    let title: String
    let systemImage: String
    let tooltip: String
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(isDisabled ? Color.secondary.opacity(0.4) : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered && !isDisabled ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04))
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .hoverFeedback(tooltip)
    }
}

/// 朗读控制小按钮
private struct SpeechBarButton: View {
    let systemImage: String
    let tooltip: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11))
                .foregroundStyle(isActive ? Color.accentColor : (isDisabled ? Color.secondary.opacity(0.4) : Color.primary))
                .frame(width: 18, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isHovered && !isDisabled ? Color.primary.opacity(0.1) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .hoverFeedback(tooltip)
    }
}

/// 缩放控制浮动小按钮
private struct ZoomBarButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Color.white)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(isHovered ? Color.white.opacity(0.25) : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .hoverFeedback(tooltip)
    }
}

/// 键盘快捷键按键外观（Kbd Badge）
private struct KbdShortcutView: View {
    let keys: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(keys), id: \.self) { char in
                Text(String(char))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.12), radius: 1, x: 0, y: 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                            )
                    )
            }
        }
    }
}

/// 识别历史卡片行（带平滑悬停与阴影抬升）
private struct HistoryRowButton: View {
    let entry: ResultModel.HistoryEntry
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(nsImage: entry.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 56, height: 38)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.sourceText.prefix(45))
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(.primary)

                    HStack(spacing: 6) {
                        Text(entry.timestamp, style: .relative)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        if let src = entry.sourceLanguage {
                            Text("·")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                            Text("\(src.displayName) → \(entry.targetLanguage.displayName)")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(isHovered ? 1.0 : 0.0)
            }
            .padding(7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isHovered ? Color(nsColor: .controlBackgroundColor) : Color.gray.opacity(0.08))
                    .shadow(color: isHovered ? Color.black.opacity(0.08) : Color.clear, radius: 4, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .hoverFeedback("恢复该条记录")
    }
}
