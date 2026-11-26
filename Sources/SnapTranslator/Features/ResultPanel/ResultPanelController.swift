import AppKit
import SnapTranslatorCore
import SwiftUI

/// 结果置顶面板：NSPanel（nonactivating + floating），支持失焦降透明度、全键盘快捷流与图片粘贴
@MainActor
final class ResultPanelController: NSObject, NSWindowDelegate {
    let model = ResultModel()

    var onStartCapture: (() -> Void)?
    var onStartSilentOCR: (() -> Void)?
    var onRecaptureLastRegion: (() -> Void)?
    var onTranslateClipboard: (() -> Void)?
    var onCollect: ((String, String) -> Void)?
    var onRetry: (() -> Void)?
    var onSwapLanguages: (() -> Void)?
    var onOpenWordBook: (() -> Void)?
    var onOpenHistory: (() -> Void)?
    var onLiveTranslate: ((String) -> Void)?
    var onSourceLanguageChange: ((Language?) -> Void)?
    var onTargetLanguageChange: ((Language) -> Void)?
    var onEngineChange: ((PrimaryEngine?) -> Void)?
    var onStyleChange: ((TranslationStyle?) -> Void)?
    var onToggleCompare: (() -> Void)?
    var onQuickExplain: ((String, String) -> Void)?
    var onImportImage: ((NSImage) -> Void)?
    var onPinImage: ((NSImage, String) -> Void)?
    var onRestoreHistory: ((HistoryRecord) -> Void)?
    var onToggleSmartMerge: (() -> Void)?
    var onClear: (() -> Void)?

    private let settings: SettingsStore
    private let historyStore: HistoryStore
    private var panel: KeyableResultPanel?
    private var focusObservers: [NSObjectProtocol] = []
    /// 记录窗口当前是否已按内容扩展过（避免打断用户手动拖拽好的窗口尺寸）
    private var hasExpandedForContent = false

    init(settings: SettingsStore, historyStore: HistoryStore) {
        self.settings = settings
        self.historyStore = historyStore
        super.init()
    }

    deinit {
        for observer in focusObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    var diagContentView: NSView? {
        ensurePanel().contentView
    }

    private func ensurePanel() -> KeyableResultPanel {
        if let panel { return panel }
        let initialSize = WindowSize.small.size
        let panel = KeyableResultPanel(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
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
        panel.titlebarSeparatorStyle = .none
        // 挂载空 unifiedCompact 工具栏：系统原生将红绿灯垂直居中至距顶 20pt（与 40pt 工具栏 0px 精准对齐）
        panel.toolbar = NSToolbar(identifier: "SnapTranslatorMainToolbar")
        panel.toolbarStyle = .unifiedCompact
        panel.backgroundColor = .textBackgroundColor
        panel.isReleasedWhenClosed = false
        panel.onKeyShortcut = { [weak self] event in
            self?.handlePanelKeyEvent(event) ?? false
        }

        let hasRestoredFrame = panel.setFrameAutosaveName("SnapTranslatorResultPanel")
        if !hasRestoredFrame, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: visible.midX - initialSize.width / 2,
                y: visible.midY - initialSize.height / 2
            ))
        }

        panel.delegate = self
        let hosting = NSHostingView(
            rootView: ResultPanelView(
                model: model,
                settings: settings,
                historyStore: historyStore,
                onStartCapture: { [weak self] in self?.onStartCapture?() },
                onStartSilentOCR: { [weak self] in self?.onStartSilentOCR?() },
                onRecaptureLastRegion: { [weak self] in self?.onRecaptureLastRegion?() },
                onTranslateClipboard: { [weak self] in self?.onTranslateClipboard?() },
                onCollect: { [weak self] phrase, context in self?.onCollect?(phrase, context) },
                onRetry: { [weak self] in self?.onRetry?() },
                onClose: { [weak self] in self?.hide() },
                onTogglePin: { [weak self] in self?.togglePin() },
                onSwapLanguages: { [weak self] in self?.onSwapLanguages?() },
                onOpenWordBook: { [weak self] in self?.onOpenWordBook?() },
                onOpenHistory: { [weak self] in self?.onOpenHistory?() },
                onLiveTranslate: { [weak self] text in self?.onLiveTranslate?(text) },
                onSourceLanguageChange: { [weak self] lang in self?.onSourceLanguageChange?(lang) },
                onTargetLanguageChange: { [weak self] lang in self?.onTargetLanguageChange?(lang) },
                onEngineChange: { [weak self] engine in self?.onEngineChange?(engine) },
                onStyleChange: { [weak self] style in self?.onStyleChange?(style) },
                onToggleCompare: { [weak self] in self?.onToggleCompare?() },
                onQuickExplain: { [weak self] phrase, context in self?.onQuickExplain?(phrase, context) },
                onImportImage: { [weak self] image in self?.onImportImage?(image) },
                onPinImage: { [weak self] image, title in self?.onPinImage?(image, title) },
                onRestoreHistory: { [weak self] record in self?.onRestoreHistory?(record) },
                onToggleSmartMerge: { [weak self] in self?.onToggleSmartMerge?() },
                onClear: { [weak self] in self?.handleClearContent() }
            )
        )
        hosting.sizingOptions = []
        panel.contentView = hosting
        observeFocus(panel)
        self.panel = panel
        return panel
    }

    func show(near rect: CGRect?) {
        let panel = ensurePanel()
        panel.alphaValue = 1
        if model.hasContent && !hasExpandedForContent {
            applyDefaultWindowSize(force: true)
            hasExpandedForContent = true
        }
        if let rect {
            position(panel: panel, near: rect)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusSourceEditor()
    }

    /// 显式应用默认窗口大小（仅在首次有内容或用户在设置中修改「默认窗口大小」时触发）
    func applyDefaultWindowSize(force: Bool = false) {
        guard let panel else { return }
        guard force || model.hasContent else { return }
        let defaultSize = settings.defaultWindowSize.size
        let currentSize = panel.frame.size
        guard abs(currentSize.width - defaultSize.width) > 1
            || abs(currentSize.height - defaultSize.height) > 1 else { return }
        panel.setContentSize(defaultSize)
    }

    func handleClearContent() {
        SpeechManager.shared.stop()
        onClear?()
        model.reset()
        hasExpandedForContent = false
        guard let panel else { return }
        let smallSize = WindowSize.small.size
        if abs(panel.frame.size.width - smallSize.width) > 1
            || abs(panel.frame.size.height - smallSize.height) > 1 {
            panel.setContentSize(smallSize)
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func toggle() {
        if isVisible { hide() } else { show(near: nil) }
    }

    func applyPin(alwaysOnTop: Bool) {
        guard let panel else { return }
        panel.isFloatingPanel = alwaysOnTop
        panel.level = alwaysOnTop ? .floating : .normal
    }

    private func togglePin() {
        settings.alwaysOnTop.toggle()
        applyPin(alwaysOnTop: settings.alwaysOnTop)
    }

    // MARK: - 面板内快捷键盘流

    private func handlePanelKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // ESC：优先关闭 AI 速释浮层，否则隐藏面板
        if event.keyCode == 53 {
            if model.quickExplain != nil {
                model.quickExplain = nil
                return true
            }
            hide()
            return true
        }

        // ⌘1~4 切换页签
        if flags == .command {
            switch event.charactersIgnoringModifiers {
            case "1":
                if model.phase == .done || model.phase == .idle { model.tab = .recognize; return true }
            case "2":
                if model.phase == .done || model.phase == .idle { model.tab = .translation; return true }
            case "3":
                if model.phase == .done || model.phase == .idle { model.tab = .sideBySide; return true }
            case "4":
                if model.phase == .done || model.phase == .idle { model.tab = .oneToOne; return true }
            case "r":
                if model.image != nil || !model.sourceText.isEmpty {
                    onRetry?()
                    return true
                }
            case "v":
                // 非编辑态下直接 ⌘V 粘贴剪贴板图片触发 OCR+翻译
                let isEditingText = (panel?.firstResponder as? NSTextView)?.isEditable == true
                if !isEditingText, let image = NSPasteboard.readImage() {
                    onImportImage?(image)
                    return true
                }
            case "=", "+":
                settings.increaseFontSize()
                model.showNotice("字号 \(Int(settings.textFontSize)) pt", kind: .info, duration: 1.4)
                return true
            case "-":
                settings.decreaseFontSize()
                model.showNotice("字号 \(Int(settings.textFontSize)) pt", kind: .info, duration: 1.4)
                return true
            case "0":
                settings.resetFontSize()
                model.showNotice("字号已重置为 \(Int(settings.textFontSize)) pt", kind: .info, duration: 1.4)
                return true
            default:
                break
            }
        }

        // ⌘⇧+（部分键盘需要 Shift 触发 +）同样支持放大字号
        if flags == [.command, .shift], event.charactersIgnoringModifiers == "+" {
            settings.increaseFontSize()
            model.showNotice("字号 \(Int(settings.textFontSize)) pt", kind: .info, duration: 1.4)
            return true
        }

        // ⌘⇧C：快速复制原文
        if flags == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "c" {
            if !model.sourceText.isEmpty {
                NSPasteboard.writeString(model.sourceText)
                model.showNotice("已复制原文", kind: .success)
                return true
            }
        }
        return false
    }

    private func focusSourceEditor() {
        guard let panel else { return }
        DispatchQueue.main.async { [weak panel] in
            guard let panel, panel.isVisible else { return }
            guard panel.firstResponder === panel else { return }
            guard let editor = Self.findEditableTextView(in: panel.contentView) else { return }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeFirstResponder(editor)
        }
    }

    private static func findEditableTextView(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable, textView.isSelectable {
            return textView
        }
        for sub in view.subviews {
            if let found = findEditableTextView(in: sub) { return found }
        }
        return nil
    }

    private func position(panel: NSPanel, near rect: CGRect) {
        let panelSize = panel.frame.size
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(rect) }) ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame

        var origin = NSPoint(x: rect.maxX + 12, y: rect.midY - panelSize.height / 2)
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

    private func observeFocus(_ panel: NSPanel) {
        let center = NotificationCenter.default
        focusObservers.append(
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: panel, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setAlpha(self?.settings.unfocusedOpacity ?? 0.3)
                }
            }
        )
        focusObservers.append(
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: panel, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.setAlpha(1)
                }
            }
        )
    }

    private func setAlpha(_ value: Double) {
        guard let panel, abs(panel.alphaValue - value) > 0.005 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = value
        }
    }
}

private final class KeyableResultPanel: NSPanel {
    var onKeyShortcut: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if onKeyShortcut?(event) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onKeyShortcut?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}
