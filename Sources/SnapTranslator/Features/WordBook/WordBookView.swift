import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 生词本窗口：搜索、删除、CSV 导出
struct WordBookView: View {
    @ObservedObject var store: WordBookStore
    @State private var searchText = ""

    private var filtered: [Word] {
        guard !searchText.isEmpty else { return store.words }
        return store.words.filter {
            $0.phrase.localizedCaseInsensitiveContains(searchText)
                || $0.context.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
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

            Table(filtered) {
                TableColumn("词") { word in
                    Text(word.phrase)
                        .font(.system(size: 13, weight: .medium))
                }
                .width(min: 100, ideal: 140)

                TableColumn("上下文") { word in
                    Text(word.context)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
        .frame(minWidth: 560, minHeight: 380)
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
