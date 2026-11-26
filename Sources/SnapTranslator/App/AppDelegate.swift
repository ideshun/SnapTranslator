import AppKit
import Combine
import PDFKit
import SnapTranslatorCore
import SwiftUI
import UniformTypeIdentifiers

/// 轻量应用中枢：装配各领域模块、细粒度响应设置变更、提供系统右键 Services 入口与窗口协调
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var wordBook = WordBookStore()
    private lazy var historyStore = HistoryStore()
    private let hotkeyManager = HotkeyManager()
    private let captureCoordinator = CaptureCoordinator()
    private let translationHost = TranslationHostWindowController()
    private let pinController = PinImageWindowController()

    private lazy var panelController = ResultPanelController(settings: settings, historyStore: historyStore)
    private lazy var pipeline = TranslationPipeline(
        settings: settings,
        historyStore: historyStore,
        translationHost: translationHost,
        model: panelController.model
    )
    private var menuBarController: MenuBarController?

    private var wordBookWindow: NSWindow?
    private var historyWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var subscriptions: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 仅用公开 UserDefaults 缩短 Tooltip 弹出延迟，绝不调用不安全的私有反射 API
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 150])
        UserDefaults.standard.set(150, forKey: "NSInitialToolTipDelay")

        setupMenuBar()
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        NSApp.servicesProvider = self

        wirePanelActions()
        wireCaptureCoordinator()
        observeSettingsFineGrained()
        registerAllHotkeys()

        UserDefaults.standard.set(true, forKey: "st.hasLaunched")
        panelController.show(near: nil)
        NSApp.activate(ignoringOtherApps: true)
        translationHost.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            panelController.show(near: nil)
        }
        return true
    }

    // MARK: - macOS 系统右键 Services 入口（「使用 SnapTranslator 翻译」，零辅助功能权限）

    @objc func translateFromService(
        _ pboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let text = pboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { return }
        panelController.show(near: nil)
        pipeline.translateTextImmediately(text, addHistory: true)
    }

    // MARK: - 模块装配

    private func setupMenuBar() {
        let controller = MenuBarController(
            settings: settings,
            actions: .init(
                startCapture: { [weak self] in self?.startCapture(defaultAction: .translate) },
                recaptureLastRegion: { [weak self] in self?.recaptureLastRegion() },
                startSilentOCR: { [weak self] in self?.startCapture(defaultAction: .silentOCR) },
                translateClipboard: { [weak self] in self?.translateClipboard() },
                togglePanel: { [weak self] in self?.panelController.toggle() },
                toggleOfflineMode: { [weak self] in self?.toggleOfflineMode() },
                toggleDock: { [weak self] in self?.toggleDock() },
                openHistory: { [weak self] in self?.openHistory() },
                openWordBook: { [weak self] in self?.openWordBook() },
                openSettings: { [weak self] in self?.openSettings() },
                showAbout: { NSApp.orderFrontStandardAboutPanel(nil) }
            )
        )
        controller.setup()
        menuBarController = controller
    }

    private func wirePanelActions() {
        panelController.onStartCapture = { [weak self] in
            self?.startCapture(defaultAction: .translate)
        }
        panelController.onStartSilentOCR = { [weak self] in
            self?.startCapture(defaultAction: .silentOCR)
        }
        panelController.onRecaptureLastRegion = { [weak self] in
            self?.recaptureLastRegion()
        }
        panelController.onTranslateClipboard = { [weak self] in
            self?.translateClipboard()
        }
        panelController.onCollect = { [weak self] phrase, context in
            self?.collectWord(phrase, context: context)
        }
        panelController.onRetry = { [weak self] in
            self?.pipeline.retry()
        }
        panelController.onSwapLanguages = { [weak self] in
            self?.pipeline.swapLanguages()
        }
        panelController.onOpenWordBook = { [weak self] in
            self?.openWordBook()
        }
        panelController.onOpenHistory = { [weak self] in
            self?.openHistory()
        }
        panelController.onLiveTranslate = { [weak self] text in
            self?.pipeline.scheduleLiveTranslate(text: text)
        }
        panelController.onSourceLanguageChange = { [weak self] lang in
            self?.pipeline.setSourceLanguage(lang)
        }
        panelController.onTargetLanguageChange = { [weak self] lang in
            self?.pipeline.setTargetLanguage(lang)
        }
        panelController.onEngineChange = { [weak self] engine in
            self?.pipeline.setEngineOverride(engine)
        }
        panelController.onStyleChange = { [weak self] style in
            self?.pipeline.setStyleOverride(style)
        }
        panelController.onToggleCompare = { [weak self] in
            self?.pipeline.toggleCompareMode()
        }
        panelController.onQuickExplain = { [weak self] phrase, context in
            self?.pipeline.quickExplain(phrase: phrase, context: context)
        }
        panelController.onImportImage = { [weak self] image in
            self?.handleImportedImage(image)
        }
        panelController.onPinImage = { [weak self] image, title in
            self?.pinController.pin(image: image, title: title)
        }
        panelController.onRestoreHistory = { [weak self] record in
            self?.restoreHistoryRecord(record)
        }
        panelController.onToggleSmartMerge = { [weak self] in
            self?.pipeline.toggleSmartMerge()
        }
        panelController.onClear = { [weak self] in
            self?.pipeline.cancelOngoingWork()
        }
    }

    private func wireCaptureCoordinator() {
        captureCoordinator.onCaptured = { [weak self] image, rect, action in
            self?.handleCaptured(image: image, rect: rect, action: action)
        }
        captureCoordinator.onPermissionDenied = { [weak self] in
            self?.notifyPermissionDenied()
        }
        captureCoordinator.onCancelled = {}
        captureCoordinator.onDirectCaptureFailed = {}
    }

    /// 细粒度订阅设置项：仅对真正变化的属性做出精准响应，彻底告别修改透明度时重注册热键与重置窗口大小
    private func observeSettingsFineGrained() {
        Publishers.MergeMany(
            settings.$hotkeyCapture.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$hotkeyRecapture.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$hotkeyTogglePanel.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$hotkeySilentOCR.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$hotkeyTranslateClipboard.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.registerAllHotkeys()
            self?.menuBarController?.refreshMenu()
        }
        .store(in: &subscriptions)

        settings.$alwaysOnTop
            .dropFirst()
            .sink { [weak self] pinned in
                self?.panelController.applyPin(alwaysOnTop: pinned)
                self?.applyPopupWindowLevels()
            }
            .store(in: &subscriptions)

        settings.$defaultWindowSize
            .dropFirst()
            .sink { [weak self] _ in
                self?.panelController.applyDefaultWindowSize(force: false)
            }
            .store(in: &subscriptions)

        settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in
                self?.historyStore.trim(limit: limit)
            }
            .store(in: &subscriptions)

        Publishers.Merge(
            settings.$showInDock.dropFirst().map { _ in () },
            settings.$offlineOnlyMode.dropFirst().map { _ in () }
        )
        .sink { [weak self] in
            self?.menuBarController?.refreshMenu()
        }
        .store(in: &subscriptions)
    }

    private func registerAllHotkeys() {
        hotkeyManager.unregisterAll()
        var failed: [String] = []

        if !hotkeyManager.register(.capture, spec: settings.hotkeyCapture, handler: { [weak self] in
            Task { @MainActor in self?.startCapture(defaultAction: .translate) }
        }) { failed.append("截屏翻译(\(settings.hotkeyCapture.display))") }

        if !hotkeyManager.register(.recapture, spec: settings.hotkeyRecapture, handler: { [weak self] in
            Task { @MainActor in self?.recaptureLastRegion() }
        }) { failed.append("重截上次区域(\(settings.hotkeyRecapture.display))") }

        if !hotkeyManager.register(.togglePanel, spec: settings.hotkeyTogglePanel, handler: { [weak self] in
            Task { @MainActor in self?.panelController.toggle() }
        }) { failed.append("显示/隐藏窗口(\(settings.hotkeyTogglePanel.display))") }

        if !hotkeyManager.register(.silentOCR, spec: settings.hotkeySilentOCR, handler: { [weak self] in
            Task { @MainActor in self?.startCapture(defaultAction: .silentOCR) }
        }) { failed.append("静默截屏 OCR(\(settings.hotkeySilentOCR.display))") }

        if !hotkeyManager.register(.translateClipboard, spec: settings.hotkeyTranslateClipboard, handler: { [weak self] in
            Task { @MainActor in self?.translateClipboard() }
        }) { failed.append("翻译剪贴板(\(settings.hotkeyTranslateClipboard.display))") }

        if !failed.isEmpty {
            AppLogger.hotkey.warning("部分快捷键注册失败: \(failed.joined(separator: ", "), privacy: .public)")
            panelController.model.showNotice("部分快捷键冲突：\(failed.first ?? "")", kind: .warning, duration: 4.0)
        }
    }

    // MARK: - 核心动作

    private func startCapture(defaultAction: CaptureAction) {
        captureCoordinator.begin(
            defaultAction: defaultAction,
            refineMode: settings.captureRefineToolbar,
            excludeOwnWindows: settings.hideWindowOnCapture
        )
    }

    private func recaptureLastRegion() {
        guard let rect = CaptureCoordinator.adjustedLastRect() else {
            startCapture(defaultAction: .translate)
            return
        }
        captureCoordinator.capture(
            rect: rect,
            action: .translate,
            excludeOwnWindows: settings.hideWindowOnCapture
        )
    }

    private func translateClipboard() {
        if let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            panelController.show(near: nil)
            pipeline.translateTextImmediately(text, addHistory: true)
            return
        }
        if let image = NSPasteboard.readImage() {
            handleImportedImage(image)
            return
        }
        HUDNotifier.shared.show("剪贴板中暂无可翻译的文本或图片", systemImage: "info.circle.fill")
    }

    private func handleImportedImage(_ image: NSImage) {
        panelController.show(near: nil)
        pipeline.processCapturedImage(image, preserveTab: false, addHistory: true)
    }

    private func handleCaptured(image: NSImage, rect: CGRect, action: CaptureAction) {
        switch action {
        case .translate:
            panelController.show(near: rect)
            pipeline.processCapturedImage(image, preserveTab: false, addHistory: true)

        case .silentOCR:
            Task { [weak self] in
                guard let self else { return }
                if let text = await self.pipeline.silentOCR(image: image) {
                    let count = text.count
                    HUDNotifier.shared.show("已识别并复制 \(count) 字到剪贴板", systemImage: "doc.on.clipboard.fill")
                } else {
                    HUDNotifier.shared.show("未识别到文字", systemImage: "exclamationmark.triangle.fill")
                }
            }

        case .pinImage:
            pinController.pin(image: image, near: rect, title: "截图贴图")

        case .saveImage:
            saveScreenshotPNG(image)
        }
    }

    private func saveScreenshotPNG(_ image: NSImage) {
        guard let png = image.pngData() else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        savePanel.nameFieldStringValue = "SnapTranslator-\(formatter.string(from: Date())).png"
        NSApp.activate(ignoringOtherApps: true)
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try png.write(to: url, options: .atomic)
                Task { @MainActor in
                    HUDNotifier.shared.show("已保存截图：\(url.lastPathComponent)", systemImage: "checkmark.circle.fill")
                }
            } catch {
                NSAlert(error: error).runModal()
            }
        }
    }

    private func toggleDock() {
        settings.showInDock.toggle()
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
        menuBarController?.refreshMenu()
    }

    private func toggleOfflineMode() {
        settings.offlineOnlyMode.toggle()
        menuBarController?.refreshMenu()
        panelController.model.showNotice(
            settings.offlineOnlyMode ? "已开启纯离线隐私模式" : "已关闭纯离线模式",
            kind: .info
        )
    }

    private func restoreHistoryRecord(_ record: HistoryRecord) {
        let img = historyStore.image(for: record)
        panelController.model.restore(record: record, image: img)
        panelController.show(near: nil)
    }

    private func collectWord(_ phrase: String, context: String) {
        let model = panelController.model
        let source = model.sourceLanguage?.rawValue ?? "auto"
        let target = model.targetLanguage.rawValue
        // 若收藏整句则顺带保存当前整句译文；若是划词速释则 context 为释义
        let autoTranslation = (phrase == model.sourceText) ? model.translatedText : ""
        if wordBook.add(
            phrase: phrase,
            context: context,
            translation: autoTranslation,
            source: source,
            target: target
        ) {
            model.showNotice("已收藏「\(String(phrase.prefix(12)))」", kind: .success)
            model.selectedText = ""
            model.leftSelectedText = ""
        } else {
            model.showNotice("收藏失败，请重试", kind: .error)
        }
    }

    // MARK: - 功能窗口管理

    private func openHistory() {
        let view = HistoryView(store: historyStore) { [weak self] record in
            self?.restoreHistoryRecord(record)
        }
        showWindow(key: \AppDelegate.historyWindow, title: "识别历史", size: NSSize(width: 760, height: 480), content: view)
    }

    private func openWordBook() {
        let view = WordBookView(store: wordBook) { [weak self] text, src, tgt in
            guard let self else { return "" }
            return await self.pipeline.translateForWordBook(text: text, source: src, target: tgt)
        }
        showWindow(key: \AppDelegate.wordBookWindow, title: "生词本", size: NSSize(width: 760, height: 480), content: view)
    }

    private func openSettings() {
        let view = SettingsView(settings: settings) { [weak self] in
            self?.prepareAppleLanguages()
        }
        showWindow(key: \AppDelegate.settingsWindow, title: "设置", size: NSSize(width: 720, height: 560), content: view)
    }

    private func showWindow<Content: View>(
        key: ReferenceWritableKeyPath<AppDelegate, NSWindow?>,
        title: String,
        size: NSSize,
        content: Content
    ) {
        if let existing = self[keyPath: key] {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .textBackgroundColor
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = settings.alwaysOnTop ? .modalPanel : .normal
        self[keyPath: key] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyPopupWindowLevels() {
        let level: NSWindow.Level = settings.alwaysOnTop ? .modalPanel : .normal
        for window in [wordBookWindow, historyWindow, settingsWindow].compactMap({ $0 }) {
            window.level = level
        }
    }

    private func prepareAppleLanguages() {
        let urls = [
            URL(string: "x-apple.systempreferences:com.apple.Translation-Settings.extension"),
            URL(string: "x-apple.systempreferences:com.apple.preference.general?Translation"),
            URL(string: "x-apple.systempreferences:com.apple.preference.general"),
        ]
        var opened = false
        for url in urls.compactMap({ $0 }) {
            if NSWorkspace.shared.open(url) {
                opened = true
                break
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

    private func notifyPermissionDenied() {
        let alert = NSAlert()
        alert.messageText = "需要屏幕录制权限"
        alert.informativeText = "请在 系统设置 → 隐私与安全性 → 屏幕录制 中勾选 SnapTranslator，然后重启应用。"
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - 界面诊断（--ui-diag）

    func runUIDiagnostic() -> Int32 {
        let model = panelController.model
        print("== UI 诊断开始 ==")

        handleCaptured(
            image: Self.makeDiagTestImage(),
            rect: NSRect(x: 120, y: 480, width: 600, height: 240),
            action: .translate
        )

        let deadline = Date().addingTimeInterval(60)
        loop: while Date() < deadline {
            switch model.phase {
            case .done, .failed: break loop
            default: RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
            }
        }

        if case .failed(let message) = model.phase {
            print("RESULT phase=failed message=\(message)")
        }
        print(String(
            format: "RESULT phase=%@ tab=%@ srcChars=%d dstChars=%d provider=%@ srcLang=%@",
            "\(model.phase)", model.tab.rawValue, model.sourceText.count, model.translatedText.count,
            model.providerName, model.sourceLanguage?.rawValue ?? "nil"
        ))
        guard case .done = model.phase, !model.sourceText.isEmpty else { return 1 }

        var failures: Int32 = 0
        let checks: [(PanelTab, String, String)] = [
            (.recognize, "识别", "DIAGNOSTIC"),
            (.translation, "翻译", String(model.translatedText.prefix(6))),
            (.sideBySide, "对照", String(model.translatedText.prefix(6))),
        ]
        for (tab, name, needle) in checks {
            model.tab = tab
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.6))
            let text = Self.pdfText(of: panelController.diagContentView)
            let hit = !needle.isEmpty && text.contains(needle)
            print("TAB \(name) pdfChars=\(text.count) contains(\(needle))=\(hit)")
            if !hit { failures += 1 }
        }
        model.tab = .oneToOne
        RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.8))
        let oneToOnePdf = Self.pdfDataLength(of: panelController.diagContentView)
        print("TAB 对比 pdfBytes=\(oneToOnePdf)")
        if oneToOnePdf < 1000 { failures += 1 }

        print("== UI 诊断结束：\(failures == 0 ? "全部通过" : "\(failures) 项失败") ==")
        return failures
    }

    private static func makeDiagTestImage() -> NSImage {
        let width = 600
        let height = 240
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return NSImage(size: NSSize(width: width, height: height)) }

        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        ("DIAGNOSTIC Hello World" as NSString).draw(
            at: NSPoint(x: 24, y: 170),
            withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .bold), .foregroundColor: NSColor.black]
        )
        ("这是界面诊断的中文测试句子，用于验证整体流程。" as NSString).draw(
            at: NSPoint(x: 24, y: 100),
            withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.black]
        )
        NSGraphicsContext.restoreGraphicsState()

        guard let cg = ctx.makeImage() else { return NSImage(size: NSSize(width: width, height: height)) }
        return NSImage(cgImage: cg, size: NSSize(width: width, height: height))
    }

    private static func pdfText(of view: NSView?) -> String {
        guard let view else { return "" }
        view.layoutSubtreeIfNeeded()
        let data = view.dataWithPDF(inside: view.bounds)
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else { return "" }
        return page.string ?? ""
    }

    private static func pdfDataLength(of view: NSView?) -> Int {
        guard let view else { return 0 }
        view.layoutSubtreeIfNeeded()
        return view.dataWithPDF(inside: view.bounds).count
    }
}
