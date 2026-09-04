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
    /// 视图出现后是否自动聚焦（首次展示翻译页签时直接可输入）
    var focusOnAppear: Bool = false

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
        context.coordinator.textView = textView

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let coordinator = context.coordinator
        // 出现后接管焦点：仅当焦点确实设置成功才消耗标记。
        // 若首次 updateNSView 时视图尚未挂进窗口（window == nil）静默失败，
        // 保留标记可借后续 SwiftUI 更新重试，否则面板永远失去自动聚焦。
        if focusOnAppear && !coordinator.didFocusOnAppear {
            coordinator.didFocusOnAppear = coordinator.focus()
        }
        // 仅当外部传入的文本与当前编辑内容不同，且不在输入法拼音合成（marked text）期间才同步，
        // 避免 setAttributedString 重置 textStorage 打断中文等输入法的候选字。
        if !textView.hasMarkedText() && textView.string != text {
            coordinator.isProgrammatic = true
            applyStyleAndText(to: textView)
            coordinator.isProgrammatic = false
        }
        coordinator.parent = self
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
        /// 标记当前是否为程序化同步文本，避免 setAttributedString 触发递归 onChange 干扰实时翻译
        var isProgrammatic = false
        /// 弱引用编辑框，用于自动聚焦
        weak var textView: NSTextView?
        /// 是否已执行过出现时的自动聚焦
        var didFocusOnAppear = false

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        /// 把窗口首响应者切到编辑框（激活应用以确保键盘事件可达）
        /// - Returns: 焦点是否真正设置成功（供调用方决定是否保留重试标记）
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
