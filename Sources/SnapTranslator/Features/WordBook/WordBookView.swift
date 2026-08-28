import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 生词本窗口：搜索、详情、删除、CSV 导出
/// 支持词条翻译与语音朗读
struct WordBookView: View {
    @ObservedObject var store: WordBookStore
    /// 翻译回调：传入文本返回翻译结果
    var onTranslate: (String) async -> String = { _ in "" }

    @State private var searchText = ""
    @State private var selectedWordID: Word.ID?
    /// 当前选中词的翻译结果
    @State private var translationResult = ""
    @State private var isTranslating = false

    private var filtered: [Word] {
        guard !searchText.isEmpty else { return store.words }
        return store.words.filter {
            $0.phrase.localizedCaseInsensitiveContains(searchText)
                || $0.context.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedWord: Word? {
        guard let selectedWordID else { return nil }
        return filtered.first { $0.id == selectedWordID }
    }

    var body: some View {
        HSplitView {
            // 左侧列表
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    TextField("搜索", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 240)
                    Spacer()
                    Text("\(store.words.count) 个词")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Button {
                        exportCSV()
                    } label: {
                        Label("导出 CSV", systemImage: "square.and.arrow.up")
                    }
                    .disabled(store.words.isEmpty)
                }
                .padding(12)

                Divider()

                Table(filtered, selection: $selectedWordID) {
                    TableColumn("词") { word in
                        Text(word.phrase)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("上下文") { word in
                        Text(word.context)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    TableColumn("时间") { word in
                        Text(word.createdAt, style: .date)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .width(90)

                    TableColumn("") { word in
                        Button {
                            store.delete(word)
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .help("删除")
                    }
                    .width(36)
                }
                .tableStyle(.inset)
            }
            .frame(minWidth: 280)

            // 右侧详情面板
            VStack(alignment: .leading, spacing: 12) {
                if let word = selectedWord {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            // 词条 + 朗读按钮
                            HStack(alignment: .center) {
                                Text(word.phrase)
                                    .font(.system(size: 18, weight: .semibold))
                                    .textSelection(.enabled)
                                Spacer()
                                Button {
                                    let lang = Language(rawValue: word.sourceLanguage)
                                    SpeechManager.shared.speak(word.phrase, language: lang)
                                } label: {
                                    Image(systemName: "speaker.wave.2")
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.borderless)
                                .help("朗读词条")
                            }

                            Divider()

                            // 上下文 + 朗读按钮
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("上下文")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button {
                                        let lang = Language(rawValue: word.sourceLanguage)
                                        SpeechManager.shared.speak(word.context, language: lang)
                                    } label: {
                                        Image(systemName: "speaker.wave.2")
                                            .font(.system(size: 12))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("朗读上下文")
                                }
                                Text(word.context)
                                    .font(.system(size: 13))
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            // 翻译区域
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("翻译")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    if isTranslating {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Button {
                                            performTranslation(word)
                                        } label: {
                                            Image(systemName: "character.bubble")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.borderless)
                                        .help("翻译词条")
                                    }
                                    // 朗读翻译结果
                                    if !translationResult.isEmpty {
                                        Button {
                                            let lang = Language(rawValue: word.targetLanguage)
                                            SpeechManager.shared.speak(translationResult, language: lang)
                                        } label: {
                                            Image(systemName: "speaker.wave.2")
                                                .font(.system(size: 12))
                                        }
                                        .buttonStyle(.borderless)
                                        .help("朗读译文")
                                    }
                                }
                                if translationResult.isEmpty {
                                    Text("点击翻译按钮翻译词条")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.tertiary)
                                } else {
                                    Text(translationResult)
                                        .font(.system(size: 13))
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Divider()

                            HStack(spacing: 16) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("源语言")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(languageName(word.sourceLanguage))
                                        .font(.system(size: 12))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("目标语言")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(languageName(word.targetLanguage))
                                        .font(.system(size: 12))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("收藏时间")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    Text(word.createdAt, style: .date)
                                        .font(.system(size: 12))
                                }
                            }

                            Divider()

                            HStack {
                                Button {
                                    NSPasteboard.writeString(word.context)
                                } label: {
                                    Label("复制上下文", systemImage: "doc.on.doc")
                                }
                                .buttonStyle(.borderless)

                                Button {
                                    store.delete(word)
                                    selectedWordID = nil
                                    translationResult = ""
                                } label: {
                                    Label("删除", systemImage: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(20)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text("在左侧选择一条记录查看详情")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 220)
        }
        .frame(minWidth: 700, minHeight: 420)
        .onChange(of: selectedWordID) { _, _ in
            // 切换词条时清空翻译结果
            translationResult = ""
        }
    }

    private func languageName(_ code: String) -> String {
        Language(rawValue: code)?.displayName ?? code
    }

    /// 翻译选中词条
    private func performTranslation(_ word: Word) {
        Task {
            isTranslating = true
            let result = await onTranslate(word.phrase)
            translationResult = result
            isTranslating = false
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SnapTranslator-生词本.csv"
        panel.begin { [store] response in
            guard response == .OK, let url = panel.url else { return }
            let csv = WordBookExporter.csv(for: store.words)
            do {
                try Data(csv.utf8).write(to: url)
            } catch {
                let alert = NSAlert(error: error)
                alert.runModal()
            }
        }
    }
}
