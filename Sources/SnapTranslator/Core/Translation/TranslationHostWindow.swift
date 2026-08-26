import AppKit
import SwiftUI
import Translation

/// 专用翻译锚点窗口控制器：托管 TranslationAnchorView，用于 Apple 翻译和语言包准备
/// 解决以下问题：
/// 1. 语言包下载不需要显示结果面板（"点击下载跳首页"的问题）
/// 2. 翻译锚点始终在可见窗口中，保证 TranslationSession 可靠触发
@MainActor
final class TranslationHostWindowController {
    let anchor = TranslationAnchor()
    private var panel: NSPanel?

    /// 确保窗口存在：小尺寸、无边框、透明、不可交互
    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // 锚点视图：透明视图，只负责驱动 TranslationSession
        if #available(macOS 15.0, *) {
            let hosting = NSHostingView(
                rootView: TranslationAnchorView(anchor: anchor)
            )
            // 使用完整窗口尺寸，确保 SwiftUI 视图能正确渲染和激活
            hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting
        }
        self.panel = panel
        return panel
    }

    /// 显示锚点窗口（屏幕右下角边缘，几乎不可见）
    func show() {
        let panel = ensurePanel()
        // 放在屏幕右下角边缘，极小尺寸几乎不可见
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.maxX - 100,
                y: visible.minY + 10
            ))
        }
        panel.orderFront(nil)
    }

    /// 隐藏锚点窗口
    func hide() {
        panel?.orderOut(nil)
        anchor.cancelPending()
    }

    /// 触发语言包下载准备
    func prepareLanguages(source: Language?, target: Language) async throws {
        show()
        try await anchor.prepareLanguages(source: source, target: target)
    }
}
