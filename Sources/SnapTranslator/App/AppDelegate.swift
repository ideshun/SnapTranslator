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
    private lazy var translationHost = TranslationHostWindowController()
    private var wordBookWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var settingsSubscription: AnyCancellable?

    /// 重试所需的最近一次请求（含 OCR 行位置，用于翻译覆盖定位）
    private var lastRequest: (image: NSImage, sourceText: String, ocrLines: [(text: String, rect: CGRect)])?
    /// 实时翻译请求序号，用于丢弃过期请求结果
    private var liveTranslateGeneration: UInt = 0
    /// 实时翻译防抖任务（编辑停顿后触发，避免每敲一个字都请求）
    private var liveTranslateDebounce: Task<Void, Never>?
    /// 普通翻译请求序号，用于丢弃过期请求结果
    private var translateGeneration: UInt = 0
    /// 当前正在进行的翻译请求数（用于协调 translationHost 的隐藏时机）
    private var activeTranslationCount = 0

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

        // 每次启动都展示结果面板（默认聚焦「翻译」页签），支持输入内容实时翻译
        UserDefaults.standard.set(true, forKey: "st.hasLaunched")
        panelController.show(near: nil)

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

        // 预创建并显示翻译锚点窗口，确保 TranslationSession 随时可用
        translationHost.show()
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

        let historyItem = NSMenuItem(
            title: "识别历史",
            action: #selector(showHistory),
            keyEquivalent: "h"
        )
        historyItem.target = self
        fileMenu.addItem(historyItem)

        // 编辑菜单：提供标准的撤销/剪切/复制/粘贴/全选，
        // 缺少该菜单时 ⌘X/⌘C/⌘V/⌘A 等快捷键在任何文本框内都不可用
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenuItem.submenu = editMenu

        let editItems: [(String, Selector, String)] = [
            ("撤销", Selector(("undo:")), "z"),
            ("重做", Selector(("redo:")), "Z"),
            ("剪切", #selector(NSText.cut(_:)), "x"),
            ("复制", #selector(NSText.copy(_:)), "c"),
            ("粘贴", #selector(NSText.paste(_:)), "v"),
            ("全选", #selector(NSText.selectAll(_:)), "a"),
        ]
        for (index, (title, action, key)) in editItems.enumerated() {
            if index == 2 {
                editMenu.addItem(.separator())
            }
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }

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
        // 使用可变长度确保图标在所有场景下都能显示
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // 依次尝试多个 SF Symbol，最后用程序化绘制兜底
            let symbols = [
                "character.bubble.fill",
                "character.bubble",
                "translate",
                "text.bubble",
                "globe",
                "doc.text.magnifyingglass",
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
            // 设置合适的尺寸确保图标在菜单栏中清晰可见
            image?.size = NSSize(width: 18, height: 18)
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "SnapTranslator"
            // 确保按钮能正确接收点击
            button.isEnabled = true
        }
        statusItem = item
        item.menu = buildMenu()
    }

    /// 程序化绘制菜单栏图标（SF Symbol 全部加载失败时的兜底）
    private static func makeFallbackIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        // 画一个圆角气泡 + 两条文字线（template 模式由系统自动适配颜色）
        NSColor.labelColor.set()
        let bubble = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: 14, height: 12), xRadius: 3, yRadius: 3)
        bubble.fill()
        // 气泡尾巴
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 6, y: 14))
        tail.line(to: NSPoint(x: 4, y: 17))
        tail.line(to: NSPoint(x: 10, y: 14))
        tail.close()
        tail.fill()
        image.unlockFocus()
        image.isTemplate = true
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

        let historyItem = NSMenuItem(
            title: "识别历史",
            action: #selector(showHistory),
            keyEquivalent: ""
        )
        historyItem.target = self
        menu.addItem(historyItem)

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
        // 设置变化时同步应用默认窗口大小
        panelController.applyDefaultWindowSize()
        statusItem?.menu = buildMenu()

        // 按历史设置限制历史条数
        trimHistory()
    }

    /// 根据设置修剪历史记录
    private func trimHistory() {
        let limit = settings.historyLimit
        if limit > 0 && panelController.model.history.count > limit {
            panelController.model.history = Array(panelController.model.history.prefix(limit))
        }
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
        panelController.onLiveTranslate = { [weak self] text in
            self?.liveTranslate(text: text)
        }
        panelController.onSourceLanguageChange = { [weak self] lang in
            self?.handleSourceLanguageChange(lang)
        }
        panelController.onTargetLanguageChange = { [weak self] lang in
            self?.handleTargetLanguageChange(lang)
        }
    }

    // MARK: - 语言切换

    /// 用户从状态栏选择源语言后：更新设置并重新翻译当前文本
    private func handleSourceLanguageChange(_ lang: Language?) {
        // 更新持久化设置
        settings.sourceHint = lang
        // 如有当前文本，重新翻译
        reTranslateCurrent()
    }

    /// 用户从状态栏选择目标语言后：更新设置并重新翻译当前文本
    private func handleTargetLanguageChange(_ lang: Language) {
        settings.targetLanguage = lang
        reTranslateCurrent()
    }

    /// 用当前源/目标语言设置重新翻译当前文本
    private func reTranslateCurrent() {
        let model = panelController.model
        guard !model.sourceText.isEmpty else { return }
        let image = model.image
        // 重置翻译状态（保留当前 tab）
        model.phase = .translating
        guard let image else {
            // 无图片时仅更新译文（可能来自实时翻译场景）
            let text = model.sourceText
            performDirectTranslate(text: text)
            return
        }
        translate(text: model.sourceText, image: image, model: model, preserveTab: true, addHistory: false)
    }

    /// 无图片时的直接翻译（如实时翻译场景切换语种）
    private func performDirectTranslate(text: String) {
        let model = panelController.model
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let source = determineSourceLanguage(for: trimmed)
        let target = effectiveTargetLanguage(source: source)
        model.targetLanguage = target

        liveTranslateGeneration &+= 1
        let generation = liveTranslateGeneration
        activeTranslationCount += 1

        translationHost.show()
        let service = TranslationService(
            config: .init(
                primary: settings.primaryEngine,
                openaiBaseURL: settings.openaiBaseURL,
                openaiModel: settings.openaiModel,
                openaiAPIKey: settings.openaiAPIKey,
                deeplAPIKey: settings.deeplAPIKey,
                anchor: translationHost.anchor
            )
        )
        Task { [weak self, weak model] in
            guard let self, let model else { return }
            defer {
                self.activeTranslationCount -= 1
                if self.activeTranslationCount <= 0 {
                    self.activeTranslationCount = 0
                    self.translationHost.hide()
                }
            }
            guard generation == self.liveTranslateGeneration else { return }
            do {
                let (translation, provider) = try await service.translate(
                    trimmed,
                    from: source,
                    to: target
                )
                guard generation == self.liveTranslateGeneration else { return }
                model.translatedText = translation
                model.providerName = provider
                model.sourceLanguage = source
                model.phase = .done
            } catch {
                guard generation == self.liveTranslateGeneration else { return }
                model.phase = .failed("翻译失败：\(error.localizedDescription)")
            }
        }
    }

    /// 实时翻译：翻译页签左侧原文编辑后即时翻译，右侧实时更新
    private func liveTranslate(text: String) {
        let model = panelController.model
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 清空时立即清空译文，无需等待防抖
        if trimmed.isEmpty {
            liveTranslateDebounce?.cancel()
            liveTranslateGeneration &+= 1
            model.translatedText = ""
            model.collectNotice = ""
            return
        }

        // 编辑停顿 400ms 后再翻译，避免连续输入时反复请求
        liveTranslateDebounce?.cancel()
        liveTranslateDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.performLiveTranslate(text: trimmed)
        }
    }

    /// 实际执行实时翻译请求（防抖后调用）
    private func performLiveTranslate(text: String) {
        let model = panelController.model
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            model.translatedText = ""
            model.collectNotice = ""
            return
        }
        // 同步源文本（编辑视图已更新 model.sourceText，这里仅确保一致）
        model.sourceText = text
        // 源语言判定
        let source = determineSourceLanguage(for: trimmed)
        // 若源语言与目标语言相同，自动切到英文
        let target = effectiveTargetLanguage(source: source)
        model.targetLanguage = target
        // 生成序号，仅最新一次请求的结果生效（防止旧请求覆盖新输入）
        liveTranslateGeneration &+= 1
        let generation = liveTranslateGeneration
        activeTranslationCount += 1

        translationHost.show()
        let service = TranslationService(
            config: .init(
                primary: settings.primaryEngine,
                openaiBaseURL: settings.openaiBaseURL,
                openaiModel: settings.openaiModel,
                openaiAPIKey: settings.openaiAPIKey,
                deeplAPIKey: settings.deeplAPIKey,
                anchor: translationHost.anchor
            )
        )
        Task { [weak self, weak model] in
            guard let self, let model else { return }
            defer {
                self.activeTranslationCount -= 1
                if self.activeTranslationCount <= 0 {
                    self.activeTranslationCount = 0
                    self.translationHost.hide()
                }
            }
            // 仅当仍是最新请求时才更新结果，旧请求直接丢弃
            guard generation == self.liveTranslateGeneration else { return }
            do {
                let (translation, provider) = try await service.translate(
                    trimmed,
                    from: source,
                    to: target
                )
                // 请求期间可能又有新编辑，再次校验后才更新
                guard generation == self.liveTranslateGeneration else { return }
                model.translatedText = translation
                model.providerName = provider
                model.sourceLanguage = source
                model.collectNotice = ""
            } catch {
                guard generation == self.liveTranslateGeneration else { return }
                model.translatedText = ""
                model.collectNotice = "实时翻译失败"
                Task { [weak model] in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    model?.collectNotice = ""
                }
            }
        }
    }

    /// 交换默认源/目标语言方向（如英译中 ↔ 中译英）
    /// 对下次截屏生效；同时更新当前面板中的语言显示
    @objc private func swapLanguages() {
        let model = panelController.model
        // 源语言：优先用已识别到的源语言，其次用设置里的 sourceHint，兜底英文
        let currentSource = model.sourceLanguage ?? settings.sourceHint ?? .en
        // 目标语言：使用面板上当前显示的实际目标语言（可能已被自动调整）
        let currentTarget = model.targetLanguage
        guard currentSource != currentTarget else {
            model.collectNotice = "源语言和目标语言相同，无需切换"
            Task { [weak model] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                model?.collectNotice = ""
            }
            return
        }

        // 交换持久化默认方向：新源 = 原目标，新目标 = 原源
        settings.sourceHint = currentTarget
        settings.targetLanguage = currentSource
        // 同时更新面板显示
        model.sourceLanguage = currentTarget
        model.targetLanguage = currentSource
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

    @objc private func showHistory() {
        let model = panelController.model
        // 显示面板并切到历史查看
        if !panelController.isVisible {
            panelController.show(near: nil)
        }
        if !model.history.isEmpty {
            model.phase = .idle  // 让历史在 idle 态显示
        }
    }

    @objc private func openWordBook() {
        guard let wordBook else {
            presentErrorAlert("生词本不可用", error: nil)
            return
        }
        let view = WordBookView(
            store: wordBook,
            onTranslate: { [weak self] text in
                guard let self else { return "" }
                return await self.translateForWordBook(text: text)
            }
        )
        showWindow(
            key: \AppDelegate.wordBookWindow,
            title: "生词本",
            content: view
        )
    }

    /// 生词本界面调用的翻译
    private func translateForWordBook(text: String) async -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let source = determineSourceLanguage(for: trimmed)
        let target = effectiveTargetLanguage(source: source)

        translationHost.show()
        activeTranslationCount += 1
        defer {
            activeTranslationCount -= 1
            if activeTranslationCount <= 0 {
                activeTranslationCount = 0
                translationHost.hide()
            }
        }

        let service = TranslationService(
            config: .init(
                primary: settings.primaryEngine,
                openaiBaseURL: settings.openaiBaseURL,
                openaiModel: settings.openaiModel,
                openaiAPIKey: settings.openaiAPIKey,
                deeplAPIKey: settings.deeplAPIKey,
                anchor: translationHost.anchor
            )
        )
        do {
            let (translation, _) = try await service.translate(
                trimmed,
                from: source,
                to: target
            )
            return translation
        } catch {
            return "翻译失败：\(error.localizedDescription)"
        }
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
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 480),
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
        lastRequest = (image, "", [])
        let model = panelController.model
        model.begin(image: image, target: settings.targetLanguage)
        panelController.show(near: rect)

        Task { [weak self] in
            guard let self else { return }
            do {
                // 始终包含全语种识别，避免 sourceHint 限制 OCR 导致中文等语言无法识别
                let languages = Self.allRecognitionLanguages(hint: self.settings.sourceHint)
                let result = try await self.ocrService.recognize(image, languages: languages)
                guard !result.fullText.isEmpty else {
                    model.failed("未识别到文字，请调整区域后重试")
                    return
                }
                let ocrLines = result.lines.map { (text: $0.text, rect: $0.boundingBox) }
                model.recognized(text: result.fullText, lines: ocrLines)
                self.lastRequest = (image, result.fullText, ocrLines)
                self.translate(text: result.fullText, image: image, model: model)
            } catch {
                model.failed("OCR 失败：\(error.localizedDescription)")
            }
        }
    }

    /// 构建 OCR 识别语言集：始终包含默认全语种，sourceHint 仅作优先级前置
    private static func allRecognitionLanguages(hint: Language?) -> [String] {
        var languages = VisionOCRService.defaultRecognitionLanguages
        if let hintCode = hint?.visionCode, !languages.contains(hintCode) {
            languages.insert(hintCode, at: 0)
        }
        return languages
    }

    /// 若检测到的源语言与目标语言相同，自动切换目标为英文
    /// 例如用户默认目标为中文，截图中文内容时自动改为翻译到英文
    private func effectiveTargetLanguage(source: Language?) -> Language {
        let target = settings.targetLanguage
        guard let source, source == target else { return target }
        // 源语言 == 目标语言，自动切换到英文作为翻译目标
        return .en
    }

    /// 确定源语言：用户手动选择优先，未选择时自动检测
    private func determineSourceLanguage(for text: String) -> Language? {
        if let hint = settings.sourceHint {
            return hint
        }
        return LanguageDetector.detect(text)
    }

    private func retryTranslation() {
        guard let last = lastRequest, !last.sourceText.isEmpty else {
            panelController.show(near: nil)
            return
        }
        let model = panelController.model
        model.recognized(text: last.sourceText, lines: last.ocrLines)
        panelController.show(near: nil)
        translate(text: last.sourceText, image: last.image, model: model)
    }

    private func translate(
        text: String,
        image: NSImage,
        model: ResultModel,
        preserveTab: Bool = false,
        addHistory: Bool = true
    ) {
        // 确保翻译锚点窗口可见，TranslationSession 才能可靠触发
        translationHost.show()
        // 源语言判定：用户手动选择优先，未选择时自动检测
        let source = determineSourceLanguage(for: text)
        // 若源语言与目标语言相同（如截图中文但目标也是中文），自动改为翻译到英文
        let target = effectiveTargetLanguage(source: source)
        // 生成序号，仅最新一次请求的结果生效（防止旧请求覆盖新输入）
        translateGeneration &+= 1
        let generation = translateGeneration
        activeTranslationCount += 1

        let service = TranslationService(
            config: .init(
                primary: settings.primaryEngine,
                openaiBaseURL: settings.openaiBaseURL,
                openaiModel: settings.openaiModel,
                openaiAPIKey: settings.openaiAPIKey,
                deeplAPIKey: settings.deeplAPIKey,
                anchor: translationHost.anchor
            )
        )
        // 更新面板中的实际目标语言（可能已被 effectiveTargetLanguage 自动调整）
        model.targetLanguage = target
        Task { [weak self] in
            guard let self else { return }
            defer {
                self.activeTranslationCount -= 1
                if self.activeTranslationCount <= 0 {
                    self.activeTranslationCount = 0
                    self.translationHost.hide()
                }
            }
            do {
                let (translation, provider) = try await service.translate(
                    text,
                    from: source,
                    to: target
                )
                guard generation == self.translateGeneration else { return }
                model.finished(
                    translation: translation,
                    provider: provider,
                    source: source,
                    preserveTab: preserveTab,
                    addHistory: addHistory
                )
                self.trimHistory()
            } catch {
                guard generation == self.translateGeneration else { return }
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
            model.leftSelectedText = ""
            Task { [weak model] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                model?.collectNotice = ""
            }
        } else {
            model.collectNotice = "收藏失败，请重试"
        }
    }

    /// 触发 Apple 翻译语言包下载：调起系统设置翻译界面
    private func prepareAppleLanguages() {
        // 尝试多种系统设置 URL 以兼容不同 macOS 版本
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.Translation-Settings.extension"),
            URL(string: "x-apple.systempreferences:com.apple.preference.general?Translation"),
            URL(string: "x-apple.systempreferences:com.apple.preference.general"),
        ]
        var opened = false
        for url in urls {
            if let url {
                opened = NSWorkspace.shared.open(url)
                if opened { break }
            }
        }

        if !opened {
            let alert = NSAlert()
            alert.messageText = "无法打开系统翻译设置"
            alert.informativeText = "请手动前往 系统设置 → 通用 → 翻译 下载所需语言包。"
            alert.addButton(withTitle: "好的")
            alert.runModal()
        }
        translationHost.hide()
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
