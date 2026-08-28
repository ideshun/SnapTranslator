import AppKit
import SwiftUI

/// 可编辑文本视图：用于翻译页签左侧识别区，支持编辑并实时触发翻译
/// 文字变化时通过 onChange 回调（供 AppDelegate 实时翻译）
/// 同时通过 onSelectionChange 回调跟踪左侧选中文本（供左侧朗读优先朗读选中内容）
struct EditableTextView: NSViewRepresentable {
    @Binding var text: String
    var paragraphSpacing: CGFloat = 4
    var lineSpacing: CGFloat = 2
    /// 文字变化回调（编辑后触发，用于实时翻译）
    var onChange: ((String) -> Void)?
    /// 选中文本变化回调（用于左侧朗读时优先朗读选中内容）
    var onSelectionChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.delegate = context.coordinator
        applyStyleAndText(to: textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // 仅当外部传入的文本与当前编辑内容不同时才同步（避免覆盖用户正在输入的字符）
        if textView.string != text {
            applyStyleAndText(to: textView)
        }
        context.coordinator.parent = self
    }

    /// 应用字体、段落间距并设置文本
    private func applyStyleAndText(to textView: NSTextView) {
        let font = NSFont.systemFont(ofSize: 13)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = paragraphSpacing
        if lineSpacing > 0 {
            paragraphStyle.lineSpacing = lineSpacing
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraphStyle,
        ]
        textView.textStorage?.setAttributedString(NSAttributedString(string: text, attributes: attrs))
        // 同步 typingAttributes，确保后续输入沿用样式
        textView.typingAttributes = attrs
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: EditableTextView

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
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
