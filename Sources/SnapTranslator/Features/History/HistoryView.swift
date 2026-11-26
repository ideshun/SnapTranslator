import AppKit
import SnapTranslatorCore
import SwiftUI

/// 现代 Master-Detail 识别历史窗口：卡片列表 + 搜索筛选 + 星标 + 一键回看 1:1 译文图
struct HistoryView: View {
    @ObservedObject var store: HistoryStore
    let onRestore: (HistoryRecord) -> Void

    @State private var searchText = ""
    @State private var starredOnly = false
    @State private var selectedID: UUID?
    @State private var notice = ""

    private var filtered: [HistoryRecord] {
        store.records.filter { record in
            if starredOnly && !record.isStarred { return false }
            guard !searchText.isEmpty else { return true }
            return record.sourceText.localizedCaseInsensitiveContains(searchText)
                || record.translatedText.localizedCaseInsensitiveContains(searchText)
                || record.providerName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var selectedRecord: HistoryRecord? {
        guard let selectedID else { return filtered.first }
        return filtered.first(where: { $0.id == selectedID }) ?? filtered.first
    }

    var body: some View {
        HSplitView {
            // 左侧列表侧边栏
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        TextField("搜索原文、译文或引擎…", text: $searchText)
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
                        filterPill(title: "全部 (\(store.records.count))", active: !starredOnly) {
                            starredOnly = false
                        }
                        filterPill(title: "星标 (\(store.records.filter(\.isStarred).count))", icon: "star.fill", active: starredOnly) {
                            starredOnly = true
                        }
                        Spacer()
                        Menu {
                            Button("清空非星标记录") {
                                store.clearAll(keepStarred: true)
                                showNotice("已清空非星标历史")
                            }
                            Button("清空全部记录", role: .destructive) {
                                store.clearAll(keepStarred: false)
                                selectedID = nil
                                showNotice("已清空全部历史")
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .disabled(store.records.isEmpty)
                        .hoverFeedback("清理历史记录")
                    }
                }
                .padding(12)
                .background(STTheme.windowCanvas)

                Divider()

                if filtered.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: starredOnly ? "star.slash" : "clock.arrow.circlepath")
                            .font(.system(size: 30, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text(store.records.isEmpty ? "暂无识别历史" : "未找到匹配记录")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(filtered) { record in
                                HistoryListCard(
                                    record: record,
                                    thumbnail: store.image(for: record),
                                    isSelected: selectedRecord?.id == record.id,
                                    onSelect: { selectedID = record.id },
                                    onToggleStar: { store.toggleStar(record.id) }
                                )
                            }
                        }
                        .padding(10)
                    }
                }
            }
            .frame(minWidth: 310, maxWidth: 380)
            .background(STTheme.windowCanvas)

            // 右侧详情区
            VStack(alignment: .leading, spacing: 0) {
                if let record = selectedRecord {
                    HStack(spacing: 8) {
                        let srcName = record.sourceLanguage?.displayName ?? "自动"
                        HStack(spacing: 5) {
                            Text(srcName)
                            Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                            Text(record.targetLanguage.displayName)
                        }
                        .font(.system(size: 11.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        .foregroundStyle(Color.accentColor)

                        Text(record.providerName)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            store.toggleStar(record.id)
                        } label: {
                            Image(systemName: record.isStarred ? "star.fill" : "star")
                                .foregroundStyle(record.isStarred ? .yellow : .secondary)
                        }
                        .buttonStyle(.borderless)
                        .hoverFeedback(record.isStarred ? "取消星标" : "加星标")

                        Button {
                            onRestore(record)
                        } label: {
                            Label("在主面板打开", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(STTheme.windowCanvas)

                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if let image = store.image(for: record) {
                                STCard(padding: 8) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: .infinity, maxHeight: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                            }

                            STCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("原文", systemImage: "doc.plaintext")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("复制") {
                                            NSPasteboard.writeString(record.sourceText)
                                            showNotice("已复制原文")
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11.5))
                                    }
                                    Text(record.sourceText)
                                        .font(.system(size: 13.5))
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            STCard {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Label("译文", systemImage: "character.bubble")
                                            .font(.system(size: 11.5, weight: .semibold))
                                            .foregroundStyle(Color.accentColor)
                                        Spacer()
                                        Button("复制") {
                                            NSPasteboard.writeString(record.translatedText)
                                            showNotice("已复制译文")
                                        }
                                        .buttonStyle(.borderless)
                                        .font(.system(size: 11.5))
                                    }
                                    Text(record.translatedText)
                                        .font(.system(size: 13.5))
                                        .lineSpacing(4)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            HStack {
                                Text("记录时间：\(record.timestamp.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.tertiary)
                                Spacer()
                                Button(role: .destructive) {
                                    store.delete(record.id)
                                    selectedID = nil
                                    showNotice("已删除记录")
                                } label: {
                                    Label("删除此条", systemImage: "trash")
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
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 34, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("选择一条历史记录查看详情或回看 1:1 译文")
                            .font(.system(size: 12.5))
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
            if !notice.isEmpty {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(STTheme.strongBorder, lineWidth: 0.6))
                    .shadow(color: .black.opacity(0.16), radius: 8, y: 3)
                    .padding(.bottom, 16)
            }
        }
    }

    private func filterPill(title: String, icon: String? = nil, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 9.5))
                        .foregroundStyle(active ? .yellow : .secondary)
                }
                Text(title).font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(active ? Color.accentColor.opacity(0.16) : STTheme.subtleFill))
        }
        .buttonStyle(.plain)
    }

    private func showNotice(_ text: String) {
        notice = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if notice == text { notice = "" }
        }
    }
}

private struct HistoryListCard: View {
    let record: HistoryRecord
    let thumbnail: NSImage?
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleStar: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 48, height: 36)
                        .overlay(Image(systemName: "doc.text").font(.system(size: 13)).foregroundStyle(Color.accentColor))
                }

                VStack(alignment: .leading, spacing: 2.5) {
                    Text(record.sourceText.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(record.translatedText.replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(record.timestamp, style: .relative)
                        Text("·")
                        Text(record.providerName)
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 4)

                Button(action: onToggleStar) {
                    Image(systemName: record.isStarred ? "star.fill" : "star")
                        .font(.system(size: 11))
                        .foregroundStyle(record.isStarred ? .yellow : (hovered ? .secondary : .clear))
                }
                .buttonStyle(.borderless)
            }
            .padding(9)
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
