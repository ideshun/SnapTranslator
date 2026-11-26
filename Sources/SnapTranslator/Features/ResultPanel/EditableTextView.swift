import AppKit
import SnapTranslatorCore
import SwiftUI

/// 可编辑文本视图：舒适阅读排版（14pt + 宽裕留白）、暗色模式适配、剪贴板粘贴图片拦截、右键收藏与 AI 速释
struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 14
    var paragraphSpacing: CGFloat = 8
    var lineSpacing: CGFloat = 4.5
    var onChange: ((String) -> Void)?
    var onSelectionChange: ((String) -> Void)?
    var onCollect: ((String, String) -> Void)?
    var onQuickExplain: ((String, String) -> Void)?
    var onPasteImage: ((NSImage) -> Void)?
    var focusOnAppear: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PasteAwareTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.insertionPointColor = .controlAccentColor
        textView.textContainerInset = NSSize(width: 14, height: 14)
        textView.delegate = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.onCollect = onCollect
        textView.onQuickExplain = onQuickExplain
        applyStyleAndText(to: textView)
        context.coordinator.textView = textView
        context.coordinator.lastFontSize = fontSize

        let scrollView = TextPaneScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? PasteAwareTextView else { return }
        let coordinator = context.coordinator
        textView.onPasteImage = onPasteImage
        textView.onCollect = onCollect
        textView.onQuickExplain = onQuickExplain

        if focusOnAppear && !coordinator.didFocusOnAppear {
            coordinator.didFocusOnAppear = coordinator.focus()
        }
        let fontChanged = abs(coordinator.lastFontSize - fontSize) > 0.1
        if !textView.hasMarkedText() && (textView.string != text || fontChanged) {
            let savedRanges = textView.selectedRanges
            coordinator.isProgrammatic = true
            applyStyleAndText(to: textView)
            if !fontChanged || textView.string == text {
                let maxLen = (textView.string as NSString).length
                let valid = savedRanges.compactMap { val -> NSValue? in
                    let r = val.rangeValue
                    guard r.location <= maxLen else { return nil }
                    return NSValue(range: NSRange(location: r.location, length: min(r.length, maxLen - r.location)))
                }
                if !valid.isEmpty { textView.selectedRanges = valid }
            }
            coordinator.lastFontSize = fontSize
            coordinator.isProgrammatic = false
        }
        coordinator.parent = self
    }

    private func applyStyleAndText(to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = paragraphSpacing
        if lineSpacing > 0 {
            paragraphStyle.lineSpacing = lineSpacing
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle,
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        textView.typingAttributes = attrs
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView
        var isProgrammatic = false
        weak var textView: NSTextView?
        var didFocusOnAppear = false
        var lastFontSize: CGFloat = 14

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        @discardableResult
        func focus() -> Bool {
            guard let textView, let window = textView.window else { return false }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(textView)
            return window.firstResponder === textView
        }

        func textDidChange(_ notification: Notification) {
            guard !isProgrammatic else { return }
            guard let textView = notification.object as? NSTextView else { return }
            let newText = textView.string
            parent.text = newText
            parent.onChange?(newText)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange
            guard range.length > 0, range.location != NSNotFound else {
                parent.onSelectionChange?("")
                return
            }
            let selected = (textView.string as NSString).substring(with: range)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            parent.onSelectionChange?(selected)
        }
    }
}

final class PasteAwareTextView: NSTextView {
    var onPasteImage: ((NSImage) -> Void)?
    var onCollect: ((String, String) -> Void)?
    var onQuickExplain: ((String, String) -> Void)?

    private var selectedText: String {
        guard selectedRange.length > 0, selectedRange.location != NSNotFound else { return "" }
        return (string as NSString).substring(with: selectedRange)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let hasPlainText = !(pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        if !hasPlainText, let image = NSPasteboard.readImage(), let onPasteImage {
            onPasteImage(image)
            return
        }
        super.paste(sender)
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
                    action: #selector(handleQuickExplain(_:)),
                    keyEquivalent: ""
                )
                explainItem.target = self
                menu.insertItem(explainItem, at: 0)
            }
            if onCollect != nil {
                let collectItem = NSMenuItem(
                    title: "收藏「\(preview)」到生词本",
                    action: #selector(handleCollect(_:)),
                    keyEquivalent: ""
                )
                collectItem.target = self
                menu.insertItem(collectItem, at: 0)
            }
        }
        return menu
    }

    @objc private func handleCollect(_ sender: Any?) {
        let selection = selectedText
        guard !selection.isEmpty else { return }
        onCollect?(selection, string)
    }

    @objc private func handleQuickExplain(_ sender: Any?) {
        let selection = selectedText
        guard !selection.isEmpty else { return }
        onQuickExplain?(selection, string)
    }
}
