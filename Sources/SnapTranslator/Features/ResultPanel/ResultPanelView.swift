import AppKit
import SwiftUI

/// 结果面板主视图：工具条 + 内容区（原图/译文/并排 + 各阶段状态）
struct ResultPanelView: View {
    @ObservedObject var model: ResultModel
    @ObservedObject var anchor: TranslationAnchor
    @ObservedObject var settings: SettingsStore

    let onCollect: (String, String) -> Void
    let onRetry: () -> Void
    let onClose: () -> Void
    let onTogglePin: () -> Void
    let onSwapLanguages: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
            statusBar
        }
        .frame(minWidth: 380, minHeight: 260)
        // Apple 翻译锚点：隐藏在面板窗口中驱动 TranslationSession
        .background {
            if #available(macOS 15.0, *) {
                TranslationAnchorView(anchor: anchor)
                    .frame(width: 0, height: 0)
            }
        }
    }

    // MARK: - 工具条

    private var toolbar: some View {
        HStack(spacing: 8) {
            Picker("视图", selection: $model.tab) {
                ForEach(ResultModel.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
            .disabled(model.phase != .done)

            Spacer(minLength: 8)

            if model.phase == .done {
                Button {
                    let phrase = model.selectedText.isEmpty ? model.sourceText : model.selectedText
                    onCollect(phrase, model.sourceText)
                } label: {
                    Label("收藏", systemImage: "bookmark")
                }
                .help("收藏选中内容；未选中时收藏整段原文")

                Button {
                    let text = model.sourceText.isEmpty ? model.translatedText : model.sourceText
                    onCollect(text, text)
                } label: {
                    Label("收藏整句", systemImage: "text.badge.star")
                }
                .help("收藏整句到生词本")
            }

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

    @ViewBuilder
    private var doneContent: some View {
        switch model.tab {
        case .originalImage:
            if let image = model.image {
                ScrollView([.vertical, .horizontal]) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                }
            }

        case .translation:
            SelectableTextView(
                text: model.translatedText,
                onSelectionChange: { model.selectedText = $0 },
                onCollect: onCollect
            )

        case .sideBySide:
            HSplitView {
                // 左栏：截图原图
                if let image = model.image {
                    imagePane(image: image)
                }
                // 右栏：译文以图片形式渲染（保留原文版式观感）
                translatedImagePane(
                    text: model.translatedText,
                    referenceImage: model.image
                )
            }
        }
    }

    // MARK: - 图片视图

    /// 原图浏览窗格
    @ViewBuilder
    private func imagePane(image: NSImage) -> some View {
        ScrollView([.vertical, .horizontal]) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .padding(8)
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
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }
}
