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

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            statusBar
        }
        .frame(minWidth: 380, minHeight: 260)
        .onChange(of: model.phase) { _, _ in
            // 新截图/新翻译开始时重置缩放
            imageScale = 1.0
        }
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $model.tab) {
                ForEach(ResultModel.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 240)
            .disabled(!(model.phase == .done || model.phase == .idle))
            .labelsHidden()

            Spacer()

            if model.phase == .done {
                // 翻译结果支持划词选中
                Button {
                    let phrase = model.selectedText.isEmpty ? model.sourceText : model.selectedText
                    onCollect(phrase, model.sourceText)
                } label: {
                    Label("收藏", systemImage: "bookmark")
                }
                .help("收藏选中的文字到生词本；需先在翻译结果中划词选中")
                .disabled(model.selectedText.isEmpty)

                Button {
                    let text = model.sourceText.isEmpty ? model.translatedText : model.sourceText
                    onCollect(text, text)
                } label: {
                    Label("收藏整句", systemImage: "text.badge.star")
                }
                .help("收藏整句原文到生词本")
            }

            // 生词本按钮：始终可见，方便随时查看收藏
            Button(action: onOpenWordBook) {
                Image(systemName: "books.vertical")
            }
            .help("打开生词本")

            Button {
                let text = model.translatedText.isEmpty ? model.sourceText : model.translatedText
                NSPasteboard.writeString(text)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("复制译文")

            Button(action: onTogglePin) {
                Image(systemName: settings.alwaysOnTop ? "pin.fill" : "pin")
            }
            .help(settings.alwaysOnTop ? "取消置顶" : "置顶窗口")

            if model.phase == .done {
                Button(action: onSwapLanguages) {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("交换源语言/目标语言并重新翻译")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .help("关闭（窗口）")
        }
        // tab 区域左边缘不留额外间距，紧凑对齐
        .padding(.leading, 0)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        // 空闲态也展示「翻译」页签，支持输入内容实时翻译
        if model.phase == .idle && model.tab == .translation {
            idleTranslationContent
        } else {
            switch model.phase {
            case .idle:
                VStack(spacing: 10) {
                    Image(systemName: "character.bubble")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("按下 \(settings.hotkeyCapture.display) 截屏翻译")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    if !model.history.isEmpty {
                        historySection
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .recognizing:
                ProgressView("识别文字中…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .translating:
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
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                }

            case .done:
                doneContent

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    Text(message)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                    Button("重试") {
                        onRetry()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// 空闲态的翻译页签内容：左侧可编辑原文，右侧实时译文
    private var idleTranslationContent: some View {
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
                    onSelectionChange: { model.leftSelectedText = $0 }
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
                if model.translatedText.isEmpty {
                    Text("输入内容后自动翻译")
                        .font(.system(size: 13))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    SelectableTextView(
                        text: model.translatedText,
                        onSelectionChange: { model.selectedText = $0 },
                        onCollect: onCollect,
                        paragraphSpacing: 4,
                        lineSpacing: 2
                    )
                }
            }
            .frame(minWidth: 160)
        }
    }

    // MARK: - 识别历史

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("识别历史")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(model.history.prefix(settings.historyLimit)) { entry in
                        Button {
                            model.image = entry.image
                            model.sourceText = entry.sourceText
                            model.translatedText = entry.translatedText
                            model.sourceLanguage = entry.sourceLanguage
                            model.targetLanguage = entry.targetLanguage
                            model.providerName = entry.providerName
                            model.ocrLines = []
                            model.phase = .done
                            model.tab = .sideBySide
                        } label: {
                            HStack(spacing: 8) {
                                Image(nsImage: entry.image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 60, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.sourceText.prefix(40))
                                        .font(.system(size: 11))
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                    Text(entry.timestamp, style: .relative)
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(6)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 200)
        }
        .padding(.horizontal, 20)
    }

    // MARK: - 完成态内容

    @ViewBuilder
    private var doneContent: some View {
        switch model.tab {
        case .recognize:
            // 识别：左侧大图 + 右侧原文
            HSplitView {
                // 左栏：截图原图（自动适配宽度，支持缩放）
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                // 右栏：原文/识别结果（带分段效果）
                VStack(alignment: .leading, spacing: 0) {
                    // 阅读控制条：右上角
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
            // 翻译：左侧原文支持编辑（实时翻译）+ 右侧译文（行距与左侧识别区一致）
            HSplitView {
                // 左栏：原文
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
                        onSelectionChange: { model.leftSelectedText = $0 }
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

        case .sideBySide:
            HSplitView {
                // 左栏：截图原图
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                // 右栏：译文以文本形式展示
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
            // 1:1 模式：左右对照，左边截图，右边翻译覆盖结果
            HSplitView {
                // 左栏：截图原图
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                // 右栏：翻译覆盖结果（仅左栏有缩放控制）
                if let image = model.image, !model.translatedText.isEmpty {
                    oneToOneView(image: image, translation: model.translatedText, ocrLines: model.ocrLines)
                } else if let image = model.image {
                    InteractiveImageView(image: image, scale: $imageScale)
                        .frame(minWidth: 160)
                }
            }
        }
    }

    // MARK: - 朗读控制条

    /// 每个面板右上角的朗读控制条：朗读/暂停/继续/停止/静音
    /// - Parameters:
    ///   - text: 面板全文内容
    ///   - language: 朗读语言
    ///   - selection: 面板自身的选中文本（朗读时优先朗读选中内容）
    private func speechToolbar(text: String, language: Language?, selection: String) -> some View {
        HStack(spacing: 8) {
            // 朗读按钮：有选中文本时朗读选中部分（使用本面板的选中内容）
            Button {
                let speakText = selection.isEmpty ? text : selection
                speech.speak(speakText, language: language)
            } label: {
                Image(systemName: "speaker.wave.2")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .help(selection.isEmpty ? "朗读全文" : "朗读选中部分")
            .disabled(text.isEmpty)

            // 暂停/继续
            Button {
                speech.togglePause()
            } label: {
                Image(systemName: speech.isPausedState ? "play.fill" : "pause.fill")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .help(speech.isPausedState ? "继续朗读" : "暂停朗读")
            .disabled(!speech.isSpeaking)

            // 停止
            Button {
                speech.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .help("停止朗读")
            .disabled(!speech.isSpeaking)

            // 静音（图标固定尺寸，避免切换时高度抖动）
            Button {
                speech.toggleMute()
            } label: {
                Image(systemName: speech.isMutedState ? "speaker.slash.fill" : "speaker.fill")
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            .help(speech.isMutedState ? "取消静音" : "静音")

            Spacer()

            if !selection.isEmpty {
                Text("已选中: \(selection.prefix(12))…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .font(.system(size: 11))
        .frame(height: 24)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.gray.opacity(0.08))
    }

    // MARK: - 图片视图

    /// 可缩放图片视图：默认自适应宽度，滚轮缩放，双击恢复
    @State private var imageScale: CGFloat = 1.0

    @ViewBuilder
    private func zoomableImagePane(image: NSImage) -> some View {
        InteractiveImageView(image: image, scale: $imageScale)
            .overlay(alignment: .bottomTrailing) {
                zoomControlBar
            }
            .frame(minWidth: 160)
    }

    /// 译文图片窗格：按 OCR 位置把译文排版为图片，与左栏原图对应
    @ViewBuilder
    private func positionedTranslatedImagePane(
        text: String,
        referenceImage: NSImage?,
        ocrLines: [(text: String, rect: CGRect)]
    ) -> some View {
        ScrollView([.vertical, .horizontal]) {
            if let referenceImage,
               let image = Self.renderPositionedTextImage(
                   text: text,
                   reference: referenceImage,
                   ocrLines: ocrLines
               ) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(8)
            } else if let image = Self.renderTextAsImage(text: text, reference: referenceImage) {
                // 无 OCR 位置信息时的兜底：普通排版渲染
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(8)
            } else {
                SelectableTextView(
                    text: text,
                    paragraphSpacing: 4,
                    lineSpacing: 2
                )
                .frame(minWidth: 160, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 160)
    }

    /// 1:1 模式：翻译结果以图片形式覆盖原图，按 OCR 位置对应
    /// 无独立缩放按钮，统一用左侧区域的缩放控制
    @ViewBuilder
    private func oneToOneView(
        image: NSImage,
        translation: String,
        ocrLines: [(text: String, rect: CGRect)]
    ) -> some View {
        if let coveredImage = Self.renderPositionedCoverImage(
            image: image,
            translation: translation,
            ocrLines: ocrLines
        ) {
            InteractiveImageView(image: coveredImage, scale: $imageScale)
                .frame(minWidth: 160)
        } else {
            // 无 OCR 位置信息时兜底：直接显示原图
            InteractiveImageView(image: image, scale: $imageScale)
                .frame(minWidth: 160)
        }
    }

    /// 缩放控制按钮组（仅显示在左侧图片区域）
    private var zoomControlBar: some View {
        HStack(spacing: 6) {
            Button {
                imageScale = max(0.2, imageScale / 1.25)
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("缩小")

            Button {
                imageScale = max(0.2, imageScale * 1.25)
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("放大")

            Button {
                imageScale = 1.0
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("重置缩放")
        }
        .padding(6)
        .background(Color.black.opacity(0.5))
        .clipShape(Capsule())
        .padding(8)
    }

    // MARK: - 图片渲染

    /// 把译文文本渲染为 NSImage（透明底，白字，行距按文本分行）
    private static func renderTextAsImage(text: String, reference: NSImage?) -> NSImage? {
        guard !text.isEmpty else { return nil }
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]

        // 参考图尺寸（若可用），否则按行数估算
        let width: CGFloat = reference.map { $0.size.width } ?? max(320, lines.map {
            (($0 as NSString).size(withAttributes: attributes).width)
        }.max() ?? 320)
        let lineHeight = font.pointSize * 1.5
        let height = max(120, CGFloat(lines.count) * lineHeight + 24)

        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        var y = height - 18
        for line in lines {
            (line as NSString).draw(
                at: NSPoint(x: 14, y: y),
                withAttributes: attributes
            )
            y -= lineHeight
        }
        image.unlockFocus()
        return image
    }

    /// 渲染译文覆盖图：在原图上绘制译文，每行译文覆盖在对应 OCR 行位置
    /// 与 renderPositionedTextImage 的区别：背景使用原图（不透明），译文覆盖在文字上
    /// 按换行后实际高度动态调整字号与覆盖区，确保译文完整显示不被裁切
    /// 字号比默认大，提升 1:1 翻译区的可读性
    private static func renderPositionedCoverImage(
        image: NSImage,
        translation: String,
        ocrLines: [(text: String, rect: CGRect)]
    ) -> NSImage? {
        guard !translation.isEmpty, !ocrLines.isEmpty else { return nil }

        let translatedLines = translation.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !translatedLines.isEmpty else { return nil }

        // 将 OCR 行按从上到下排序（Vision 归一化坐标：y 轴从底部向上）
        let sortedLines = ocrLines.sorted { $0.rect.midY > $1.rect.midY }

        let imgW = image.size.width
        let imgH = image.size.height
        guard imgW > 0, imgH > 0 else { return nil }

        // 创建与参考图同尺寸的画布
        let canvas = NSImage(size: image.size)
        canvas.lockFocus()

        // 先绘制原图作为背景
        image.draw(in: NSRect(x: 0, y: 0, width: imgW, height: imgH))

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byWordWrapping

        // 译文行数可能多于 OCR 行：多余行在最后一行下方按序排列
        let count = translatedLines.count
        for i in 0..<count {
            let translatedLine = translatedLines[i]
            guard !translatedLine.isEmpty else { continue }

            // 确定该译文行对应的 OCR 区域（超出部分使用最后一行，向下排列）
            let box: CGRect
            if i < sortedLines.count {
                box = sortedLines[i].rect
            } else {
                let lastBox = sortedLines[sortedLines.count - 1].rect
                let overflowIndex = i - sortedLines.count + 1
                box = CGRect(
                    x: lastBox.origin.x,
                    y: max(0, lastBox.origin.y - lastBox.size.height * CGFloat(overflowIndex)),
                    width: lastBox.size.width,
                    height: lastBox.size.height
                )
            }

            // Vision 归一化坐标（原点左下）→ 像素坐标（AppKit 同样原点左下）
            let rect = CGRect(
                x: box.origin.x * imgW,
                y: box.origin.y * imgH,
                width: box.size.width * imgW,
                height: box.size.height * imgH
            )
            guard rect.width > 8, rect.height > 2 else { continue }

            // 可用绘制宽度（内缩避免贴边）
            let availWidth = max(rect.width - 4, 8)
            // 垂直可用空间：OCR 行高的数倍，给译文换行留足空间，避免裁切
            let maxTextHeight = max(rect.height * 3, 36)

            // 根据换行后实际高度动态调整字号，确保完整显示
            // 起始字号加大到 17，提升可读性
            var fontSize: CGFloat = 17
            let minFontSize: CGFloat = 10
            var fittedFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            var fittedHeight = rect.height

            while fontSize > minFontSize {
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: fittedFont,
                    .paragraphStyle: paragraphStyle,
                ]
                let constrained = CGSize(width: availWidth, height: .greatestFiniteMagnitude)
                let measured = (translatedLine as NSString).boundingRect(
                    with: constrained,
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs
                )
                if measured.height <= maxTextHeight {
                    fittedHeight = measured.height
                    break
                }
                fontSize -= 0.5
                fittedFont = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            }

            // 覆盖区向上扩展以容纳换行后的完整译文（clamp 到画布内避免越界裁切）
            let coverHeight = max(rect.height + 6, fittedHeight + 6)
            let coverRect = CGRect(
                x: max(0, rect.origin.x - 3),
                y: max(0, rect.origin.y - 3),
                width: min(imgW, rect.width + 6),
                height: min(imgH, coverHeight)
            )
            NSColor.windowBackgroundColor.setFill()
            NSBezierPath(rect: coverRect).fill()

            // 译文绘制区：从覆盖区顶部向下对齐，确保多行完整显示
            let drawHeight = max(fittedHeight, rect.height - 4)
            let drawTop = coverRect.maxY
            let drawRect = CGRect(
                x: max(0, rect.origin.x + 2),
                y: max(0, drawTop - drawHeight),
                width: availWidth,
                height: min(drawHeight, imgH)
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: fittedFont,
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: paragraphStyle,
            ]
            (translatedLine as NSString).draw(
                in: drawRect,
                withAttributes: attrs
            )
        }

        canvas.unlockFocus()
        return canvas
    }

    /// 按 OCR boundingBox 位置渲染译文图片：译文每行放置在对应的原文字位置
    /// - 参考图尺寸创建画布，每行译文绘制在原图对应 OCR 行的 boundingBox 区域内
    private static func renderPositionedTextImage(
        text: String,
        reference: NSImage,
        ocrLines: [(text: String, rect: CGRect)]
    ) -> NSImage? {
        guard !text.isEmpty, !ocrLines.isEmpty else { return nil }

        let translatedLines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard !translatedLines.isEmpty else { return nil }

        // 将 OCR 行按从上到下排序（Vision 归一化坐标：y 轴从底部向上）
        let sortedLines = ocrLines.sorted { $0.rect.midY > $1.rect.midY }

        let imgW = reference.size.width
        let imgH = reference.size.height
        guard imgW > 0, imgH > 0 else { return nil }

        // 创建与参考图同尺寸的画布
        let canvas = NSImage(size: reference.size)
        canvas.lockFocus()
        NSColor.clear.set()
        NSRect(x: 0, y: 0, width: imgW, height: imgH).fill()

        let font = NSFont.systemFont(ofSize: 14, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]

        // 逐个绘制：译文行对应 OCR 行的位置
        let count = min(translatedLines.count, sortedLines.count)
        for i in 0..<count {
            let translatedLine = translatedLines[i]
            let box = sortedLines[i].rect

            // Vision 归一化坐标（原点左下）→ 像素坐标（AppKit 同样原点左下）
            let rect = CGRect(
                x: box.origin.x * imgW,
                y: box.origin.y * imgH,
                width: box.size.width * imgW,
                height: box.size.height * imgH
            )

            // 在对应位置绘制译文
            let drawRect = rect.insetBy(dx: 2, dy: 2)
            (translatedLine as NSString).draw(
                in: drawRect,
                withAttributes: attributes
            )
        }

        canvas.unlockFocus()
        return canvas
    }

    // MARK: - 状态栏

    /// 是否在左下角展示源/目标语言选择：翻译相关场景（翻译页签空闲输入或已完成）
    private var showLanguageBar: Bool {
        model.phase == .done || (model.phase == .idle && model.tab == .translation)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if showLanguageBar {
                // 左下角源语言/目标语言：点击弹出选择菜单（切换语种，而非朗读）
                Menu {
                    // 源语言选择
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
                    Text(model.sourceLanguage?.displayName ?? "自动")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("选择源语言")

                Text("→").foregroundStyle(.tertiary)

                // 目标语言选择
                Menu {
                    ForEach(Language.allCases) { lang in
                        Button(lang.displayName) {
                            model.targetLanguage = lang
                            onTargetLanguageChange?(lang)
                        }
                    }
                } label: {
                    Text(model.targetLanguage.displayName)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help("选择目标语言")

                if !model.providerName.isEmpty {
                    Text("· \(model.providerName)").foregroundStyle(.secondary)
                }
            } else {
                Text("SnapTranslator")
            }
            Spacer()
            if !model.collectNotice.isEmpty {
                Text(model.collectNotice)
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
