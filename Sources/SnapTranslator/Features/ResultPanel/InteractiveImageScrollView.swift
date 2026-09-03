import AppKit
import SwiftUI

/// 可拖拽、可缩放图片的 NSScrollView 子类
/// - Option + 滚轮缩放
/// - 鼠标左键拖拽平移（图片超出可视区时）
/// - 触控板捏合缩放
/// - 双击重置缩放
final class InteractiveImageScrollView: NSScrollView {
    /// 当前缩放比例
    var imageScale: CGFloat = 1.0 {
        didSet {
            if abs(imageScale - oldValue) > 0.001 {
                onScaleChanged?(imageScale)
                updateImageLayout()
            }
        }
    }
    var onScaleChanged: ((CGFloat) -> Void)?

    private let imageView = NSImageView()
    let containerView = PanContainerView()

    /// 是否需要滚动（图片超出可视区）
    private var hasOverflow: Bool {
        let docSize = containerView.frame.size
        let clipSize = contentView.bounds.size
        return docSize.width > clipSize.width + 1 || docSize.height > clipSize.height + 1
    }

    var displayImage: NSImage? {
        didSet {
            imageView.image = displayImage
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    // MARK: - Setup

    private func setup() {
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        backgroundColor = .clear

        imageView.imageScaling = .scaleAxesIndependently

        containerView.addSubview(imageView)
        documentView = containerView

        // 容器视图回调：拖拽平移和双击重置
        containerView.onPanStart = { [weak self] in
            self?.beginPanning()
        }
        containerView.onPanChanged = { [weak self] dx, dy in
            self?.panBy(dx: dx, dy: dy)
        }
        containerView.onPanEnd = { [weak self] in
            self?.endPanning()
        }
        containerView.onDoubleClick = { [weak self] in
            self?.setImageScale(1.0)
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateImageLayout()
    }

    /// 根据缩放比例更新图片和滚动区域
    private func updateImageLayout() {
        guard let image = displayImage else {
            imageView.image = nil
            return
        }

        let baseSize = image.size
        guard baseSize.width > 0, baseSize.height > 0 else { return }

        let clipSize = contentView.bounds.size
        let availW = max(clipSize.width - 16, 50)
        let availH = max(clipSize.height - 16, 50)

        // 1.0 缩放时：图片适配可视区（保持比例）
        let baseScale = min(1.0, availW / baseSize.width, availH / baseSize.height)
        let displayW = baseSize.width * baseScale * imageScale
        let displayH = baseSize.height * baseScale * imageScale

        // 更新容器大小（为滚动提供可滚动区域）
        let containerW = max(displayW + 16, clipSize.width)
        let containerH = max(displayH + 16, clipSize.height)
        containerView.frame = NSRect(x: 0, y: 0, width: containerW, height: containerH)
        containerView.setFrameSize(containerView.frame.size)

        // 更新图片大小（左上角对齐，带 8pt 边距）
        imageView.frame = NSRect(x: 8, y: 8, width: displayW, height: displayH)
        imageView.imageScaling = .scaleAxesIndependently
    }

    // MARK: - 缩放控制

    func setImageScale(_ newScale: CGFloat) {
        let clamped = max(0.2, min(5.0, newScale))
        guard abs(clamped - imageScale) > 0.001 else { return }
        imageScale = clamped
    }

    private func zoomByFactor(_ factor: CGFloat) {
        guard factor != 1.0 else { return }
        setImageScale(imageScale * factor)
    }

    // MARK: - 拖拽平移

    private var isCursorPushed = false

    private func beginPanning() {
        if hasOverflow && !isCursorPushed {
            NSCursor.closedHand.push()
            isCursorPushed = true
        }
    }

    private func panBy(dx: CGFloat, dy: CGFloat) {
        guard hasOverflow else { return }

        let clip = contentView
        var newOrigin = clip.bounds.origin
        newOrigin.x -= dx
        newOrigin.y += dy

        // 限制滚动范围
        let maxX = max(0, containerView.frame.width - clip.bounds.width)
        let maxY = max(0, containerView.frame.height - clip.bounds.height)
        newOrigin.x = max(0, min(maxX, newOrigin.x))
        newOrigin.y = max(0, min(maxY, newOrigin.y))

        clip.scroll(to: newOrigin)
        reflectScrolledClipView(clip)
    }

    private func endPanning() {
        if isCursorPushed {
            NSCursor.pop()
            isCursorPushed = false
        }
    }

    // MARK: - 事件处理

    override var acceptsFirstResponder: Bool { true }

    /// Option + 滚轮缩放；其余交给 NSScrollView 默认滚动
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.option) {
            let delta = event.scrollingDeltaY
            if delta != 0 {
                let factor: CGFloat = delta > 0 ? 1.15 : (1.0 / 1.15)
                zoomByFactor(factor)
                return
            }
        }
        super.scrollWheel(with: event)
    }

    /// 触控板捏合缩放
    override func magnify(with event: NSEvent) {
        let factor = 1.0 + event.magnification
        zoomByFactor(factor)
    }
}

/// 翻转坐标系视图（左上角为原点），用于 NSScrollView 的 documentView
/// 同时处理拖拽平移和双击事件
final class PanContainerView: NSView {
    var onPanStart: (() -> Void)?
    var onPanChanged: ((CGFloat, CGFloat) -> Void)?
    var onPanEnd: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    private var isPanning = false
    private var lastDragLocation: NSPoint = .zero

    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        isPanning = true
        lastDragLocation = event.locationInWindow
        onPanStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPanning else { return }
        let current = event.locationInWindow
        let dx = current.x - lastDragLocation.x
        let dy = current.y - lastDragLocation.y
        lastDragLocation = current
        onPanChanged?(dx, dy)
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            onPanEnd?()
        }
    }
}

/// SwiftUI 包装：可拖拽缩放图片
struct InteractiveImageView: NSViewRepresentable {
    let image: NSImage
    @Binding var scale: CGFloat

    func makeNSView(context: Context) -> InteractiveImageScrollView {
        let view = InteractiveImageScrollView()
        view.displayImage = image
        view.imageScale = scale
        view.onScaleChanged = { newScale in
            DispatchQueue.main.async {
                scale = newScale
            }
        }
        return view
    }

    func updateNSView(_ nsView: InteractiveImageScrollView, context: Context) {
        if nsView.displayImage !== image {
            nsView.displayImage = image
        }
        if abs(nsView.imageScale - scale) > 0.001 {
            nsView.setImageScale(scale)
        }
    }
}
