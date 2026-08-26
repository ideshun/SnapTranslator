import AppKit
import Combine
import SwiftUI

/// 应用中枢：菜单栏、快捷键、流程编排（截屏 → OCR → 翻译 → 面板）
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let settings = SettingsStore()
    private var wordBook: WordBookStore?
    private let hotkeyManager = HotkeyManager()
    private let captureCoordinator = CaptureCoordinator()
    private let ocrService = VisionOCRService()
    private lazy var panelController = ResultPanelController(settings: settings)
    private var wordBookWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var settingsSubscription: AnyCancellable?

    /// 重试所需的最近一次请求
    private var lastRequest: (image: NSImage, sourceText: String)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        wordBook = WordBookStore()

        // 菜单栏图标必须在任何窗口创建前设置，确保可靠显示
        setupStatusItem()

        // 按设置恢复程序坞显隐
        applyDockPolicy()

        // 设置主菜单（程序坞图标模式下左上角显示应用名和菜单）
        setupMainMenu()

        wirePanelActions()
        applySettings()

        // 首次启动展示结果面板（空闲态），让用户明确看到应用已就绪
        if !UserDefaults.standard.bool(forKey: "st.hasLaunched") {
            UserDefaults.standard.set(true, forKey: "st.hasLaunched")
            panelController.show(near: nil)
        }

        settingsSubscription = settings.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.applySettings()
            }

        captureCoordinator.onCaptured = { [weak self] image, rect in
            self?.handleCaptured(image: image, rect: rect)
        }
        captureCoordinator.onPermissionDenied = { [weak self] in
            self?.notifyPermissionDenied()
        }

        // 激活应用，确保菜单栏图标和菜单立即可见
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 程序坞策略

    /// 根据设置切换程序坞显隐（LSUIElement 模式下需运行时切换激活策略）
    private func applyDockPolicy() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    // MARK: - 主菜单（左上角应用菜单）

    /// 设置主菜单：应用名 + 文件/编辑/窗口菜单
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // 应用菜单（点击左上角应用名显示）
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutItem = NSMenuItem(
            title: "关于 SnapTranslator",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        appMenu.addItem(aboutItem)

        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        appMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 SnapTranslator",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        // 文件菜单
        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "文件")
        fileMenuItem.submenu = fileMenu

        let captureItem = NSMenuItem(
            title: "截屏翻译",
            action: #selector(startCapture),
            keyEquivalent: "s"
        )
        captureItem.keyEquivalentModifierMask = [.option]
        captureItem.target = self
        fileMenu.addItem(captureItem)

        let recaptureItem = NSMenuItem(
            title: "重截上次区域",
            action: #selector(recaptureLastRegion),
            keyEquivalent: "s"
        )
        recaptureItem.keyEquivalentModifierMask = [.option, .shift]
        recaptureItem.target = self
        fileMenu.addItem(recaptureItem)

        let toggleItem = NSMenuItem(
            title: "显示/隐藏窗口",
            action: #selector(togglePanel),
            keyEquivalent: "t"
        )
        toggleItem.keyEquivalentModifierMask = [.option]
        toggleItem.target = self
        fileMenu.addItem(toggleItem)

        fileMenu.addItem(.separator())

        let wordBookItem = NSMenuItem(
            title: "生词本",
            action: #selector(openWordBook),
            keyEquivalent: ""
        )
        wordBookItem.target = self
        fileMenu.addItem(wordBookItem)

        // 窗口菜单
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "窗口")
        windowMenuItem.submenu = windowMenu

        let minimizeItem = NSMenuItem(
            title: "最小化",
            action: #selector(NSWindow.miniaturize(_:)),
            keyEquivalent: "m"
        )
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(
            title: "缩放",
            action: #selector(NSWindow.zoom(_:)),
            keyEquivalent: ""
        )
        windowMenu.addItem(zoomItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        // 使用固定长度确保图标始终可见
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            // 依次尝试多个 SF Symbol，最后用程序化绘制兜底
            let symbols = [
                "character.bubble.fill",
                "character.bubble",
                "translate",
                "text.bubble",
            ]
            var image: NSImage?
            for symbol in symbols {
                if let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "SnapTranslator") {
                    image = img
                    break
                }
            }
            if image == nil {
                // 程序化绘制一个简单的翻译气泡图标
                image = Self.makeFallbackIcon()
            }
            image?.isTemplate = true
            button.image = image
            button.toolTip = "SnapTranslator"
        }
        statusItem = item
        item.menu = buildMenu()
    }

    /// 程序化绘制菜单栏图标（SF Symbol 全部加载失败时的兜底）
    private static func makeFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        // 画一个圆角气泡 + 两条文字线
        NSColor.labelColor.set()
        let bubble = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 13), xRadius: 3, yRadius: 3)
        bubble.fill()
        // 气泡尾巴
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 5, y: 14))
        tail.line(to: NSPoint(x: 3, y: 17))
        tail.line(to: NSPoint(x: 9, y: 14))
        tail.close()
        tail.fill()
        // 文字线条
        NSColor.windowBackgroundColor.set()
        let line1 = NSRect(x: 4, y: 9, width: 10, height: 1.5)
        let line2 = NSRect(x: 4, y: 6, width: 7, height: 1.5)
        NSBezierPath(rect: line1).fill()
        NSBezierPath(rect: line2).fill()
        image.unlockFocus()
        return image
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        // 应用名标题
        let titleItem = NSMenuItem(title: "SnapTranslator", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(.separator())

        let captureItem = NSMenuItem(
            title: "截屏翻译（\(settings.hotkeyCapture.display)）",
            action: #selector(startCapture),
            keyEquivalent: ""
        )
        captureItem.target = self
        menu.addItem(captureItem)

        let recaptureItem = NSMenuItem(
            title: "重截上次区域（\(settings.hotkeyRecapture.display)）",
            action: #selector(recaptureLastRegion),
            keyEquivalent: ""
        )
        recaptureItem.target = self
        menu.addItem(recaptureItem)

        let toggleItem = NSMenuItem(
            title: "显示/隐藏窗口（\(settings.hotkeyTogglePanel.display)）",
            action: #selector(togglePanel),
            keyEquivalent: ""
        )
        toggleItem.target = self
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let dockItem = NSMenuItem(
            title: "在程序坞中显示",
            action: #selector(toggleDock),
            keyEquivalent: ""
        )
        dockItem.target = self
        dockItem.state = settings.showInDock ? .on : .off
        menu.addItem(dockItem)

        menu.addItem(.separator())

        let wordBookItem = NSMenuItem(
            title: "生词本",
            action: #selector(openWordBook),
            keyEquivalent: ""
        )
        wordBookItem.target = self
        menu.addItem(wordBookItem)

        let settingsItem = NSMenuItem(
            title: "设置…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "退出 SnapTranslator",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - 设置应用

    /// 快捷键 / 置顶 / 菜单文案 全量刷新
    private func applySettings() {
        hotkeyManager.unregisterAll()

        var allRegistered = true
        allRegistered = hotkeyManager.register(.capture, spec: settings.hotkeyCapture) { [weak self] in
            Task { @MainActor in self?.startCapture() }
        } && allRegistered
        allRegistered = hotkeyManager.register(.recapture, spec: settings.hotkeyRecapture) { [weak self] in
            Task { @MainActor in self?.recaptureLastRegion() }
        } && allRegistered
        allRegistered = hotkeyManager.register(.togglePanel, spec: settings.hotkeyTogglePanel) { [weak self] in
            Task { @MainActor in self?.togglePanel() }
        } && allRegistered

        if !allRegistered {
            presentErrorAlert("部分快捷键注册失败", error: nil)
        }

        panelController.applyPin(alwaysOnTop: settings.alwaysOnTop)
        statusItem?.menu = buildMenu()
    }

    private func wirePanelActions() {
        panelController.onCollect = { [weak self] phrase, context in
            self?.collectWord(phrase, context: context)
        }
        panelController.onRetry = { [weak self] in
            self?.retryTranslation()
        }
        panelController.onSwapLanguages = { [weak self] in
            self?.swapLanguages()
        }
        panelController.onOpenWordBook = { [weak self] in
            self?.openWordBook()
        }
    }

    /// 交换默认源/目标语言方向（如英译中 ↔ 中译英），下次截屏生效
    @objc private func swapLanguages() {
        let model = panelController.model
        // 源语言：优先用已识别到的源语言，其次用设置里的 sourceHint，再退化为目标语言
        let currentSource = model.sourceLanguage ?? settings.sourceHint ?? settings.targetLanguage
        let currentTarget = settings.targetLanguage
        guard currentSource != currentTarget else { return }

        // 交换持久化默认方向：新源 = 原目标，新目标 = 原源
        settings.sourceHint = currentTarget
        settings.targetLanguage = currentSource
        model.collectNotice = "已切换语向：\(currentTarget.displayName) → \(currentSource.displayName)"
        Task { [weak model] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            model?.collectNotice = ""
        }
    }

    // MARK: - 生命周期

    /// 关闭最后一个窗口不退出应用，保持菜单栏驻留
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// 点击程序坞图标时唤起结果面板，避免“不知道应用是否启动”
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            panelController.show(near: nil)
        }
        return true
    }

    // MARK: - 动作

    @objc private func toggleDock() {
        settings.showInDock.toggle()
        applyDockPolicy()
        // 切换后刷新菜单栏菜单中的勾选状态
        statusItem?.menu = buildMenu()
    }

    @objc private func startCapture() {
        captureCoordinator.begin()
    }

    @objc private func recaptureLastRegion() {
        guard let rect = CaptureCoordinator.adjustedLastRect() else {
            captureCoordinator.begin()
            return
        }
        captureCoordinator.capture(rect: rect)
    }

    @objc private func togglePanel() {
        panelController.toggle()
    }

    @objc private func openWordBook() {
        guard let wordBook else {
            presentErrorAlert("生词本不可用", error: nil)
            return
        }
        showWindow(
            key: \AppDelegate.wordBookWindow,
            title: "生词本",
            content: WordBookView(store: wordBook)
        )
    }

    @objc private func openSettings() {
        let view = SettingsView(settings: settings) { [weak self] in
            self?.prepareAppleLanguages()
        }
        showWindow(key: \AppDelegate.settingsWindow, title: "设置", content: view)
    }

    /// 显示（或前置）普通功能窗口
    private func showWindow<Content: View>(
        key: ReferenceWritableKeyPath<AppDelegate, NSWindow?>,
        title: String,
        content: Content
    ) {
        if let existing = self[keyPath: key] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        self[keyPath: key] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - 核心流程

    private func handleCaptured(image: NSImage, rect: CGRect) {
        lastRequest = (image, "")
        let model = panelController.model
        model.begin(image: image, target: settings.targetLanguage)
        panelController.show(near: rect)

        Task { [weak self] in
            guard let self else { return }
            do {
                let languages = self.settings.sourceHint.map { [$0.visionCode, "en-US"] }
                let result = try await self.ocrService.recognize(image, languages: languages)
                guard !result.fullText.isEmpty else {
                    model.failed("未识别到文字，请调整区域后重试")
                    return
                }
                model.recognized(text: result.fullText)
                self.lastRequest = (image, result.fullText)
                self.translate(text: result.fullText, image: image, model: model)
            } catch {
                model.failed("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    private func retryTranslation() {
        guard let last = lastRequest, !last.sourceText.isEmpty else {
            panelController.show(near: nil)
            return
        }
        let model = panelController.model
        model.recognized(text: last.sourceText)
        panelController.show(near: nil)
        translate(text: last.sourceText, image: last.image, model: model)
    }

    private func translate(text: String, image: NSImage, model: ResultModel) {
        let source = settings.sourceHint ?? LanguageDetector.detect(text)
        let service = TranslationService(
            config: .init(
                primary: settings.primaryEngine,
                openaiBaseURL: settings.openaiBaseURL,
                openaiModel: settings.openaiModel,
                openaiAPIKey: settings.openaiAPIKey,
                deeplAPIKey: settings.deeplAPIKey,
                anchor: panelController.anchor
            )
        )
        Task { [weak self] in
            do {
                let (translation, provider) = try await service.translate(
                    text,
                    from: source,
                    to: self?.settings.targetLanguage ?? .zhHans
                )
                model.finished(translation: translation, provider: provider, source: source)
            } catch {
                model.failed("翻译失败：\(error.localizedDescription)")
            }
        }
    }

    // MARK: - 生词收藏

    private func collectWord(_ phrase: String, context: String) {
        let model = panelController.model
        guard let wordBook else {
            model.collectNotice = "生词本不可用"
            return
        }
        let source = model.sourceLanguage?.rawValue ?? "auto"
        let target = model.targetLanguage.rawValue
        if wordBook.add(phrase: phrase, context: context, source: source, target: target) {
            model.collectNotice = "已收藏「\(String(phrase.prefix(10)))」"
            model.selectedText = ""
            Task { [weak model] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                model?.collectNotice = ""
            }
        } else {
            model.collectNotice = "收藏失败，请重试"
        }
    }

    /// 触发 Apple 翻译语言包下载（面板需可见才能弹下载确认框）
    private func prepareAppleLanguages() {
        panelController.show(near: nil)
        let anchor = panelController.anchor
        let source = settings.sourceHint
        let target = settings.targetLanguage
        Task {
            try? await anchor.prepareLanguages(source: source, target: target)
        }
    }

    // MARK: - 提示

    private func notifyPermissionDenied() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在 系统设置 → 隐私与安全性 → 屏幕录制 中勾选 SnapTranslator，然后重启应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func presentErrorAlert(_ message: String, error: Error?) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = error?.localizedDescription ?? "可能是快捷键与其他应用冲突，请在设置中更换键位。"
        alert.runModal()
    }
}
