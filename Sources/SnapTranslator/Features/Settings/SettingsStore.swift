import AppKit
import ServiceManagement

/// 全部用户偏好：UserDefaults 持久化，API Key 走 Keychain
@MainActor
final class SettingsStore: ObservableObject {
    private let defaults = UserDefaults.standard

    // MARK: - 通用

    @Published var targetLanguage: Language {
        didSet { defaults.set(targetLanguage.rawValue, forKey: "st.targetLanguage") }
    }
    /// 源语言提示，nil 表示自动检测
    @Published var sourceHint: Language? {
        didSet { defaults.set(sourceHint?.rawValue ?? "", forKey: "st.sourceHint") }
    }
    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: "st.alwaysOnTop") }
    }
    /// 截屏时先隐藏翻译面板，避免面板出现在截图中；取消框选时自动恢复
    @Published var hideWindowOnCapture: Bool {
        didSet { defaults.set(hideWindowOnCapture, forKey: "st.hideWindowOnCapture") }
    }
    /// 失焦时的面板透明度
    @Published var unfocusedOpacity: Double {
        didSet { defaults.set(unfocusedOpacity, forKey: "st.unfocusedOpacity") }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: "st.launchAtLogin")
            applyLaunchAtLogin()
        }
    }
    /// 是否在程序坞（Dock）中显示图标；关闭时纯菜单栏驻留
    @Published var showInDock: Bool {
        didSet {
            defaults.set(showInDock, forKey: "st.showInDock")
            applyShowInDock()
        }
    }
    /// 识别历史保存条数（0 表示不保存）
    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: "st.historyLimit") }
    }
    /// 截图在面板中的显示方式
    @Published var screenshotDisplayMode: ScreenshotDisplayMode {
        didSet { defaults.set(screenshotDisplayMode.rawValue, forKey: "st.screenshotDisplayMode") }
    }
    /// 默认窗口大小（宽度 x 高度）
    @Published var defaultWindowSize: WindowSize {
        didSet { defaults.set(defaultWindowSize.rawValue, forKey: "st.defaultWindowSize") }
    }
    /// 截图翻译完成后默认聚焦的页签
    @Published var defaultDoneTab: ResultModel.Tab {
        didSet { defaults.set(defaultDoneTab.rawValue, forKey: "st.defaultDoneTab") }
    }

    // MARK: - 快捷键

    @Published var hotkeyCapture: HotkeySpec {
        didSet { persistHotkey(hotkeyCapture, key: "st.hotkey.capture") }
    }
    @Published var hotkeyRecapture: HotkeySpec {
        didSet { persistHotkey(hotkeyRecapture, key: "st.hotkey.recapture") }
    }
    @Published var hotkeyTogglePanel: HotkeySpec {
        didSet { persistHotkey(hotkeyTogglePanel, key: "st.hotkey.toggle") }
    }

    // MARK: - 引擎

    /// 智谱 AI 默认接入点
    static let defaultOpenAIBaseURL = "https://open.bigmodel.cn/api/paas/v4"
    /// 智谱 AI 默认模型
    static let defaultOpenAIModel = "glm-5.2"
    /// 代理默认主机/端口
    static let defaultProxyHost = "127.0.0.1"
    static let defaultProxyPort = "7890"

    @Published var primaryEngine: PrimaryEngine {
        didSet { defaults.set(primaryEngine.rawValue, forKey: "st.engine.primary") }
    }
    @Published var openaiBaseURL: String {
        didSet { defaults.set(openaiBaseURL, forKey: "st.openai.baseURL") }
    }
    @Published var openaiModel: String {
        didSet { defaults.set(openaiModel, forKey: "st.openai.model") }
    }
    @Published var openaiAPIKey: String {
        didSet { KeychainStore.set(openaiAPIKey, forKey: "st.openai.key") }
    }
    @Published var deeplAPIKey: String {
        didSet { KeychainStore.set(deeplAPIKey, forKey: "st.deepl.key") }
    }

    // MARK: - 网络代理（仅云引擎）

    @Published var proxyEnabled: Bool {
        didSet { defaults.set(proxyEnabled, forKey: "st.proxy.enabled") }
    }
    @Published var proxyHost: String {
        didSet { defaults.set(proxyHost, forKey: "st.proxy.host") }
    }
    /// 端口以字符串存储，输入框可直接编辑
    @Published var proxyPort: String {
        didSet { defaults.set(proxyPort, forKey: "st.proxy.port") }
    }

    /// 供翻译服务使用的代理配置
    var engineProxy: EngineProxySettings {
        EngineProxySettings(enabled: proxyEnabled, host: proxyHost, port: Int(proxyPort))
    }

    init() {
        // 一次性迁移到 GLM-5.2：老用户若仍是旧默认 auto/旧 OpenAI 地址/旧模型，升级后自动切到 GLM
        if !defaults.bool(forKey: "st.migrated.glm52") {
            defaults.set(true, forKey: "st.migrated.glm52")
            if defaults.string(forKey: "st.engine.primary") == nil
                || defaults.string(forKey: "st.engine.primary") == PrimaryEngine.auto.rawValue {
                defaults.set(PrimaryEngine.openai.rawValue, forKey: "st.engine.primary")
            }
            if defaults.string(forKey: "st.openai.baseURL") == nil
                || defaults.string(forKey: "st.openai.baseURL") == "https://api.openai.com/v1" {
                defaults.set("https://open.bigmodel.cn/api/paas/v4", forKey: "st.openai.baseURL")
            }
            if defaults.string(forKey: "st.openai.model") == "gpt-4o-mini" {
                defaults.set("glm-5.2", forKey: "st.openai.model")
            }
        }
        targetLanguage = Language(rawValue: defaults.string(forKey: "st.targetLanguage") ?? "") ?? .zhHans
        sourceHint = defaults.string(forKey: "st.sourceHint").flatMap(Language.init(rawValue:))
        alwaysOnTop = defaults.object(forKey: "st.alwaysOnTop") as? Bool ?? true
        hideWindowOnCapture = defaults.object(forKey: "st.hideWindowOnCapture") as? Bool ?? true
        // 「1:1」tab 已改名「对比」，旧持久化值解码失败时回退默认
        defaultDoneTab = ResultModel.Tab(rawValue: defaults.string(forKey: "st.defaultDoneTab") ?? "") ?? .oneToOne
        unfocusedOpacity = defaults.object(forKey: "st.unfocusedOpacity") as? Double ?? 0.3
        launchAtLogin = defaults.bool(forKey: "st.launchAtLogin")
        showInDock = defaults.object(forKey: "st.showInDock") as? Bool ?? true
        historyLimit = defaults.object(forKey: "st.historyLimit") as? Int ?? 10
        screenshotDisplayMode = ScreenshotDisplayMode(
            rawValue: defaults.string(forKey: "st.screenshotDisplayMode") ?? ""
        ) ?? .adaptiveWidth
        defaultWindowSize = WindowSize(rawValue: defaults.string(forKey: "st.defaultWindowSize") ?? "") ?? .medium
        hotkeyCapture = Self.loadHotkey("st.hotkey.capture")
            ?? HotkeySpec(keyCode: 1, modifiers: HotkeySpec.optionModifier) // ⌥S
        hotkeyRecapture = Self.loadHotkey("st.hotkey.recapture")
            ?? HotkeySpec(keyCode: 1, modifiers: HotkeySpec.optionShiftModifier) // ⌥⇧S
        hotkeyTogglePanel = Self.loadHotkey("st.hotkey.toggle")
            ?? HotkeySpec(keyCode: 17, modifiers: HotkeySpec.optionModifier) // ⌥T
        primaryEngine = PrimaryEngine(rawValue: defaults.string(forKey: "st.engine.primary") ?? "") ?? .openai
        // 引擎合并迁移：原「仅离线」并入「Apple 系统翻译（离线优先）」
        if defaults.string(forKey: "st.engine.primary") == "offline" {
            primaryEngine = .apple
            defaults.set(PrimaryEngine.apple.rawValue, forKey: "st.engine.primary")
        }
        openaiBaseURL = defaults.string(forKey: "st.openai.baseURL") ?? Self.defaultOpenAIBaseURL
        openaiModel = defaults.string(forKey: "st.openai.model") ?? Self.defaultOpenAIModel
        openaiAPIKey = KeychainStore.get("st.openai.key") ?? ""
        deeplAPIKey = KeychainStore.get("st.deepl.key") ?? ""
        proxyEnabled = defaults.object(forKey: "st.proxy.enabled") as? Bool ?? false
        proxyHost = defaults.string(forKey: "st.proxy.host") ?? Self.defaultProxyHost
        proxyPort = defaults.string(forKey: "st.proxy.port") ?? Self.defaultProxyPort
    }

    private func persistHotkey(_ spec: HotkeySpec, key: String) {
        do {
            defaults.set(try JSONEncoder().encode(spec), forKey: key)
        } catch {
            NSLog("快捷键持久化失败 key=%@ error=%@", key, error.localizedDescription)
        }
    }

    private static func loadHotkey(_ key: String) -> HotkeySpec? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(HotkeySpec.self, from: data)
        } catch {
            NSLog("快捷键读取失败 key=%@ error=%@", key, error.localizedDescription)
            return nil
        }
    }

    private func applyShowInDock() {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        if showInDock {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13, *) else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // 非 .app bundle（如 swift run）下注册登录项失败，记录即可
            NSLog("登录项设置失败 launchAtLogin=%@ error=%@",
                  String(launchAtLogin), error.localizedDescription)
        }
    }
}

/// 截图显示方式
enum ScreenshotDisplayMode: String, CaseIterable, Codable, Identifiable {
    /// 自适应宽度：缩放至面板宽度 100% 显示（现有模式）
    case adaptiveWidth = "adaptiveWidth"
    /// 原图：不缩放，按图片原始尺寸显示（超出部分滚动）
    case original = "original"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .adaptiveWidth: return "自适应宽度（宽度 100%）"
        case .original: return "原图（不缩放）"
        }
    }
}

/// 默认窗口大小选项
enum WindowSize: String, CaseIterable, Codable, Identifiable {
    case small = "small"      // 680 x 520
    case medium = "medium"    // 880 x 680
    case large = "large"      // 1280 x 800
    case xlarge = "xlarge"    // 1920 x 1080

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .small: return "小 (680×520)"
        case .medium: return "中 (880×680)"
        case .large: return "大 (1280×800)"
        case .xlarge: return "超大 (1920×1080)"
        }
    }

    var size: CGSize {
        switch self {
        case .small: return CGSize(width: 680, height: 520)
        case .medium: return CGSize(width: 880, height: 680)
        case .large: return CGSize(width: 1280, height: 800)
        case .xlarge: return CGSize(width: 1920, height: 1080)
        }
    }
}
