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

            if model.phase == .done, !model.selectedText.isEmpty {
                Button {
                    onCollect(model.selectedText, model.sourceText)
                } label: {
                    Label("收藏选中", systemImage: "bookmark")
                }
                .help("收藏选中内容到生词本")
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
                SelectableTextView(
                    text: model.sourceText,
                    onSelectionChange: { model.selectedText = $0 },
                    onCollect: onCollect
                )
                .frame(minWidth: 160)
                SelectableTextView(
                    text: model.translatedText,
                    onSelectionChange: { model.selectedText = $0 },
                    onCollect: onCollect
                )
                .frame(minWidth: 160)
            }
        }
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
