import AppKit
import SnapTranslatorCore
import SwiftUI

/// 悬停窗口高亮框视图（QQ 式窗口吸附的选框效果）
final class WindowHighlightView: NSView {
    var highlightRect: CGRect? {
        didSet {
            if highlightRect != oldValue {
                needsDisplay = true
            }
        }
    }

    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        guard let rect = highlightRect else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        NSColor.controlAccentColor.setStroke()
        let border = NSBezierPath(roundedRect: NSInsetRect(rect, 1.25, 1.25), xRadius: 6, yRadius: 6)
        border.lineWidth = 2.5
        border.stroke()
    }
}

final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 框选遮罩窗口：每块屏幕一个，支持拖拽框选、窗口吸附、精调模式与快捷模式切换
final class OverlayWindow: NSWindow {
    var onRegionSelected: ((_ globalRect: CGRect, _ localRect: CGRect, _ snapshot: CGImage?, _ action: CaptureAction) -> Void)?
    var onCancelled: (() -> Void)?
    let screenSnapshot: CGImage?

    private var hoverWindowRect: CGRect?
    private var mouseDownPoint: NSPoint?
    private var dragExceededThreshold = false
    private var lastHoverQueryPoint: NSPoint = .zero
    private let primaryTopY: CGFloat
    private let highlightView = WindowHighlightView()
    private let state: OverlaySessionState

    init(
        screen: NSScreen,
        snapshot: CGImage?,
        defaultAction: CaptureAction,
        refineMode: Bool
    ) {
        self.screenSnapshot = snapshot
        self.state = OverlaySessionState(action: defaultAction, refineMode: refineMode)
        self.primaryTopY = (NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main)?.frame.maxY ?? 0

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
        acceptsMouseMovedEvents = true

        let snapshotNSImage = snapshot.map {
            NSImage(cgImage: $0, size: screen.frame.size)
        }

        let overlay = OverlayView(
            screenFrame: screen.frame,
            snapshot: snapshotNSImage,
            state: state,
            onSelect: { [weak self] globalRect, localRect, action in
                self?.onRegionSelected?(globalRect, localRect, self?.screenSnapshot, action)
            },
            onCancel: { [weak self] in
                self?.onCancelled?()
            }
        )
        let hosting = OverlayHostingView(rootView: overlay)
        contentView = hosting
        highlightView.frame = hosting.bounds
        highlightView.autoresizingMask = [.width, .height]
        hosting.addSubview(highlightView)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            onCancelled?()
            return
        case .keyDown:
            // 精调态下支持回车确认、方向键 1pt 微调选区
            if state.lockedSelection != nil {
                if handleRefineKeyDown(event) { return }
            }
        case .leftMouseDown:
            if state.lockedSelection == nil {
                mouseDownPoint = NSEvent.mouseLocation
                dragExceededThreshold = false
            }
        case .leftMouseDragged:
            if state.lockedSelection == nil, let down = mouseDownPoint {
                let location = NSEvent.mouseLocation
                if hypot(location.x - down.x, location.y - down.y) > 4 {
                    dragExceededThreshold = true
                    setHoverWindow(nil)
                }
            }
        case .leftMouseUp:
            if state.lockedSelection == nil {
                let wasClickOnTopBar = isInTopModeBar(event.locationInWindow)
                mouseDownPoint = nil
                if !wasClickOnTopBar, !dragExceededThreshold, let windowRect = hoverWindowRect {
                    selectWindow(windowRect)
                    return
                }
            }
        case .mouseMoved:
            if state.lockedSelection == nil && !isInTopModeBar(event.locationInWindow) {
                updateHoverWindow(at: NSEvent.mouseLocation)
            } else {
                setHoverWindow(nil)
            }
        default:
            break
        }
        super.sendEvent(event)
    }

    private func isInTopModeBar(_ pointInWindow: NSPoint) -> Bool {
        // 顶部模式条居中（距离顶部 64pt 内）
        pointInWindow.y >= frame.height - 76 && abs(pointInWindow.x - frame.width / 2) < 260
    }

    private func handleRefineKeyDown(_ event: NSEvent) -> Bool {
        guard var rect = state.lockedSelection else { return false }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 36, 76: // Return / Enter
            let global = CGRect(
                x: frame.minX + rect.minX,
                y: frame.maxY - rect.maxY,
                width: rect.width,
                height: rect.height
            )
            onRegionSelected?(global, rect, screenSnapshot, state.action)
            return true
        case 123: rect.origin.x = max(0, rect.origin.x - step)
        case 124: rect.origin.x = min(frame.width - rect.width, rect.origin.x + step)
        case 126: rect.origin.y = max(0, rect.origin.y - step)
        case 125: rect.origin.y = min(frame.height - rect.height, rect.origin.y + step)
        default: return false
        }
        state.lockedSelection = rect
        return true
    }

    private func updateHoverWindow(at mouse: NSPoint) {
        let moved = hypot(mouse.x - lastHoverQueryPoint.x, mouse.y - lastHoverQueryPoint.y)
        if moved < 3 { return }
        lastHoverQueryPoint = mouse
        setHoverWindow(WindowSnapLocator.windowRect(under: mouse, primaryTopY: primaryTopY))
    }

    private func setHoverWindow(_ rect: CGRect?) {
        guard rect != hoverWindowRect else { return }
        hoverWindowRect = rect
        highlightView.highlightRect = rect.map { convertFromScreen($0) }
    }

    private func selectWindow(_ globalRect: CGRect) {
        let localTopLeft = CGRect(
            x: globalRect.minX - frame.minX,
            y: frame.maxY - globalRect.maxY,
            width: globalRect.width,
            height: globalRect.height
        )
        if state.refineMode {
            setHoverWindow(nil)
            state.lockedSelection = localTopLeft
        } else {
            onRegionSelected?(globalRect, localTopLeft, screenSnapshot, state.action)
        }
    }
}
