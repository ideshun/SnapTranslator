import AppKit
import SwiftUI

/// 结果置顶面板：NSPanel（nonactivating + floating），失焦自动降透明度
@MainActor
final class ResultPanelController: NSObject, NSWindowDelegate {
    let model = ResultModel()

    /// 语义回调（由 AppDelegate 注入）
    var onCollect: ((String, String) -> Void)?
    var onRetry: (() -> Void)?
    var onSwapLanguages: (() -> Void)?
    var onOpenWordBook: (() -> Void)?
    /// 翻译页签左侧原文编辑后的实时翻译回调
    var onLiveTranslate: ((String) -> Void)?

    private let settings: SettingsStore
    private var panel: NSPanel?
    private var focusObservers: [NSObjectProtocol] = []

    init(settings: SettingsStore) {
        self.settings = settings
        super.init()
    }

    // MARK: - NSWindowDelegate

    /// 点关闭（红绿灯/⌘W）时隐藏面板而非销毁窗口，保持菜单栏驻留
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    private func ensurePanel() -> NSPanel {
        if let panel {
            return panel
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            // 含 closable/miniaturizable 以支持远程桌面（VNC）右上角红绿灯关闭/最小化
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "SnapTranslator"
        panel.level = settings.alwaysOnTop ? .floating : .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = settings.alwaysOnTop
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.backgroundColor = .windowBackgroundColor
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("ResultPanelFrame")
        // 关闭（右上角红绿灯/⌘W）时隐藏而非退出，保持菜单栏驻留
        panel.delegate = self
        panel.contentView = NSHostingView(
            rootView: ResultPanelView(
                model: model,
                settings: settings,
                onCollect: { [weak self] phrase, context in
                    self?.onCollect?(phrase, context)
                },
                onRetry: { [weak self] in
                    self?.onRetry?()
                },
                onClose: { [weak self] in
                    self?.hide()
                },
                onTogglePin: { [weak self] in
                    self?.togglePin()
                },
                onSwapLanguages: { [weak self] in
                    self?.onSwapLanguages?()
                },
                onOpenWordBook: { [weak self] in
                    self?.onOpenWordBook?()
                },
                onLiveTranslate: { [weak self] text in
                    self?.onLiveTranslate?(text)
                }
            )
        )
        observeFocus(panel)
        self.panel = panel
        return panel
    }

    /// 显示面板：有选区时贴近选区展示
    func show(near rect: CGRect?) {
        let panel = ensurePanel()
        panel.alphaValue = 1
        if let rect {
            position(panel: panel, near: rect)
        }
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible {
            hide()
        } else {
            show(near: nil)
        }
    }

    /// 应用置顶设置（设置变化时调用）
    func applyPin(alwaysOnTop: Bool) {
        guard let panel else { return }
        panel.isFloatingPanel = alwaysOnTop
        panel.level = alwaysOnTop ? .floating : .normal
    }

    private func togglePin() {
        settings.alwaysOnTop.toggle()
        // 立即生效，避免依赖 settings.objectWillChange 的 200ms 防抖
        applyPin(alwaysOnTop: settings.alwaysOnTop)
    }

    /// 面板贴近选区展示：右侧优先，越界换左侧/下方
    private func position(panel: NSPanel, near rect: CGRect) {
        let panelSize = panel.frame.size
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame

        var origin = NSPoint(
            x: rect.maxX + 12,
            y: rect.midY - panelSize.height / 2
        )
        if origin.x + panelSize.width > visible.maxX {
            origin.x = rect.minX - panelSize.width - 12
        }
        if origin.x < visible.minX {
            origin.x = rect.minX
            origin.y = rect.minY - panelSize.height - 12
        }
        origin.y = max(visible.minY, min(origin.y, visible.maxY - panelSize.height))
        origin.x = max(visible.minX, min(origin.x, visible.maxX - panelSize.width))
        panel.setFrameOrigin(origin)
    }

    /// 失焦降透明度 / 聚焦恢复
    private func observeFocus(_ panel: NSPanel) {
        let center = NotificationCenter.default
        focusObservers.append(
            center.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.setAlpha(self?.settings.unfocusedOpacity ?? 0.3)
                }
            }
        )
        focusObservers.append(
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.setAlpha(1)
                }
            }
        )
    }

    private func setAlpha(_ value: Double) {
        guard let panel, panel.alphaValue != value else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = value
        }
    }
}
