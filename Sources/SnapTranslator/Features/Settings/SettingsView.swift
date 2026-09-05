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
        .frame(width: 480, height: 560)
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
            // 默认窗口大小设置
            Picker("默认窗口大小", selection: $settings.defaultWindowSize) {
                ForEach(WindowSize.allCases) { size in
                    Text(size.displayName).tag(size)
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

            // 截图显示方式
            Picker("截图显示方式", selection: $settings.screenshotDisplayMode) {
                ForEach(ScreenshotDisplayMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }

            // 截图翻译完成后默认聚焦的页签
            Picker("完成后默认页签", selection: $settings.defaultDoneTab) {
                ForEach(ResultModel.Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }

            // 截屏时隐藏面板，避免面板入镜
            Toggle("截屏时隐藏窗口", isOn: $settings.hideWindowOnCapture)

            // 识别历史设置
            Picker("保存最近识别次数", selection: $settings.historyLimit) {
                Text("不保存").tag(0)
                Text("5 次").tag(5)
                Text("10 次").tag(10)
                Text("20 次").tag(20)
                Text("50 次").tag(50)
                Text("80 次").tag(80)
                Text("180 次").tag(180)
                Text("280 次").tag(280)
            }
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

            // 模型 Key 配置：仅当前主引擎对应分区显示；配置过的 Key 切走后仍保存在
            // Keychain/UserDefaults，切回来自动恢复
            if settings.primaryEngine == .openai {
                Section {
                    TextField("Base URL", text: $settings.openaiBaseURL)
                    TextField("模型", text: $settings.openaiModel)
                    SecureField("API Key", text: $settings.openaiAPIKey)
                    Text("API Key 在智谱开放平台 [open.bigmodel.cn](https://open.bigmodel.cn) 获取，点击链接直达。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                } header: {
                    HStack {
                        Text("智谱 AI")
                        Spacer()
                        Button {
                            settings.openaiBaseURL = SettingsStore.defaultOpenAIBaseURL
                            settings.openaiModel = SettingsStore.defaultOpenAIModel
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.borderless)
                        .help("恢复默认 Base URL 与模型（\(SettingsStore.defaultOpenAIModel)）")
                    }
                }
            }
            if settings.primaryEngine == .deepl {
                Section("DeepL") {
                    SecureField("API Key", text: $settings.deeplAPIKey)
                    Text("API Key 在 [deepl.com](https://www.deepl.com) 获取，点击链接直达；Free 档 Key 以 :fx 结尾。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                TextField("主机", text: $settings.proxyHost)
                    .disabled(!settings.proxyEnabled)
                TextField("端口", text: $settings.proxyPort)
                    .disabled(!settings.proxyEnabled)
                Text("仅对在线引擎（智谱 AI/Google/DeepL）生效，支持 HTTP 代理。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } header: {
                HStack {
                    Text("网络代理")
                    Spacer()
                    Button {
                        settings.proxyHost = SettingsStore.defaultProxyHost
                        settings.proxyPort = SettingsStore.defaultProxyPort
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .help("恢复默认主机与端口（\(SettingsStore.defaultProxyHost):\(SettingsStore.defaultProxyPort)）")
                    Toggle("", isOn: $settings.proxyEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help("启用/停用云引擎代理")
                }
            }
            Section {
                HStack {
                    Button("下载 Apple 翻译语言包") {
                        onPrepareAppleLanguages()
                    }
                    .help("调起系统设置 → 通用 → 翻译 界面，手动下载离线翻译语言包")
                }
                Text("Apple 系统翻译完全离线，需 MacOS 15+。点击按钮会打开系统「翻译」语言设置界面，在系统设置中下载所需语言包。翻译时若语言包未就绪会自动触发准备。该引擎失败时会自动降级到云引擎（智谱 AI/Google/DeepL，需联网）。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(1)
    }
}
