import AppKit
import SwiftUI

/// 框选遮罩窗口：每块屏幕一个，置于 screenSaver 级别覆盖全部内容
final class OverlayWindow: NSWindow {
    var onRegionSelected: ((CGRect) -> Void)?
    var onCancelled: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let overlay = OverlayView(
            screenFrame: screen.frame,
            onSelect: { [weak self] rect in
                self?.onRegionSelected?(rect)
            },
            onCancel: { [weak self] in
                self?.onCancelled?()
            }
        )
        contentView = NSHostingView(rootView: overlay)
    }

    override var canBecomeKey: Bool { true }
}
