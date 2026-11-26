import AppKit
import SwiftUI
import Translation

/// 专用翻译锚点窗口控制器：托管 TranslationAnchorView，用于 Apple 翻译和语言包准备
@MainActor
public final class TranslationHostWindowController {
    public let anchor = TranslationAnchor()
    private var panel: NSPanel?

    public init() {}

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

        if #available(macOS 15.0, *) {
            let hosting = NSHostingView(rootView: TranslationAnchorView(anchor: anchor))
            hosting.frame = NSRect(x: 0, y: 0, width: 100, height: 100)
            hosting.wantsLayer = true
            hosting.layer?.backgroundColor = NSColor.clear.cgColor
            panel.contentView = hosting
        }
        self.panel = panel
        return panel
    }

    public func show() {
        let panel = ensurePanel()
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: visible.maxX - 100, y: visible.minY + 10))
        }
        panel.orderFront(nil)
    }

    public func hide() {
        panel?.orderOut(nil)
        anchor.cancelAll()
    }

    public func prepareLanguages(source: Language?, target: Language) async throws {
        show()
        try await anchor.prepareLanguages(source: source, target: target)
    }
}
