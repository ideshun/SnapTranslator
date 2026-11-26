import SnapTranslatorCore
import SwiftUI

/// 现代 macOS 侧边栏风格设置窗口：左侧彩色图标导航 + 右侧卡片分区详情
struct SettingsView: View {
    enum SectionTab: String, CaseIterable, Identifiable {
        case general = "通用"
        case hotkeys = "快捷键"
        case engines = "引擎与 AI"
        case privacy = "隐私与数据"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .hotkeys: return "command"
            case .engines: return "sparkles"
            case .privacy: return "lock.shield.fill"
            }
        }

        var badgeColor: Color {
            switch self {
            case .general: return .blue
            case .hotkeys: return .orange
            case .engines: return .purple
            case .privacy: return .green
            }
        }

        var subtitle: String {
            switch self {
            case .general: return "语言偏好、截屏交互与窗口外观"
            case .hotkeys: return "全局快捷键与面板键盘流"
            case .engines: return "AI 模型预设、流式引擎与网络代理"
            case .privacy: return "纯离线隐私保护、本地语言包与缓存"
            }
        }
    }

    @ObservedObject var settings: SettingsStore
    let onPrepareAppleLanguages: () -> Void

    @State private var selectedTab: SectionTab = .general
    @State private var isTestingConnection = false
    @State private var testStatusMessage: String?
    @State private var testStatusSuccess = false

    var body: some View {
        HStack(spacing: 0) {
            // 左侧毛玻璃侧边栏
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: "character.bubble.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(STTheme.accentGradient)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("SnapTranslator")
                            .font(.system(size: 13, weight: .semibold))
                        Text("偏好设置")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 14)
                .padding(.bottom, 10)

                ForEach(SectionTab.allCases) { tab in
                    let selected = selectedTab == tab
                    Button {
                        withAnimation(.easeOut(duration: 0.14)) { selectedTab = tab }
                    } label: {
                        HStack(spacing: 9) {
                            STSidebarBadge(systemImage: tab.icon, color: tab.badgeColor, size: 22)
                            Text(tab.rawValue)
                                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                                .foregroundStyle(selected ? .primary : .secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selected ? Color.accentColor.opacity(0.14) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 8)
                    .hoverFeedback(tab.subtitle)
                }

                Spacer()

                // 底部运行状态卡片
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(settings.offlineOnlyMode ? Color.green : Color.accentColor)
                            .frame(width: 6, height: 6)
                        Text(settings.offlineOnlyMode ? "纯离线模式" : settings.activeAIProfile.name)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                    }
                    Text(settings.offlineOnlyMode ? "绝不发送任何网络请求" : settings.activeAIProfile.model)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(STTheme.cardSurface))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(STTheme.hairlineBorder, lineWidth: 0.6))
                .padding(10)
            }
            .frame(width: 176)
            .background(STTheme.windowCanvas)
            .overlay(STTheme.secondaryCanvas.allowsHitTesting(false))

            Divider()

            // 右侧详情内容区
            VStack(alignment: .leading, spacing: 0) {
                // 顶部标题头
                HStack(spacing: 10) {
                    STSidebarBadge(systemImage: selectedTab.icon, color: selectedTab.badgeColor, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedTab.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                        Text(selectedTab.subtitle)
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(STTheme.windowCanvas)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch selectedTab {
                        case .general: generalContent
                        case .hotkeys: hotkeyContent
                        case .engines: engineContent
                        case .privacy: privacyContent
                        }
                    }
                    .padding(18)
                }
                .background(STTheme.windowCanvas)
            }
        }
        .environment(\.stUIFontSize, settings.uiFontSize)
        .frame(minWidth: 700, minHeight: 540)
    }

    // MARK: - 1. 通用

    private var generalContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("语言与识别")
            STCard {
                VStack(spacing: 12) {
                    settingRow("默认目标语言", hint: "当原文与目标相同时会自动智能反转") {
                        Picker("", selection: $settings.targetLanguage) {
                            ForEach(Language.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    Divider()
                    settingRow("持久源语言锁定", hint: "通常建议保持「自动检测」") {
                        Picker("", selection: $settings.persistentSourceLanguage) {
                            Text("自动检测（推荐）").tag(Language?.none)
                            ForEach(Language.allCases) { lang in
                                Text(lang.displayName).tag(Language?.some(lang))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 160)
                    }
                    Divider()
                    settingToggle(
                        "OCR 智能段落合并",
                        hint: "自动合并 PDF/网页硬断行并修复英文行尾连字符，大幅提升译文连贯性",
                        isOn: $settings.ocrSmartMerge
                    )
                }
            }

            sectionTitle("截屏与结果面板")
            STCard {
                VStack(spacing: 12) {
                    settingRow("默认窗口大小") {
                        Picker("", selection: $settings.defaultWindowSize) {
                            ForEach(WindowSize.allCases) { size in
                                Text(size.displayName).tag(size)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 170)
                    }
                    Divider()
                    settingRow("截图显示方式") {
                        Picker("", selection: $settings.screenshotDisplayMode) {
                            ForEach(ScreenshotDisplayMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 210)
                    }
                    Divider()
                    settingRow("翻译完成后默认页签") {
                        Picker("", selection: $settings.defaultDoneTab) {
                            ForEach(PanelTab.allCases) { tab in
                                Text(tab.rawValue).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 220)
                    }
                    Divider()
                    settingToggle(
                        "截屏框选后停留精调工具栏",
                        hint: "松开鼠标后可微调选区，并选择「翻译 / 仅提文字 / 贴图 / 保存」",
                        isOn: $settings.captureRefineToolbar
                    )
                    Divider()
                    settingToggle(
                        "截屏时排除自身翻译面板",
                        hint: "基于 ScreenCaptureKit 原生过滤，面板绝不入镜",
                        isOn: $settings.hideWindowOnCapture
                    )
                    Divider()
                    settingToggle("结果面板置顶显示", isOn: $settings.alwaysOnTop)
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("界面字体大小").font(.system(size: 13))
                            Text("实时作用于顶部页签、分栏标题与底部状态栏")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Slider(
                            value: $settings.uiFontSize,
                            in: SettingsStore.minUIFontSize...SettingsStore.maxUIFontSize,
                            step: 0.5
                        )
                        .frame(width: 120)
                        Text(String(format: "%.1f pt", settings.uiFontSize).replacingOccurrences(of: ".0", with: ""))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 58, alignment: .trailing)
                        Button {
                            settings.resetUIFontSize()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10.5))
                        }
                        .buttonStyle(.borderless)
                        .disabled(abs(settings.uiFontSize - SettingsStore.defaultUIFontSize) < 0.05)
                        .hoverFeedback("恢复默认界面字号 (\(Int(SettingsStore.defaultUIFontSize)) pt)")
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("正文字体大小").font(.system(size: 13))
                            Text("实时作用于原文与译文面板（也可直接按 ⌘+ / ⌘- / ⌘0 调节）")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Slider(
                            value: $settings.textFontSize,
                            in: SettingsStore.minTextFontSize...SettingsStore.maxTextFontSize,
                            step: 1
                        )
                        .frame(width: 120)
                        Text("\(Int(settings.textFontSize)) pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .frame(width: 58, alignment: .trailing)
                        Button {
                            settings.resetFontSize()
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10.5))
                        }
                        .buttonStyle(.borderless)
                        .disabled(Int(settings.textFontSize) == Int(SettingsStore.defaultTextFontSize))
                        .hoverFeedback("恢复默认字号 (\(Int(SettingsStore.defaultTextFontSize)) pt)")
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("失焦透明度").font(.system(size: 13))
                            Text("面板失去焦点时自动淡化，方便边看底层文档边对照")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Slider(value: $settings.unfocusedOpacity, in: 0.15...0.95, step: 0.05)
                            .frame(width: 130)
                        Text("\(Int(settings.unfocusedOpacity * 100))%")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                }
            }

            sectionTitle("系统集成")
            STCard {
                VStack(spacing: 12) {
                    settingToggle("在程序坞（Dock）中显示图标", hint: "关闭后仅驻留顶部菜单栏", isOn: $settings.showInDock)
                    Divider()
                    settingToggle("登录 macOS 时自动启动", isOn: $settings.launchAtLogin)
                }
            }
        }
    }

    // MARK: - 2. 快捷键

    private var hotkeyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("全局快捷键（零辅助功能权限）")
            STCard {
                VStack(spacing: 11) {
                    hotkeyRow(title: "截屏翻译", subtitle: "框选区域或点击窗口自动吸附", spec: $settings.hotkeyCapture)
                    Divider()
                    hotkeyRow(title: "重截上次区域", subtitle: "连续翻译字幕、日志或终端输出", spec: $settings.hotkeyRecapture)
                    Divider()
                    hotkeyRow(title: "静默截屏 OCR", subtitle: "离线识别并直接写入剪贴板，不弹窗打扰", spec: $settings.hotkeySilentOCR)
                    Divider()
                    hotkeyRow(title: "翻译剪贴板", subtitle: "自动识别剪贴板中的文本或截图", spec: $settings.hotkeyTranslateClipboard)
                    Divider()
                    hotkeyRow(title: "显示 / 隐藏主面板", subtitle: "快速唤起或收起翻译面板", spec: $settings.hotkeyTogglePanel)
                }
            }

            if hasDuplicateHotkey {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("检测到存在重复的快捷键绑定，建议调整以避免触发冲突。")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.10)))
            }

            sectionTitle("主面板快捷键盘流")
            STCard {
                VStack(spacing: 9) {
                    shortcutHintRow("切换 识别 / 翻译 / 对照 / 对比", tokens: ["⌘", "1~4"])
                    Divider()
                    shortcutHintRow("复制译文 / 复制原文", tokens: ["⌘", "C", "/", "⌘", "⇧", "C"])
                    Divider()
                    shortcutHintRow("粘贴截图直接识别翻译", tokens: ["⌘", "V"])
                    Divider()
                    shortcutHintRow("重新识别与翻译", tokens: ["⌘", "R"])
                    Divider()
                    shortcutHintRow("放大 / 缩小 / 重置正文字号", tokens: ["⌘", "+", "/", "⌘", "-", "/", "⌘", "0"])
                    Divider()
                    shortcutHintRow("打开识别历史 / 隐藏主面板", tokens: ["⌘", "H", "/", "ESC"])
                }
            }
        }
    }

    // MARK: - 3. 引擎与 AI

    private var engineContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if settings.offlineOnlyMode {
                HStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill").font(.system(size: 18)).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前处于「纯离线隐私模式」").font(.system(size: 12.5, weight: .semibold))
                        Text("云端引擎与代理配置已暂停生效，如需调整请先在「隐私与数据」中关闭纯离线模式。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.green.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.28), lineWidth: 0.6))
            }

            sectionTitle("调度策略与风格")
            STCard {
                VStack(spacing: 12) {
                    settingRow("主引擎策略") {
                        Picker("", selection: $settings.primaryEngine) {
                            ForEach(PrimaryEngine.allCases) { engine in
                                Text(engine.displayName).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    Divider()
                    settingRow("默认 AI 翻译风格") {
                        Picker("", selection: $settings.translationStyle) {
                            ForEach(TranslationStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 240)
                    }
                    Divider()
                    settingRow("双引擎对比副引擎", hint: "开启对比视图时并行调用的对照引擎") {
                        Picker("", selection: $settings.compareSecondaryEngine) {
                            ForEach(PrimaryEngine.allCases.filter { $0 != .auto }) { engine in
                                Text(engine.shortName).tag(engine)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
            }
            .disabled(settings.offlineOnlyMode)
            .opacity(settings.offlineOnlyMode ? 0.55 : 1)

            sectionTitle("AI 模型配置预设（支持 SSE 流式输出）")
            aiProfileCard
                .disabled(settings.offlineOnlyMode)
                .opacity(settings.offlineOnlyMode ? 0.55 : 1)

            sectionTitle("DeepL 与网络代理")
            STCard {
                VStack(spacing: 12) {
                    settingRow("DeepL API Key", hint: "Free 档以 :fx 结尾，采用官方 Header 鉴权") {
                        SecureField("填入 DeepL Key（可选）", text: $settings.deeplAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                    }
                    Divider()
                    settingToggle("启用在线引擎 HTTP 代理", hint: "仅作用于云端引擎，复用连接池", isOn: $settings.proxyEnabled)
                    if settings.proxyEnabled {
                        HStack(spacing: 10) {
                            TextField("主机 (127.0.0.1)", text: $settings.proxyHost)
                                .textFieldStyle(.roundedBorder)
                            TextField("端口 (7890)", text: $settings.proxyPort)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Button("默认") {
                                settings.proxyHost = SettingsStore.defaultProxyHost
                                settings.proxyPort = SettingsStore.defaultProxyPort
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .disabled(settings.offlineOnlyMode)
            .opacity(settings.offlineOnlyMode ? 0.55 : 1)
        }
    }

    private var aiProfileCard: some View {
        let active = settings.activeAIProfile
        return STCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Picker("当前预设", selection: $settings.activeAIProfileID) {
                        ForEach(settings.aiProfiles) { profile in
                            Text("\(profile.name) · \(profile.model)").tag(profile.id)
                        }
                    }
                    .labelsHidden()

                    Menu {
                        ForEach(AIProfile.builtInTemplates) { template in
                            Button("添加模板：\(template.name) (\(template.model))") {
                                settings.addProfile(from: template)
                                testStatusMessage = nil
                            }
                        }
                        Divider()
                        Button("添加自定义 OpenAI 兼容端点") {
                            settings.addProfile(from: AIProfile(
                                name: "自定义 AI",
                                baseURL: "https://api.openai.com/v1",
                                model: "gpt-4o-mini",
                                requiresAPIKey: true
                            ))
                            testStatusMessage = nil
                        }
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                    .fixedSize()

                    if settings.aiProfiles.count > 1 {
                        Button(role: .destructive) {
                            settings.deleteActiveProfile()
                            testStatusMessage = nil
                        } label: {
                            Image(systemName: "trash").foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .hoverFeedback("删除当前预设")
                    }
                }

                Divider()

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                    GridRow {
                        Text("显示名称").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                        TextField("例如：智谱 AI", text: Binding(
                            get: { active.name },
                            set: { settings.updateActiveProfile(name: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("Base URL").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                        TextField("https://open.bigmodel.cn/api/paas/v4", text: Binding(
                            get: { active.baseURL },
                            set: { settings.updateActiveProfile(baseURL: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        Text("模型名称").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                        TextField("glm-5.2", text: Binding(
                            get: { active.model },
                            set: { settings.updateActiveProfile(model: $0) }
                        ))
                        .textFieldStyle(.roundedBorder)
                    }
                    if active.requiresAPIKey {
                        GridRow {
                            Text("API Key").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 72, alignment: .trailing)
                            SecureField("安全存储于 macOS Keychain", text: $settings.activeAIAPIKey)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                Toggle("需要 API Key（本地 Ollama 等服务可关闭）", isOn: Binding(
                    get: { active.requiresAPIKey },
                    set: { settings.updateActiveProfile(requiresAPIKey: $0) }
                ))
                .font(.system(size: 12))

                HStack(spacing: 10) {
                    Button {
                        runConnectionTest()
                    } label: {
                        if isTestingConnection {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("测试连接中…")
                            }
                        } else {
                            Label("测试连接", systemImage: "bolt.horizontal.circle.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isTestingConnection || !settings.hasConfiguredAI)

                    if let msg = testStatusMessage {
                        HStack(spacing: 4) {
                            Image(systemName: testStatusSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                            Text(msg).lineLimit(2)
                        }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(testStatusSuccess ? .green : .red)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - 4. 隐私与数据

    private var privacyContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("离线与隐私保护")
            STCard {
                VStack(alignment: .leading, spacing: 12) {
                    settingToggle(
                        "纯离线隐私模式（绝不联网）",
                        hint: "开启后严格仅使用端上 Apple Vision OCR 与 Apple 本地翻译，禁止所有云端请求与降级",
                        isOn: $settings.offlineOnlyMode
                    )
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Apple 本地离线语言包（macOS 15+）").font(.system(size: 13))
                            Text("前往系统设置下载离线翻译语言包，确保无网环境下流畅翻译")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("打开系统设置") { onPrepareAppleLanguages() }
                            .controlSize(.small)
                    }
                }
            }

            sectionTitle("历史记录与本地缓存")
            STCard {
                VStack(spacing: 12) {
                    settingRow("历史记录保留上限", hint: "持久化至磁盘，星标条目不受数量清理限制") {
                        Picker("", selection: $settings.historyLimit) {
                            Text("不保存").tag(0)
                            Text("10 条").tag(10)
                            Text("30 条").tag(30)
                            Text("50 条").tag(50)
                            Text("100 条").tag(100)
                            Text("280 条").tag(280)
                            Divider()
                            Text("无限制").tag(HistoryStore.unlimitedLimit)
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("翻译 LRU 内存缓存与熔断状态").font(.system(size: 13))
                            Text("当前已缓存 \(TranslationCache.shared.count) 条翻译结果")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("清空缓存并重置熔断") {
                            TranslationCache.shared.clear()
                            EngineBreaker.shared.resetAll()
                            testStatusSuccess = true
                            testStatusMessage = "已清空缓存与熔断状态"
                        }
                        .controlSize(.small)
                    }
                }
            }
        }
    }

    // MARK: - 辅助布局方法

    private var hasDuplicateHotkey: Bool {
        let all = [
            settings.hotkeyCapture,
            settings.hotkeyRecapture,
            settings.hotkeySilentOCR,
            settings.hotkeyTranslateClipboard,
            settings.hotkeyTogglePanel,
        ]
        return Set(all).count < all.count
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
    }

    private func settingRow<Control: View>(_ title: String, hint: String? = nil, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            control()
        }
    }

    private func settingToggle(_ title: String, hint: String? = nil, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                if let hint {
                    Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func hotkeyRow(title: String, subtitle: String, spec: Binding<HotkeySpec>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            HotkeyRecorder(spec: spec)
                .frame(width: 150, height: 28)
        }
    }

    private func shortcutHintRow(_ title: String, tokens: [String]) -> some View {
        HStack {
            Text(title).font(.system(size: 12.5))
            Spacer()
            KbdShortcutView(tokens: tokens)
        }
    }

    private func runConnectionTest() {
        isTestingConnection = true
        testStatusMessage = nil
        let profile = settings.activeAIProfile
        let apiKey = settings.activeAIAPIKey
        let proxy = settings.engineProxy

        Task {
            let session = NetworkSessionPool.shared.session(for: proxy)
            let provider = OpenAICompatProvider(
                name: profile.name,
                profileID: profile.id,
                baseURL: profile.baseURL,
                model: profile.model,
                apiKey: apiKey,
                requiresAPIKey: profile.requiresAPIKey,
                session: session
            )
            do {
                let elapsed = try await provider.testConnection()
                await MainActor.run {
                    isTestingConnection = false
                    testStatusSuccess = true
                    testStatusMessage = String(format: "连接成功（%.0f ms）", elapsed * 1000)
                }
            } catch {
                await MainActor.run {
                    isTestingConnection = false
                    testStatusSuccess = false
                    testStatusMessage = error.localizedDescription
                }
            }
        }
    }
}
