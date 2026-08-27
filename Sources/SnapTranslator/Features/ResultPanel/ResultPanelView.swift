import AppKit
import SwiftUI

/// 结果面板主视图：工具条 + 内容区（识别结果/翻译/对照/1:1 + 各阶段状态）
struct ResultPanelView: View {
    @ObservedObject var model: ResultModel
    @ObservedObject var settings: SettingsStore

    let onCollect: (String, String) -> Void
    let onRetry: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onSwapLanguages: () -> Void
    let onOpenWordBook: () -> Void

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
            .frame(width: 280)
            .disabled(model.phase != .done)
            .labelsHidden()

            Spacer(minLength: 8)

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
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
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
                SelectableTextView(text: model.sourceText)
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
            // 识别结果：左侧大图 + 右侧原文/失败信息
            HSplitView {
                // 左栏：截图原图（自动适配宽度，支持缩放）
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                // 右栏：原文/识别结果
                VStack(alignment: .leading, spacing: 8) {
                    if !model.sourceText.isEmpty {
                        SelectableTextView(
                            text: model.sourceText,
                            onSelectionChange: { model.selectedText = $0 },
                            onCollect: onCollect
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
            // 翻译：左侧原文 + 右侧译文（支持划词选中）
            HSplitView {
                SelectableTextView(text: model.sourceText)
                    .frame(minWidth: 160)
                SelectableTextView(
                    text: model.translatedText,
                    onSelectionChange: { model.selectedText = $0 },
                    onCollect: onCollect
                )
                .frame(minWidth: 160)
            }

        case .sideBySide:
            HSplitView {
                // 左栏：截图原图
                if let image = model.image {
                    zoomableImagePane(image: image)
                }
                // 右栏：译文以图片形式渲染（保留原文版式观感）
                translatedImagePane(
                    text: model.translatedText,
                    referenceImage: model.image
                )
            }

        case .oneToOne:
            // 1:1 模式：翻译结果以图片形式覆盖/替换源语言
            if let image = model.image, !model.translatedText.isEmpty {
                oneToOneView(image: image, translation: model.translatedText)
            } else if let image = model.image {
                zoomableImagePane(image: image)
            }
        }
    }

    // MARK: - 图片视图

    /// 可缩放图片视图：默认自适应宽度，滚轮缩放，双击恢复
    @State private var imageScale: CGFloat = 1.0

    @ViewBuilder
    private func zoomableImagePane(image: NSImage) -> some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(imageScale)
                    .frame(width: max(1, geo.size.width * imageScale))
                    .padding(8)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                imageScale = max(0.2, min(5.0, imageScale * value))
                            }
                    )
                    .onTapGesture(count: 2) {
                        imageScale = 1.0
                    }
            }
            .overlay(alignment: .bottomTrailing) {
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
        }
        .frame(minWidth: 160)
    }

    /// 译文图片窗格：按参考图尺寸把译文排版为图片，与左栏原图等比对照
    @ViewBuilder
    private func translatedImagePane(text: String, referenceImage: NSImage?) -> some View {
        ScrollView([.vertical, .horizontal]) {
            if let image = Self.renderTextAsImage(text: text, reference: referenceImage) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .padding(8)
            } else {
                SelectableTextView(text: text)
                    .frame(minWidth: 160, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 160)
    }

    /// 1:1 模式：翻译结果以图片形式覆盖在原文上方（等尺寸替换）
    @ViewBuilder
    private func oneToOneView(image: NSImage, translation: String) -> some View {
        GeometryReader { geo in
            ScrollView([.vertical, .horizontal]) {
                ZStack {
                    // 背景原图（半透明叠加参考）
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .opacity(0.15)

                    // 前景译文图片（等尺寸覆盖）
                    if let translatedImage = Self.renderTextAsImage(
                        text: translation,
                        reference: image
                    ) {
                        Image(nsImage: translatedImage)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                    }
                }
                .padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Text("1:1 译文覆盖源图")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Capsule())
                    .padding(8)
            }
        }
        .frame(minWidth: 160)
    }

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

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack(spacing: 8) {
            if model.phase == .done {
                Text("\(model.sourceLanguage?.displayName ?? "自动") → \(model.targetLanguage.displayName) · \(model.providerName)")
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
