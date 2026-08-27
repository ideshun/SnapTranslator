import AppKit
import SwiftUI

/// 可选中文本视图：右键菜单一键收藏，选区变化回调
struct SelectableTextView: NSViewRepresentable {
    let text: String
    var onSelectionChange: ((String) -> Void)?
    var onCollect: ((String, String) -> Void)?
    /// 段落间距（段落之间的额外间距），用于呈现更清晰的分段效果
    var paragraphSpacing: CGFloat = 0
    /// 行间距倍数，默认 0（由系统决定）
    var lineSpacing: CGFloat = 0
    /// 是否压缩多余空行（默认开启，将连续多个换行折叠为单个换行）
    var collapseBlankLines: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CollectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        applyStyleAndText(to: textView)
        textView.onSelectionChange = onSelectionChange
        textView.onCollect = onCollect

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CollectableTextView else { return }
        if textView.string != displayText {
            applyStyleAndText(to: textView)
        }
        textView.onSelectionChange = onSelectionChange
        textView.onCollect = onCollect
    }

    /// 展示文本：按需折叠多余空行，避免 AI 返回的空行导致视觉间距过大
    private var displayText: String {
        guard collapseBlankLines else { return text }
        // 将 2 个以上连续换行折叠为单个换行
        return text.replacingOccurrences(
            of: "\\n{2,}",
            with: "\n",
            options: .regularExpression
        )
    }

    /// 应用字体、段落间距并设置文本（使用 attributed string 确保样式生效）
    private func applyStyleAndText(to textView: CollectableTextView) {
        let font = NSFont.systemFont(ofSize: 13)
        var attrs: [NSAttributedString.Key: Any] = [.font: font]

        if paragraphSpacing > 0 || lineSpacing > 0 {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.paragraphSpacing = paragraphSpacing
            if lineSpacing > 0 {
                paragraphStyle.lineSpacing = lineSpacing
            }
            attrs[.paragraphStyle] = paragraphStyle
        }

        let attributed = NSAttributedString(string: displayText, attributes: attrs)
        textView.textStorage?.setAttributedString(attributed)
        // 同步 typingAttributes，确保后续编辑/选区也使用相同的样式
        textView.typingAttributes = attrs
    }
}

final class CollectableTextView: NSTextView {
    var onSelectionChange: ((String) -> Void)?
    var onCollect: ((String, String) -> Void)?

    private var selectedText: String {
        guard selectedRange.length > 0, selectedRange.location != NSNotFound else { return "" }
        return (string as NSString).substring(with: selectedRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func setSelectedRanges(
        _ ranges: [NSValue],
        affinity: NSSelectionAffinity,
        stillSelecting still: Bool
    ) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: still)
        if !still {
            onSelectionChange?(selectedText)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let menu = super.menu(for: event) else { return nil }
        let selection = selectedText
        if !selection.isEmpty {
            let preview = selection.count > 12 ? String(selection.prefix(12)) + "…" : selection
            let collectItem = NSMenuItem(
                title: "收藏「\(preview)」到生词本",
                action: #selector(collectSelection(_:)),
                keyEquivalent: ""
            )
            collectItem.target = self
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(collectItem, at: 0)
        }
        return menu
    }

    @objc private func collectSelection(_ sender: Any?) {
        let selection = selectedText
        guard !selection.isEmpty else { return }
        onCollect?(selection, string)
    }
}
