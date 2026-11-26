import AppKit
import SnapTranslatorCore
import UniformTypeIdentifiers

/// 桌面悬浮贴图窗口：支持把原图或 1:1 译文图钉在桌面任意位置
/// - 左键拖拽移动、滚轮缩放、Option + 滚轮调透明度、双击 1:1 重置、ESC 关闭
/// - 右键菜单：复制图片 / 保存为 PNG / 恢复原尺寸 / 关闭贴图
@MainActor
final class PinImageWindowController: NSObject, NSWindowDelegate {
    private var windows: [UUID: NSPanel] = [:]

    func pin(image: NSImage, near rect: CGRect? = nil, title: String = "贴图") {
        let id = UUID()
        let maxInitSide: CGFloat = 720
        let rawSize = image.size
        let scale = min(1.0, maxInitSide / max(1, max(rawSize.width, rawSize.height)))
        let initSize = NSSize(
            width: max(80, (rawSize.width * scale).rounded()),
            height: max(60, (rawSize.height * scale).rounded())
        )

        let panel = PinImagePanel(
            id: id,
            image: image,
            contentRect: NSRect(origin: .zero, size: initSize)
        )
        panel.title = title
        panel.delegate = self
        panel.onRequestClose = { [weak self] closedID in
            self?.close(id: closedID)
        }

        if let rect {
            panel.setFrameOrigin(NSPoint(x: rect.minX, y: rect.minY))
        } else if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let offset = CGFloat(windows.count % 6) * 24
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - initSize.width / 2 + offset,
                y: visible.midY - initSize.height / 2 - offset
            ))
        }

        windows[id] = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func close(id: UUID) {
        if let panel = windows.removeValue(forKey: id) {
            panel.orderOut(nil)
        }
    }

    func closeAll() {
        for (_, panel) in windows {
            panel.orderOut(nil)
        }
        windows.removeAll()
    }
}

private final class PinImagePanel: NSPanel {
    let pinID: UUID
    let pinnedImage: NSImage
    var onRequestClose: ((UUID) -> Void)?
    private let baseSize: NSSize
    private var currentScale: CGFloat = 1.0

    init(id: UUID, image: NSImage, contentRect: NSRect) {
        self.pinID = id
        self.pinnedImage = image
        self.baseSize = contentRect.size
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let contentView = PinImageContentView(image: image)
        contentView.onDoubleClick = { [weak self] in self?.resetScale() }
        contentView.onCopy = { [weak self] in
            if let img = self?.pinnedImage { NSPasteboard.writeImage(img) }
        }
        contentView.onSave = { [weak self] in self?.savePNG() }
        contentView.onClose = { [weak self] in
            if let self { self.onRequestClose?(self.pinID) }
        }
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // ESC
            onRequestClose?(pinID)
            return
        }
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            NSPasteboard.writeImage(pinnedImage)
            return
        }
        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }
        if event.modifierFlags.contains(.option) {
            let nextAlpha = max(0.2, min(1.0, alphaValue + (delta > 0 ? 0.05 : -0.05)))
            alphaValue = nextAlpha
            return
        }
        let factor: CGFloat = delta > 0 ? 1.08 : (1.0 / 1.08)
        applyScale(max(0.25, min(3.5, currentScale * factor)))
    }

    private func resetScale() {
        applyScale(1.0)
        alphaValue = 1.0
    }

    private func applyScale(_ newScale: CGFloat) {
        currentScale = newScale
        let center = NSPoint(x: frame.midX, y: frame.midY)
        let newSize = NSSize(
            width: max(60, (baseSize.width * currentScale).rounded()),
            height: max(48, (baseSize.height * currentScale).rounded())
        )
        let newFrame = NSRect(
            x: center.x - newSize.width / 2,
            y: center.y - newSize.height / 2,
            width: newSize.width,
            height: newSize.height
        )
        setFrame(newFrame, display: true)
    }

    private func savePNG() {
        guard let png = pinnedImage.pngData() else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.nameFieldStringValue = "SnapTranslator-贴图.png"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            try? png.write(to: url, options: .atomic)
        }
    }
}

private final class PinImageContentView: NSView {
    private let imageView = NSImageView()
    var onDoubleClick: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onClose: (() -> Void)?

    init(image: NSImage) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1.5
        layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.65).cgColor

        imageView.image = image
        imageView.imageScaling = .scaleAxesIndependently
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        imageView.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }
        super.mouseDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "复制图片 (⌘C)", action: #selector(handleCopy), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let saveItem = NSMenuItem(title: "保存为 PNG…", action: #selector(handleSave), keyEquivalent: "")
        saveItem.target = self
        menu.addItem(saveItem)

        let resetItem = NSMenuItem(title: "重置大小与透明度", action: #selector(handleReset), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)

        menu.addItem(.separator())

        let closeItem = NSMenuItem(title: "关闭贴图 (ESC)", action: #selector(handleClose), keyEquivalent: "")
        closeItem.target = self
        menu.addItem(closeItem)
        return menu
    }

    @objc private func handleCopy() { onCopy?() }
    @objc private func handleSave() { onSave?() }
    @objc private func handleReset() { onDoubleClick?() }
    @objc private func handleClose() { onClose?() }
}
