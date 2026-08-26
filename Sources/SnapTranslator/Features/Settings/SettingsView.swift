import SwiftUI

/// 设置窗口：通用 / 快捷键 / 引擎 三个标签页
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore
    let onPrepareAppleLanguages: () -> Void

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label("通用", systemImage: "gearshape") }
            hotkeyTab
                .tabItem { Label("快捷键", systemImage: "keyboard") }
            engineTab
                .tabItem { Label("引擎", systemImage: "globe") }
        }
        .frame(width: 480, height: 440)
    }

    private var generalTab: some View {
        Form {
            Picker("目标语言", selection: $settings.targetLanguage) {
                ForEach(Language.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            Picker("源语言", selection: $settings.sourceHint) {
                Text("自动检测").tag(Language?.none)
                ForEach(Language.allCases) { language in
                    Text(language.displayName).tag(Language?.some(language))
                }
            }
            Toggle("在程序坞中显示图标", isOn: $settings.showInDock)
            Toggle("结果窗口置顶", isOn: $settings.alwaysOnTop)
            HStack {
                Text("失焦透明度")
                Slider(value: $settings.unfocusedOpacity, in: 0.1...0.9, step: 0.05)
                Text("\(Int(settings.unfocusedOpacity * 100))%")
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
                    .foregroundStyle(.secondary)
            }
            Toggle("登录时自动启动", isOn: $settings.launchAtLogin)
        }
        .formStyle(.grouped)
        .padding(1)
    }

    private var hotkeyTab: some View {
        Form {
            hotkeyRow(title: "截屏翻译", spec: $settings.hotkeyCapture)
            hotkeyRow(title: "重截上次区域", spec: $settings.hotkeyRecapture)
            hotkeyRow(title: "显示/隐藏窗口", spec: $settings.hotkeyTogglePanel)
            Text("快捷键需包含 ⌘/⌥/⌃ 至少一个修饰键；点击输入框后按下新组合键即可录入，按 ESC 取消。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(1)
    }

    private func hotkeyRow(title: String, spec: Binding<HotkeySpec>) -> some View {
        HStack {
            Text(title)
            Spacer()
            HotkeyRecorder(spec: spec)
                .frame(width: 140, height: 26)
        }
    }

    private var engineTab: some View {
        Form {
            Picker("主引擎", selection: $settings.primaryEngine) {
                ForEach(PrimaryEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
            Section("OpenAI 兼容接口") {
                TextField("Base URL（如 https://api.openai.com/v1）", text: $settings.openaiBaseURL)
                TextField("模型", text: $settings.openaiModel)
                SecureField("API Key", text: $settings.openaiAPIKey)
            }
            Section("DeepL") {
                SecureField("API Key（Free 档以 :fx 结尾）", text: $settings.deeplAPIKey)
            }
            Section {
                Button("下载 Apple 翻译语言包") {
                    onPrepareAppleLanguages()
                }
                Text("Apple 系统翻译完全离线，需 macOS 15+。首次使用前点按上方按钮下载语言包。「仅离线」模式只使用本地 Apple 翻译，永不联网；其余模式在 Apple 不可用或失败时会自动降级到云引擎（Google/OpenAI/DeepL，需联网）。Google 免费接口无需任何配置。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(1)
    }
}
