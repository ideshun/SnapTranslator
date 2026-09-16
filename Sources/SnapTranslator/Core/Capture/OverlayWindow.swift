import AppKit
import SwiftUI

/// 专门的 HostingView：重写 acceptsFirstMouse 返回 true，
/// 确保非 Key 窗口（如副屏遮罩）在收到第一次鼠标点击时立即响应手势，而不会被系统“激活窗口”吞掉
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

/// 框选遮罩窗口：每块屏幕一个，置于 screenSaver 级别覆盖全部内容
final class OverlayWindow: NSWindow {
    var onRegionSelected: ((_ globalRect: CGRect, _ localRect: CGRect, _ snapshot: CGImage?) -> Void)?
    var onCancelled: (() -> Void)?
    let screenSnapshot: CGImage?

    init(screen: NSScreen, snapshot: CGImage?) {
        self.screenSnapshot = snapshot
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

        let snapshotNSImage = snapshot.map {
            NSImage(cgImage: $0, size: screen.frame.size)
        }

        let overlay = OverlayView(
            screenFrame: screen.frame,
            snapshot: snapshotNSImage,
            onSelect: { [weak self] globalRect, localRect in
                self?.onRegionSelected?(globalRect, localRect, self?.screenSnapshot)
            },
            onCancel: { [weak self] in
                self?.onCancelled?()
            }
        )
        contentView = OverlayHostingView(rootView: overlay)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown && !isKeyWindow {
            makeKey()
        }
        super.sendEvent(event)
    }
}
