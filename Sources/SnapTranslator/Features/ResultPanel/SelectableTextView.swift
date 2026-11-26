import AppKit
import SnapTranslatorCore
import SwiftUI

/// 可选中文本视图：舒适阅读排版（14pt + 宽松行距）、暗色模式适配、右键收藏与 AI 速释
struct SelectableTextView: NSViewRepresentable {
    let text: String
    var fontSize: CGFloat = 14
    var onSelectionChange: ((String) -> Void)?
    var onCollect: ((String, String) -> Void)?
    var onQuickExplain: ((String, String) -> Void)?
    var paragraphSpacing: CGFloat = 8
    var lineSpacing: CGFloat = 4.5
    var collapseBlankLines: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let textView = CollectableTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 14, height: 14)
        applyStyleAndText(to: textView)
        textView.onSelectionChange = onSelectionChange
        textView.onCollect = onCollect
        textView.onQuickExplain = onQuickExplain

        let scrollView = TextPaneScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? CollectableTextView else { return }
        let currentSize = (textView.typingAttributes[.font] as? NSFont)?.pointSize ?? 0
        let fontChanged = abs(currentSize - fontSize) > 0.1
        if textView.string != displayText || fontChanged {
            let savedRanges = textView.selectedRanges
            applyStyleAndText(to: textView)
            if fontChanged && textView.string == displayText {
                let maxLen = (textView.string as NSString).length
                let valid = savedRanges.compactMap { val -> NSValue? in
                    let r = val.rangeValue
                    guard r.location <= maxLen else { return nil }
                    return NSValue(range: NSRange(location: r.location, length: min(r.length, maxLen - r.location)))
                }
                if !valid.isEmpty { textView.selectedRanges = valid }
            }
        }
        textView.onSelectionChange = onSelectionChange
        textView.onCollect = onCollect
        textView.onQuickExplain = onQuickExplain
    }

    private var displayText: String {
        guard collapseBlankLines else { return text }
        return text.replacingOccurrences(of: "\\n{3,}", with: "\n\n", options: .regularExpression)
    }

    private func applyStyleAndText(to textView: CollectableTextView) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
        ]
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
        textView.typingAttributes = attrs
    }
}

final class CollectableTextView: NSTextView {
    var onSelectionChange: ((String) -> Void)?
    var onCollect: ((String, String) -> Void)?
    var onQuickExplain: ((String, String) -> Void)?

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
            menu.insertItem(.separator(), at: 0)
            if onQuickExplain != nil {
                let explainItem = NSMenuItem(
                    title: "AI 速释「\(preview)」",
                    action: #selector(quickExplainSelection(_:)),
                    keyEquivalent: ""
                )
                explainItem.target = self
                menu.insertItem(explainItem, at: 0)
            }
            if onCollect != nil {
                let collectItem = NSMenuItem(
                    title: "收藏「\(preview)」到生词本",
                    action: #selector(collectSelection(_:)),
                    keyEquivalent: ""
                )
                collectItem.target = self
                menu.insertItem(collectItem, at: 0)
            }
        }
        return menu
    }

    @objc private func collectSelection(_ sender: Any?) {
        let selection = selectedText
        guard !selection.isEmpty else { return }
        onCollect?(selection, string)
    }

    @objc private func quickExplainSelection(_ sender: Any?) {
        let selection = selectedText
        guard !selection.isEmpty else { return }
        onQuickExplain?(selection, string)
    }
}
