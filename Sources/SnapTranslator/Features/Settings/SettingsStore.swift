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
        unfocusedOpacity = defaults.object(forKey: "st.unfocusedOpacity") as? Double ?? 0.3
        launchAtLogin = defaults.bool(forKey: "st.launchAtLogin")
        showInDock = defaults.object(forKey: "st.showInDock") as? Bool ?? true
        hotkeyCapture = Self.loadHotkey("st.hotkey.capture")
            ?? HotkeySpec(keyCode: 1, modifiers: HotkeySpec.optionModifier) // ⌥S
        hotkeyRecapture = Self.loadHotkey("st.hotkey.recapture")
            ?? HotkeySpec(keyCode: 1, modifiers: HotkeySpec.optionShiftModifier) // ⌥⇧S
        hotkeyTogglePanel = Self.loadHotkey("st.hotkey.toggle")
            ?? HotkeySpec(keyCode: 17, modifiers: HotkeySpec.optionModifier) // ⌥T
        primaryEngine = PrimaryEngine(rawValue: defaults.string(forKey: "st.engine.primary") ?? "") ?? .openai
        openaiBaseURL = defaults.string(forKey: "st.openai.baseURL") ?? "https://open.bigmodel.cn/api/paas/v4"
        openaiModel = defaults.string(forKey: "st.openai.model") ?? "glm-5.2"
        openaiAPIKey = KeychainStore.get("st.openai.key") ?? ""
        deeplAPIKey = KeychainStore.get("st.deepl.key") ?? ""
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
            // 非 .app bundle（如 swift run）下注册登录项必然失败，记录即可
            NSLog("登录项设置失败 launchAtLogin=%@ error=%@",
                  String(launchAtLogin), error.localizedDescription)
        }
    }
}
