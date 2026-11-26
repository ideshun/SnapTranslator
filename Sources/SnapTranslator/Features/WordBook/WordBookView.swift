import AppKit
import SnapTranslatorCore
import SwiftUI
import UniformTypeIdentifiers

/// 现代 Master-Detail 生词本窗口：卡片词条列表 + 持久化译文 + 可交互标签胶囊 + CSV / Anki TSV / JSON 导入导出
struct WordBookView: View {
    @ObservedObject var store: WordBookStore
    var onTranslate: (String, Language?, Language?) async -> String = { _, _, _ in "" }

    @State private var searchText = ""
    @State private var selectedLanguageFilter: String = "all"
    @State private var selectedWordID: Word.ID?
    @State private var isTranslating = false
    @State private var noteDraft = ""
    @State private var newTagInput = ""
    @State private var exportNotice = ""

    private var availableLanguages: [String] {
        Set(store.words.map(\.sourceLanguage)).filter { !$0.isEmpty }.sorted()
    }

    private var filtered: [Word] {
        store.words.filter { word in
            if selectedLanguageFilter != "all" && word.sourceLanguage != selectedLanguageFilter {
                return false
            }
            guard !searchText.isEmpty else { return true }
            return word.phrase.localizedCaseInsensitiveContains(searchText)
                || word.translation.localizedCaseInsensitiveContains(searchText)
                || word.context.localizedCaseInsensitiveContains(searchText)
                || word.note.localizedCaseInsensitiveContains(searchText)
                || word.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var selectedWord: Word? {
        guard let selectedWordID else { return filtered.first }
        return filtered.first { $0.id == selectedWordID } ?? filtered.first
    }

    var body: some View {
        HSplitView {
            // 左侧词条卡片列表
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField("搜索词条、译文、备注或标签…", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(STTheme.panelSurface))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(STTheme.hairlineBorder, lineWidth: 0.6))

                    HStack(spacing: 6) {
                        if availableLanguages.count > 1 {
                            Picker("", selection: $selectedLanguageFilter) {
                                Text("全部语种").tag("all")
                                ForEach(availableLanguages, id: \.self) { code in
                                    Text(languageName(code)).tag(code)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 96)
                        }

                        Text("共 \(filtered.count) 条")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Menu {
                            Button("导出 CSV（Excel）") { exportCSV() }
                            Button("导出 Anki TSV（制卡）") { exportAnkiTSV() }
                            Button("导出 JSON 备份") { exportJSON() }
                            Divider()
                            Button("从 JSON 导入合并…") { importJSON() }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "square.and.arrow.up")
                                Text("导入/导出")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(RoundedRectangle(cornerRadius: 6).fill(STTheme.subtleFill))
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .hoverFeedback("导出为 CSV / Anki TSV / JSON，或导入备份")
                    }
                }
                .padding(12)
                .background(STTheme.windowCanvas)

                Divider()

                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(store.words.isEmpty ? "还没有收藏生词" : "未找到匹配生词")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered) { word in
                                WordListCard(
                                    word: word,
                                    isSelected: selectedWord?.id == word.id,
                                    onSelect: { selectedWordID = word.id },
                                    onDelete: {
                                        if selectedWordID == word.id { selectedWordID = nil }
                                        store.delete(word)
                                    }
                                )
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .frame(minWidth: 300, maxWidth: 380)
            .background(STTheme.windowCanvas)

            // 右侧词条详情画布
            VStack(alignment: .leading, spacing: 0) {
                if let word = selectedWord {
                    // 顶部词条栏
                    HStack(alignment: .center, spacing: 10) {
                        Text(word.phrase)
                            .font(.system(size: 20, weight: .bold))
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                        ToolbarIconButton(systemImage: "speaker.wave.2", tooltip: "朗读词条") {
                            SpeechManager.shared.speak(word.phrase, language: Language(rawValue: word.sourceLanguage))
                        }
                        ToolbarIconButton(systemImage: "doc.on.doc", tooltip: "复制词条") {
                            NSPasteboard.writeString(word.phrase)
                            showNotice("已复制词条")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(STTheme.windowCanvas)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // 译文卡片
                            STCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("释义 / 译文", systemImage: "character.bubble")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                        Spacer()
                                        if isTranslating {
                                            ProgressView().controlSize(.small)
                                        } else {
                                            Button {
                                                performTranslation(word)
                                            } label: {
                                                Label(word.translation.isEmpty ? "立即翻译" : "重新翻译", systemImage: "sparkles")
                                                    .font(.system(size: 11.5, weight: .medium))
                                            }
                                            .buttonStyle(.borderless)
                                            .foregroundStyle(Color.accentColor)
                                        }
                                        if !word.translation.isEmpty {
                                            SpeechBarButton(systemImage: "speaker.wave.2", tooltip: "朗读译文") {
                                                SpeechManager.shared.speak(word.translation, language: Language(rawValue: word.targetLanguage))
                                            }
                                        }
                                    }
                                    if word.translation.isEmpty {
                                        Text("暂无保存的译文，点击右上角「立即翻译」获取并持久化存储")
                                            .font(.system(size: 12))
                                            .foregroundStyle(.tertiary)
                                    } else {
                                        Text(word.translation)
                                            .font(.system(size: 14))
                                            .lineSpacing(4)
                                            .textSelection(.enabled)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }

                            // 上下文原句卡片
                            STCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("上下文原句", systemImage: "quote.opening")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        SpeechBarButton(systemImage: "speaker.wave.2", tooltip: "朗读上下文") {
                                            SpeechManager.shared.speak(word.context, language: Language(rawValue: word.sourceLanguage))
                                        }
                                        SpeechBarButton(systemImage: "doc.on.doc", tooltip: "复制上下文") {
                                            NSPasteboard.writeString(word.context)
                                            showNotice("已复制上下文")
                                        }
                                    }
                                    Text(word.context)
                                        .font(.system(size: 13.5))
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            // 备注与交互式标签卡片
                            STCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    Label("笔记与标签", systemImage: "tag")
                                        .font(.system(size: 11.5, weight: .semibold))
                                        .foregroundStyle(.secondary)

                                    HStack(spacing: 8) {
                                        TextField("添加记忆线索或例句备注…", text: $noteDraft)
                                            .textFieldStyle(.roundedBorder)
                                            .onSubmit { saveNote(for: word) }
                                        Button("保存备注") { saveNote(for: word) }
                                            .controlSize(.small)
                                    }

                                    // 已有标签胶囊
                                    if !word.tags.isEmpty {
                                        HStack(spacing: 6) {
                                            ForEach(word.tags, id: \.self) { tag in
                                                STTagChip(text: tag) {
                                                    removeTag(tag, from: word)
                                                }
                                            }
                                            Spacer()
                                        }
                                    }

                                    HStack(spacing: 8) {
                                        TextField("输入新标签后按回车添加（如：论文 / 工作）", text: $newTagInput)
                                            .textFieldStyle(.roundedBorder)
                                            .onSubmit { addTag(to: word) }
                                        Button("添加标签") { addTag(to: word) }
                                            .controlSize(.small)
                                            .disabled(newTagInput.trimmingCharacters(in: .whitespaces).isEmpty)
                                    }
                                }
                            }

                            // 底部元信息与删除
                            HStack(spacing: 14) {
                                Text("\(languageName(word.sourceLanguage)) → \(languageName(word.targetLanguage))")
                                    .font(.system(size: 11, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(STTheme.subtleFill))
                                Text("收藏于 \(word.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button(role: .destructive) {
                                    store.delete(word)
                                    selectedWordID = nil
                                    showNotice("已删除「\(String(word.phrase.prefix(10)))」")
                                } label: {
                                    Label("删除生词", systemImage: "trash")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.top, 2)
                        }
                        .padding(18)
                    }
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "text.book.closed")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("在左侧选择一条生词查看详情、译文与标签")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 380)
            .background(STTheme.windowCanvas)
        }
        .frame(minWidth: 760, minHeight: 500)
        .overlay(alignment: .bottom) {
            if !exportNotice.isEmpty {
                Text(exportNotice)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(STTheme.strongBorder, lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                    .padding(.bottom, 16)
            }
        }
        .onChange(of: selectedWord?.id) { _, _ in
            noteDraft = selectedWord?.note ?? ""
            newTagInput = ""
        }
        .onAppear {
            noteDraft = selectedWord?.note ?? ""
        }
    }

    private func saveNote(for word: Word) {
        store.update(wordID: word.id, note: noteDraft)
        showNotice("已保存备注")
    }

    private func addTag(to word: Word) {
        let candidate = newTagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return }
        var tags = word.tags
        if !tags.contains(candidate) {
            tags.append(candidate)
            store.update(wordID: word.id, tags: tags)
        }
        newTagInput = ""
    }

    private func removeTag(_ tag: String, from word: Word) {
        let tags = word.tags.filter { $0 != tag }
        store.update(wordID: word.id, tags: tags)
    }

    private func languageName(_ code: String) -> String {
        if code == "auto" { return "自动" }
        return Language(rawValue: code)?.displayName ?? code
    }

    private func performTranslation(_ word: Word) {
        let src = Language(rawValue: word.sourceLanguage)
        let tgt = Language(rawValue: word.targetLanguage)
        Task {
            isTranslating = true
            let result = await onTranslate(word.phrase, src, tgt)
            if !result.isEmpty && !result.hasPrefix("翻译失败：") {
                store.update(wordID: word.id, translation: result)
                showNotice("已翻译并保存")
            } else if !result.isEmpty {
                showNotice(result)
            }
            isTranslating = false
        }
    }

    private func showNotice(_ text: String) {
        exportNotice = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if exportNotice == text { exportNotice = "" }
        }
    }

    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "SnapTranslator-生词本.csv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(WordBookExporter.csv(for: store.words).utf8).write(to: url, options: .atomic)
                showNotice("已导出 \(store.words.count) 条生词（CSV）")
            } catch { NSAlert(error: error).runModal() }
        }
    }

    private func exportAnkiTSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.tabSeparatedText, .plainText]
        panel.nameFieldStringValue = "SnapTranslator-Anki.tsv"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(WordBookExporter.ankiTSV(for: store.words).utf8).write(to: url, options: .atomic)
                showNotice("已导出 \(store.words.count) 条 Anki 卡片")
            } catch { NSAlert(error: error).runModal() }
        }
    }

    private func exportJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SnapTranslator-生词本备份.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try WordBookExporter.jsonData(for: store.words)
                try data.write(to: url, options: .atomic)
                showNotice("已备份 \(store.words.count) 条生词（JSON）")
            } catch { NSAlert(error: error).runModal() }
        }
    }

    private func importJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let count = try store.importJSON(data)
                showNotice("导入完成，新增 \(count) 条生词")
            } catch { NSAlert(error: error).runModal() }
        }
    }
}

private struct WordListCard: View {
    let word: Word
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3.5) {
                    Text(word.phrase)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if !word.translation.isEmpty {
                        Text(word.translation)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !word.context.isEmpty && word.context != word.phrase {
                        Text(word.context)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 5) {
                        Text(word.createdAt, style: .date)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                        ForEach(word.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor.opacity(0.11)))
                        }
                    }
                }
                Spacer(minLength: 4)
                if hovered {
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .hoverFeedback("删除生词")
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : (hovered ? STTheme.cardHoverSurface : STTheme.cardSurface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.45) : STTheme.hairlineBorder, lineWidth: isSelected ? 1 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
