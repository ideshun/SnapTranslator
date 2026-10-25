import AppKit
import SwiftUI

/// 专门的 HostingView：重写 acceptsFirstMouse 返回 true，
/// 确保非 Key 窗口（如副屏遮罩）在收到第一次鼠标点击时立即响应手势，而不会被系统“激活窗口”吞掉。
/// 同时负责绘制鼠标悬停窗口的高亮框（QQ 式窗口吸附）
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    /// 悬停窗口高亮框（视图本地坐标，原点左下）；nil 表示无悬停窗口
    var hoverHighlightRect: CGRect? {
        didSet {
            if hoverHighlightRect != oldValue {
                needsDisplay = true
            }
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let rect = hoverHighlightRect else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(rect: rect).fill()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(rect: NSInsetRect(rect, 1, 1))
        border.lineWidth = 2
        border.stroke()
    }
}

/// 框选遮罩窗口：每块屏幕一个，置于 screenSaver 级别覆盖全部内容。
/// 交互：
/// - 拖拽 = 手动框选区域（OverlayView 的 DragGesture 处理）
/// - 鼠标悬停 = 高亮光标下的整窗（QQ 式窗口吸附），单击即选中该窗口
/// - 右键 / ESC = 取消
final class OverlayWindow: NSWindow {
    var onRegionSelected: ((_ globalRect: CGRect, _ localRect: CGRect, _ snapshot: CGImage?) -> Void)?
    var onCancelled: (() -> Void)?
    let screenSnapshot: CGImage?

    /// 悬停吸附的窗口矩形（全局 AppKit 坐标，原点左下）
    private var hoverWindowRect: CGRect?
    private var mouseDownPoint: NSPoint?
    private var dragExceededThreshold = false
    private var lastHoverQueryPoint: NSPoint = .zero
    /// CG 全局坐标（主屏左上原点）→ AppKit 坐标换算用的主屏顶边 Y
    private let primaryTopY: CGFloat
    private var overlayHosting: OverlayHostingView<OverlayView>?

    init(screen: NSScreen, snapshot: CGImage?) {
        self.screenSnapshot = snapshot
        primaryTopY = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.maxY ?? 0
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
        // 窗口吸附需要持续的鼠标移动事件
        acceptsMouseMovedEvents = true

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
        let hosting = OverlayHostingView(rootView: overlay)
        overlayHosting = hosting
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            // 右键取消框选（与 ESC 等价，截图工具的常规交互）
            onCancelled?()
            return
        case .leftMouseDown:
            mouseDownPoint = NSEvent.mouseLocation
            dragExceededThreshold = false
        case .leftMouseDragged:
            if let down = mouseDownPoint {
                let location = NSEvent.mouseLocation
                let moved = hypot(location.x - down.x, location.y - down.y)
                if moved > 4 {
                    dragExceededThreshold = true
                    // 开始拖拽框选后取消窗口吸附高亮
                    setHoverWindow(nil)
                }
            }
        case .leftMouseUp:
            mouseDownPoint = nil
            // 无拖拽且有悬停窗口：单击即选中该窗口（QQ 式窗口吸附）。
            // 吞掉事件，避免继续派发给 SwiftUI 手势被判定为“误触小选区”而取消
            if !dragExceededThreshold, let windowRect = hoverWindowRect {
                selectWindow(windowRect)
                return
            }
        case .mouseMoved:
            updateHoverWindow(at: NSEvent.mouseLocation)
        default:
            break
        }
        super.sendEvent(event)
    }

    // MARK: - 窗口吸附

    private func updateHoverWindow(at mouse: NSPoint) {
        // 节流：移动不足 3pt 不重复查询窗口列表
        let moved = hypot(mouse.x - lastHoverQueryPoint.x, mouse.y - lastHoverQueryPoint.y)
        if moved < 3 { return }
        lastHoverQueryPoint = mouse
        setHoverWindow(Self.windowRectUnderMouse(mouse, primaryTopY: primaryTopY))
    }

    private func setHoverWindow(_ rect: CGRect?) {
        guard rect != hoverWindowRect else { return }
        hoverWindowRect = rect
        overlayHosting?.hoverHighlightRect = rect.map { convertFromScreen($0) }
    }

    /// 单击选中窗口：与拖拽框选一致的回调约定（全局 AppKit 坐标 + 屏幕内左上原点局部坐标）
    private func selectWindow(_ globalRect: CGRect) {
        let localTopLeft = CGRect(
            x: globalRect.minX - frame.minX,
            y: frame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
        onRegionSelected?(globalRect, localTopLeft, screenSnapshot)
    }

    /// 光标下最前面的普通窗口（全局 AppKit 坐标）；无则返回 nil。
    /// 窗口列表按前到后排序，第一个包含光标的即最上层窗口
    private static func windowRectUnderMouse(_ mouse: NSPoint, primaryTopY: CGFloat) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
            as? [[String: Any]] else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        // CG 全局坐标以主屏左上为原点、Y 向下
        let cgPoint = CGPoint(x: mouse.x, y: primaryTopY - mouse.y)
        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID else { continue }
            // 仅普通窗口层（菜单栏/桌面/浮层不算）
            guard (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: bounds) else { continue }
            guard cgRect.width > 40, cgRect.height > 40, cgRect.contains(cgPoint) else { continue }
            // CG（左上原点）→ AppKit 全局（左下原点）
            return CGRect(
                x: cgRect.minX,
                y: primaryTopY - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
        }
        return nil
    }
}
