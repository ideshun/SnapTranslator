import AppKit
import Combine
import ServiceManagement

/// 面板页签标识（放在 Core 以便 SettingsStore 直接持久化）
public enum PanelTab: String, CaseIterable, Codable, Identifiable, Sendable {
    case recognize = "识别"
    case translation = "翻译"
    case sideBySide = "对照"
    case oneToOne = "对比"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .recognize: return "text.viewfinder"
        case .translation: return "character.bubble"
        case .sideBySide: return "rectangle.split.2x1"
        case .oneToOne: return "sparkles.rectangle.stack"
        }
    }

    public var tooltip: String {
        switch self {
        case .recognize: return "识别：提取截图原文 (⌘1)"
        case .translation: return "翻译：双栏实时翻译 (⌘2)"
        case .sideBySide: return "对照：原图与译文对照 (⌘3)"
        case .oneToOne: return "对比：1:1 原图覆盖翻译 (⌘4)"
        }
    }
}

/// 截图显示方式
public enum ScreenshotDisplayMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case adaptiveWidth = "adaptiveWidth"
    case original = "original"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .adaptiveWidth: return "自适应宽度（完整适应面板）"
        case .original: return "原图（1:1 原始尺寸，可滚动）"
        }
    }

    public var fitsToViewport: Bool {
        self == .adaptiveWidth
    }
}

/// 默认窗口大小选项
public enum WindowSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case small = "small"
    case medium = "medium"
    case large = "large"
    case xlarge = "xlarge"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .small: return "小 (680×520)"
        case .medium: return "中 (880×680)"
        case .large: return "大 (1280×800)"
        case .xlarge: return "超大 (1920×1080)"
        }
    }

    public var size: CGSize {
        switch self {
        case .small: return CGSize(width: 680, height: 520)
        case .medium: return CGSize(width: 880, height: 680)
        case .large: return CGSize(width: 1280, height: 800)
        case .xlarge: return CGSize(width: 1920, height: 1080)
        }
    }
}

/// 全部用户偏好：
/// - UserDefaults 持久化，API Key 走 Keychain（并做 350ms 防抖写入，避免打字逐字符刷写 Keychain）
/// - 废弃旧版容易混淆的 sourceHint，统一使用 persistentSourceLanguage
/// - 细粒度分组发布，避免修改透明度或输入 Key 时误触发窗口重置或热键重注册
@MainActor
public final class SettingsStore: ObservableObject {
    private let defaults: UserDefaults
    private var keychainDebounceTasks: [String: Task<Void, Never>] = [:]

    // MARK: - 通用

    @Published public var targetLanguage: Language {
        didSet { defaults.set(targetLanguage.rawValue, forKey: "st.targetLanguage") }
    }
    /// 设置页持久锁定的源语言；nil 表示自动检测
    @Published public var persistentSourceLanguage: Language? {
        didSet { defaults.set(persistentSourceLanguage?.rawValue ?? "", forKey: "st.manualSource") }
    }
    @Published public var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: "st.alwaysOnTop") }
    }
    @Published public var hideWindowOnCapture: Bool {
        didSet { defaults.set(hideWindowOnCapture, forKey: "st.hideWindowOnCapture") }
    }
    /// 正文字体大小（11pt ~ 26pt，默认 14pt，支持设置调节与 ⌘+/⌘-/⌘0 实时缩放）
    public static let minTextFontSize: Double = 11
    public static let maxTextFontSize: Double = 26
    public static let defaultTextFontSize: Double = 14

    /// 界面控件字体大小（页签、分栏标题、状态栏、列表等，11pt ~ 18pt，默认 13pt）
    public static let minUIFontSize: Double = 11
    public static let maxUIFontSize: Double = 18
    public static let defaultUIFontSize: Double = 13

    @Published public var textFontSize: Double {
        didSet {
            let clamped = min(max(textFontSize, Self.minTextFontSize), Self.maxTextFontSize)
            if clamped != textFontSize {
                textFontSize = clamped
                return
            }
            defaults.set(textFontSize, forKey: "st.textFontSize")
        }
    }
    @Published public var uiFontSize: Double {
        didSet {
            let clamped = min(max(uiFontSize, Self.minUIFontSize), Self.maxUIFontSize)
            if clamped != uiFontSize {
                uiFontSize = clamped
                return
            }
            defaults.set(uiFontSize, forKey: "st.uiFontSize")
        }
    }
    /// 失焦透明度
    @Published public var unfocusedOpacity: Double {
        didSet { defaults.set(unfocusedOpacity, forKey: "st.unfocusedOpacity") }
    }
    @Published public var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "st.launchAtLogin")
            applyLaunchAtLogin()
        }
    }
    @Published public var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "st.showInDock")
            applyShowInDock()
        }
    }
    @Published public var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: "st.historyLimit") }
    }
    @Published public var screenshotDisplayMode: ScreenshotDisplayMode {
        didSet { defaults.set(screenshotDisplayMode.rawValue, forKey: "st.screenshotDisplayMode") }
    }
    @Published public var defaultWindowSize: WindowSize {
        didSet { defaults.set(defaultWindowSize.rawValue, forKey: "st.defaultWindowSize") }
    }
    @Published public var defaultDoneTab: PanelTab {
        didSet { defaults.set(defaultDoneTab.rawValue, forKey: "st.defaultDoneTab") }
    }
    /// OCR 智能段落合并（消除 PDF/英文文档硬换行与连字符断裂）
    @Published public var ocrSmartMerge: Bool {
        didSet { defaults.set(ocrSmartMerge, forKey: "st.ocr.smartMerge") }
    }
    /// 框选后停留精调模式（可拖拽边角微调并选择 翻译/仅OCR/贴图/保存）
    @Published public var captureRefineToolbar: Bool {
        didSet { defaults.set(captureRefineToolbar, forKey: "st.capture.refineToolbar") }
    }

    // MARK: - 快捷键

    @Published public var hotkeyCapture: HotkeySpec {
        didSet { persistHotkey(hotkeyCapture, key: "st.hotkey.capture") }
    }
    @Published public var hotkeyRecapture: HotkeySpec {
        didSet { persistHotkey(hotkeyRecapture, key: "st.hotkey.recapture") }
    }
    @Published public var hotkeyTogglePanel: HotkeySpec {
        didSet { persistHotkey(hotkeyTogglePanel, key: "st.hotkey.toggle") }
    }
    @Published public var hotkeySilentOCR: HotkeySpec {
        didSet { persistHotkey(hotkeySilentOCR, key: "st.hotkey.silentOCR") }
    }
    @Published public var hotkeyTranslateClipboard: HotkeySpec {
        didSet { persistHotkey(hotkeyTranslateClipboard, key: "st.hotkey.translateClipboard") }
    }

    // MARK: - 引擎与 AI 预设

    public static let defaultOpenAIBaseURL = "https://open.bigmodel.cn/api/paas/v4"
    public static let defaultOpenAIModel = "glm-5.2"
    public static let defaultProxyHost = "127.0.0.1"
    public static let defaultProxyPort = "7890"

    /// 纯离线隐私模式：仅允许使用 Apple Vision + Apple 本地翻译，绝不发起任何云端请求
    @Published public var offlineOnlyMode: Bool {
        didSet {
            defaults.set(offlineOnlyMode, forKey: "st.engine.offlineOnly")
            EngineBreaker.shared.resetAll()
        }
    }
    @Published public var primaryEngine: PrimaryEngine {
        didSet {
            defaults.set(primaryEngine.rawValue, forKey: "st.engine.primary")
            EngineBreaker.shared.resetAll()
        }
    }
    /// 双引擎并排对比时的副引擎
    @Published public var compareSecondaryEngine: PrimaryEngine {
        didSet { defaults.set(compareSecondaryEngine.rawValue, forKey: "st.engine.compareSecondary") }
    }
    @Published public var translationStyle: TranslationStyle {
        didSet { defaults.set(translationStyle.rawValue, forKey: "st.engine.style") }
    }
    @Published public var aiProfiles: [AIProfile] {
        didSet { persistProfiles() }
    }
    @Published public var activeAIProfileID: String {
        didSet {
            defaults.set(activeAIProfileID, forKey: "st.ai.activeProfileID")
            syncActiveProfileKey()
            EngineBreaker.shared.resetAll()
        }
    }
    /// 当前选中 AI 预设的 API Key（防抖写入 Keychain）
    @Published public var activeAIAPIKey: String {
        didSet {
            let keyName = activeAIProfile.keychainKey
            scheduleKeychainWrite(value: activeAIAPIKey, key: keyName)
            EngineBreaker.shared.resetAll()
        }
    }
    @Published public var deeplAPIKey: String {
        didSet {
            scheduleKeychainWrite(value: deeplAPIKey, key: "st.deepl.key")
            EngineBreaker.shared.resetAll()
        }
    }

    // MARK: - 网络代理（仅云引擎）

    @Published public var proxyEnabled: Bool {
        didSet {
            defaults.set(proxyEnabled, forKey: "st.proxy.enabled")
            EngineBreaker.shared.resetAll()
        }
    }
    @Published public var proxyHost: String {
        didSet {
            defaults.set(proxyHost, forKey: "st.proxy.host")
            EngineBreaker.shared.resetAll()
        }
    }
    @Published public var proxyPort: String {
        didSet {
            defaults.set(proxyPort, forKey: "st.proxy.port")
            EngineBreaker.shared.resetAll()
        }
    }

    public var activeAIProfile: AIProfile {
        aiProfiles.first(where: { $0.id == activeAIProfileID })
            ?? aiProfiles.first
            ?? AIProfile.builtInTemplates[0]
    }

    public var engineProxy: EngineProxySettings {
        EngineProxySettings(enabled: proxyEnabled, host: proxyHost, port: Int(proxyPort))
    }

    public var hasConfiguredAI: Bool {
        let profile = activeAIProfile
        guard !profile.model.isEmpty else { return false }
        return !profile.requiresAPIKey || !activeAIAPIKey.isEmpty
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // 保留旧版本一次性迁移，确保老用户无痛升级
        if !defaults.bool(forKey: "st.cleanup.manualSource.v2") {
            defaults.set(true, forKey: "st.cleanup.manualSource.v2")
            defaults.removeObject(forKey: "st.manualSource")
        }
        if !defaults.bool(forKey: "st.migrated.glm52") {
            defaults.set(true, forKey: "st.migrated.glm52")
            if defaults.string(forKey: "st.engine.primary") == nil
                || defaults.string(forKey: "st.engine.primary") == PrimaryEngine.auto.rawValue {
                defaults.set(PrimaryEngine.openai.rawValue, forKey: "st.engine.primary")
            }
        }

        targetLanguage = Language(rawValue: defaults.string(forKey: "st.targetLanguage") ?? "") ?? .zhHans
        persistentSourceLanguage = defaults.string(forKey: "st.manualSource").flatMap(Language.init(rawValue:))
        alwaysOnTop = defaults.object(forKey: "st.alwaysOnTop") as? Bool ?? true
        hideWindowOnCapture = defaults.object(forKey: "st.hideWindowOnCapture") as? Bool ?? true
        defaultDoneTab = PanelTab(rawValue: defaults.string(forKey: "st.defaultDoneTab") ?? "") ?? .oneToOne
        let savedFontSize = defaults.object(forKey: "st.textFontSize") as? Double ?? Self.defaultTextFontSize
        textFontSize = min(max(savedFontSize, Self.minTextFontSize), Self.maxTextFontSize)
        let savedUIFontSize = defaults.object(forKey: "st.uiFontSize") as? Double ?? Self.defaultUIFontSize
        uiFontSize = min(max(savedUIFontSize, Self.minUIFontSize), Self.maxUIFontSize)
        unfocusedOpacity = defaults.object(forKey: "st.unfocusedOpacity") as? Double ?? 0.3
        launchAtLogin = defaults.bool(forKey: "st.launchAtLogin")
        showInDock = defaults.object(forKey: "st.showInDock") as? Bool ?? true
        historyLimit = defaults.object(forKey: "st.historyLimit") as? Int ?? 30
        screenshotDisplayMode = ScreenshotDisplayMode(
            rawValue: defaults.string(forKey: "st.screenshotDisplayMode") ?? ""
        ) ?? .adaptiveWidth
        defaultWindowSize = WindowSize(rawValue: defaults.string(forKey: "st.defaultWindowSize") ?? "") ?? .medium
        ocrSmartMerge = defaults.object(forKey: "st.ocr.smartMerge") as? Bool ?? true
        captureRefineToolbar = defaults.object(forKey: "st.capture.refineToolbar") as? Bool ?? false

        hotkeyCapture = Self.loadHotkey("st.hotkey.capture", from: defaults)
            ?? HotkeySpec(keyCode: 1, modifiers: HotkeySpec.optionModifier) // ⌥S
        hotkeyRecapture = Self.loadHotkey("st.hotkey.recapture", from: defaults)
            ?? HotkeySpec(keyCode: 1, modifiers: HotkeySpec.optionShiftModifier) // ⌥⇧S
        hotkeyTogglePanel = Self.loadHotkey("st.hotkey.toggle", from: defaults)
            ?? HotkeySpec(keyCode: 17, modifiers: HotkeySpec.optionModifier) // ⌥T
        hotkeySilentOCR = Self.loadHotkey("st.hotkey.silentOCR", from: defaults)
            ?? HotkeySpec(keyCode: 31, modifiers: HotkeySpec.optionShiftModifier) // ⌥⇧O
        hotkeyTranslateClipboard = Self.loadHotkey("st.hotkey.translateClipboard", from: defaults)
            ?? HotkeySpec(keyCode: 9, modifiers: HotkeySpec.optionShiftModifier) // ⌥⇧V

        offlineOnlyMode = defaults.bool(forKey: "st.engine.offlineOnly")
        var loadedEngine = PrimaryEngine(rawValue: defaults.string(forKey: "st.engine.primary") ?? "") ?? .openai
        if defaults.string(forKey: "st.engine.primary") == "offline" {
            loadedEngine = .apple
            defaults.set(PrimaryEngine.apple.rawValue, forKey: "st.engine.primary")
        }
        primaryEngine = loadedEngine
        compareSecondaryEngine = PrimaryEngine(rawValue: defaults.string(forKey: "st.engine.compareSecondary") ?? "") ?? .apple
        translationStyle = TranslationStyle(rawValue: defaults.string(forKey: "st.engine.style") ?? "") ?? .general

        // 加载 AI 预设列表（若无持久化列表，迁移旧 openaiBaseURL/openaiModel 至默认智谱预设）
        let loadedProfiles: [AIProfile]
        if let data = defaults.data(forKey: "st.ai.profiles"),
           let decoded = try? JSONDecoder().decode([AIProfile].self, from: data),
           !decoded.isEmpty {
            loadedProfiles = decoded
        } else {
            let legacyURL = defaults.string(forKey: "st.openai.baseURL") ?? Self.defaultOpenAIBaseURL
            let legacyModel = defaults.string(forKey: "st.openai.model") ?? Self.defaultOpenAIModel
            var first = AIProfile.builtInTemplates[0]
            first.baseURL = legacyURL
            first.model = legacyModel
            loadedProfiles = [first]
        }
        aiProfiles = loadedProfiles
        let savedActiveID = defaults.string(forKey: "st.ai.activeProfileID")
        let resolvedActiveID = loadedProfiles.contains(where: { $0.id == savedActiveID })
            ? (savedActiveID ?? loadedProfiles[0].id)
            : loadedProfiles[0].id
        activeAIProfileID = resolvedActiveID

        let initialProfile = loadedProfiles.first(where: { $0.id == resolvedActiveID }) ?? loadedProfiles[0]
        activeAIAPIKey = KeychainStore.get(initialProfile.keychainKey) ?? ""
        deeplAPIKey = KeychainStore.get("st.deepl.key") ?? ""

        proxyEnabled = defaults.object(forKey: "st.proxy.enabled") as? Bool ?? false
        proxyHost = defaults.string(forKey: "st.proxy.host") ?? Self.defaultProxyHost
        proxyPort = defaults.string(forKey: "st.proxy.port") ?? Self.defaultProxyPort
    }

    // MARK: - 字体大小快捷调节

    public func increaseFontSize() {
        textFontSize = min(Self.maxTextFontSize, textFontSize + 1)
    }

    public func decreaseFontSize() {
        textFontSize = max(Self.minTextFontSize, textFontSize - 1)
    }

    public func resetFontSize() {
        textFontSize = Self.defaultTextFontSize
    }

    public func resetUIFontSize() {
        uiFontSize = Self.defaultUIFontSize
    }

    // MARK: - AI 预设管理

    public func updateActiveProfile(name: String? = nil, baseURL: String? = nil, model: String? = nil, requiresAPIKey: Bool? = nil) {
        guard let idx = aiProfiles.firstIndex(where: { $0.id == activeAIProfileID }) else { return }
        if let name { aiProfiles[idx].name = name }
        if let baseURL { aiProfiles[idx].baseURL = baseURL }
        if let model { aiProfiles[idx].model = model }
        if let requiresAPIKey { aiProfiles[idx].requiresAPIKey = requiresAPIKey }
        EngineBreaker.shared.resetAll()
    }

    public func addProfile(from template: AIProfile) {
        var copy = template
        if aiProfiles.contains(where: { $0.id == copy.id }) {
            copy.id = UUID().uuidString
        }
        aiProfiles.append(copy)
        activeAIProfileID = copy.id
    }

    public func deleteActiveProfile() {
        guard aiProfiles.count > 1,
              let idx = aiProfiles.firstIndex(where: { $0.id == activeAIProfileID })
        else { return }
        let removed = aiProfiles.remove(at: idx)
        KeychainStore.delete(removed.keychainKey)
        activeAIProfileID = aiProfiles[max(0, idx - 1)].id
    }

    /// 供 TranslationService 构建配置
    public func makeTranslationConfig(
        primaryOverride: PrimaryEngine? = nil,
        styleOverride: TranslationStyle? = nil,
        anchor: TranslationAnchor?
    ) -> TranslationService.Config {
        TranslationService.Config(
            primary: primaryOverride ?? primaryEngine,
            aiProfile: activeAIProfile,
            aiAPIKey: activeAIAPIKey,
            deeplAPIKey: deeplAPIKey,
            anchor: anchor,
            proxy: engineProxy,
            offlineOnly: offlineOnlyMode,
            style: styleOverride ?? translationStyle,
            useCache: true
        )
    }

    // MARK: - 私有持久化辅助

    private func syncActiveProfileKey() {
        let keyName = activeAIProfile.keychainKey
        let loaded = KeychainStore.get(keyName) ?? ""
        if activeAIAPIKey != loaded {
            activeAIAPIKey = loaded
        }
    }

    private func scheduleKeychainWrite(value: String, key: String) {
        keychainDebounceTasks[key]?.cancel()
        keychainDebounceTasks[key] = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            KeychainStore.set(value, forKey: key)
        }
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(aiProfiles) {
            defaults.set(data, forKey: "st.ai.profiles")
        }
    }

    private func persistHotkey(_ spec: HotkeySpec, key: String) {
        if let data = try? JSONEncoder().encode(spec) {
            defaults.set(data, forKey: key)
        }
    }

    private static func loadHotkey(_ key: String, from defaults: UserDefaults) -> HotkeySpec? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HotkeySpec.self, from: data)
    }

    private func applyShowInDock() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            AppLogger.app.warning("登录项设置失败: \(error.localizedDescription, privacy: .public)")
        }
    }
}
