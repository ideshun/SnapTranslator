import AppKit
import SnapTranslatorCore

/// 菜单栏图标与系统主菜单独立控制器
@MainActor
final class MenuBarController: NSObject {
    struct Actions {
        var startCapture: () -> Void
        var recaptureLastRegion: () -> Void
        var startSilentOCR: () -> Void
        var translateClipboard: () -> Void
        var togglePanel: () -> Void
        var toggleOfflineMode: () -> Void
        var toggleDock: () -> Void
        var openHistory: () -> Void
        var openWordBook: () -> Void
        var openSettings: () -> Void
        var showAbout: () -> Void
    }

    private let settings: SettingsStore
    private let actions: Actions
    private var statusItem: NSStatusItem?

    init(settings: SettingsStore, actions: Actions) {
        self.settings = settings
        self.actions = actions
        super.init()
    }

    func setup() {
        setupStatusItem()
        setupMainMenu()
    }

    func refreshMenu() {
        statusItem?.menu = buildStatusMenu()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let symbols = [
                "character.bubble.fill",
                "character.bubble",
                "translate",
                "text.bubble",
                "globe",
            ]
            var image: NSImage?
            for symbol in symbols {
                if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "SnapTranslator") {
                    image = img
                    break
                }
            }
            image?.isTemplate = true
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "SnapTranslator"
            button.isEnabled = true
        }
        statusItem = item
        item.menu = buildStatusMenu()
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let titleItem = NSMenuItem(title: "SnapTranslator", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)
        menu.addItem(.separator())

        menu.addItem(makeItem("截屏翻译（\(settings.hotkeyCapture.display)）", action: #selector(handleCapture)))
        menu.addItem(makeItem("重截上次区域（\(settings.hotkeyRecapture.display)）", action: #selector(handleRecapture)))
        menu.addItem(makeItem("静默截屏 OCR（\(settings.hotkeySilentOCR.display)）", action: #selector(handleSilentOCR)))
        menu.addItem(makeItem("翻译剪贴板（\(settings.hotkeyTranslateClipboard.display)）", action: #selector(handleTranslateClipboard)))
        menu.addItem(makeItem("显示/隐藏窗口（\(settings.hotkeyTogglePanel.display)）", action: #selector(handleTogglePanel)))

        menu.addItem(.separator())

        let offlineItem = makeItem("纯离线隐私模式", action: #selector(handleToggleOffline))
        offlineItem.state = settings.offlineOnlyMode ? .on : .off
        menu.addItem(offlineItem)

        let dockItem = makeItem("在程序坞中显示", action: #selector(handleToggleDock))
        dockItem.state = settings.showInDock ? .on : .off
        menu.addItem(dockItem)

        menu.addItem(.separator())

        menu.addItem(makeItem("识别历史", action: #selector(handleOpenHistory)))
        menu.addItem(makeItem("生词本", action: #selector(handleOpenWordBook)))
        menu.addItem(makeItem("设置…", action: #selector(handleOpenSettings), keyEquivalent: ","))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 SnapTranslator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(makeItem("关于 SnapTranslator", action: #selector(handleShowAbout)))
        appMenu.addItem(.separator())
        appMenu.addItem(makeItem("设置…", action: #selector(handleOpenSettings), keyEquivalent: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "退出 SnapTranslator", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu

        let captureItem = makeItem("截屏翻译", action: #selector(handleCapture), keyEquivalent: "s")
        captureItem.keyEquivalentModifierMask = [.option]
        fileMenu.addItem(captureItem)

        let recaptureItem = makeItem("重截上次区域", action: #selector(handleRecapture), keyEquivalent: "s")
        recaptureItem.keyEquivalentModifierMask = [.option, .shift]
        fileMenu.addItem(recaptureItem)

        let silentOCRItem = makeItem("静默截屏 OCR", action: #selector(handleSilentOCR), keyEquivalent: "o")
        silentOCRItem.keyEquivalentModifierMask = [.option, .shift]
        fileMenu.addItem(silentOCRItem)

        let clipItem = makeItem("翻译剪贴板", action: #selector(handleTranslateClipboard), keyEquivalent: "v")
        clipItem.keyEquivalentModifierMask = [.option, .shift]
        fileMenu.addItem(clipItem)

        let toggleItem = makeItem("显示/隐藏窗口", action: #selector(handleTogglePanel), keyEquivalent: "t")
        toggleItem.keyEquivalentModifierMask = [.option]
        fileMenu.addItem(toggleItem)

        fileMenu.addItem(.separator())
        fileMenu.addItem(makeItem("识别历史", action: #selector(handleOpenHistory), keyEquivalent: "h"))
        fileMenu.addItem(makeItem("生词本", action: #selector(handleOpenWordBook)))

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu
        editMenu.addItem(NSMenuItem(title: "撤销", action: Selector(("undo:")), keyEquivalent: "z"))
        editMenu.addItem(NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "Z"))
        editMenu.addItem(.separator())
        editMenu.addItem(NSMenuItem(title: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(NSMenuItem(title: "最小化", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))
        windowMenu.addItem(NSMenuItem(title: "缩放", action: #selector(NSWindow.zoom(_:)), keyEquivalent: ""))

        NSApp.mainMenu = mainMenu
    }

    private func makeItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    @objc private func handleCapture() { actions.startCapture() }
    @objc private func handleRecapture() { actions.recaptureLastRegion() }
    @objc private func handleSilentOCR() { actions.startSilentOCR() }
    @objc private func handleTranslateClipboard() { actions.translateClipboard() }
    @objc private func handleTogglePanel() { actions.togglePanel() }
    @objc private func handleToggleOffline() { actions.toggleOfflineMode() }
    @objc private func handleToggleDock() { actions.toggleDock() }
    @objc private func handleOpenHistory() { actions.openHistory() }
    @objc private func handleOpenWordBook() { actions.openWordBook() }
    @objc private func handleOpenSettings() { actions.openSettings() }
    @objc private func handleShowAbout() { actions.showAbout() }
}
