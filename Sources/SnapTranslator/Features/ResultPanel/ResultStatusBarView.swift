import SnapTranslatorCore
import SwiftUI

/// 通透毛玻璃底部状态栏：语向胶囊 + 引擎/风格胶囊 + 缓存徽章 + 清空 + 语义通知胶囊
struct ResultStatusBarView: View {
    @Environment(\.stUIFontSize) private var uiFontSize
    @ObservedObject var model: ResultModel
    @ObservedObject var settings: SettingsStore

    let onSwapLanguages: () -> Void
    let onSourceLanguageChange: (Language?) -> Void
    let onTargetLanguageChange: (Language) -> Void
    let onEngineChange: (PrimaryEngine?) -> Void
    let onStyleChange: (TranslationStyle?) -> Void
    let onClear: () -> Void

    @State private var swapAngle: Double = 0

    private var showLanguageBar: Bool {
        model.phase == .done || (model.phase == .idle && model.tab == .translation)
    }

    private var switchableEngines: [PrimaryEngine] {
        if settings.offlineOnlyMode { return [.apple] }
        return PrimaryEngine.allCases.filter { engine in
            switch engine {
            case .openai: return settings.hasConfiguredAI
            case .deepl: return !settings.deeplAPIKey.isEmpty
            default: return true
            }
        }
    }

    private var engineDisplayName: String {
        if settings.offlineOnlyMode { return "纯离线" }
        if let override = model.engineOverride {
            return override == .openai ? settings.activeAIProfile.name : override.shortName
        }
        if !model.providerName.isEmpty {
            return model.providerName
        }
        return settings.primaryEngine == .openai ? settings.activeAIProfile.name : settings.primaryEngine.shortName
    }

    private var activeStyle: TranslationStyle {
        model.styleOverride ?? settings.translationStyle
    }

    var body: some View {
        HStack(spacing: 8) {
            if showLanguageBar {
                languagePairControl
                engineControl
                if !settings.offlineOnlyMode {
                    styleControl
                }
                if model.fromCache && !model.translatedText.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: max(9, uiFontSize - 3)))
                        Text("缓存")
                            .font(.system(size: max(10.5, uiFontSize - 1.5), weight: .medium))
                    }
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3.5)
                    .background(Capsule().fill(Color.orange.opacity(0.11)))
                    .hoverFeedback("命中本地 LRU 翻译缓存，0ms 返回")
                }
                ClearActionButton(isDisabled: !model.hasContent, action: onClear)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: settings.offlineOnlyMode ? "lock.shield.fill" : "sparkles")
                        .font(.system(size: max(11, uiFontSize - 1), weight: .semibold))
                        .foregroundStyle(settings.offlineOnlyMode ? .green : Color.accentColor)
                    Text(settings.offlineOnlyMode ? "SnapTranslator · 纯离线隐私模式" : "SnapTranslator")
                        .font(.system(size: max(11.5, uiFontSize - 0.5), weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let notice = model.notice {
                noticeBadge(notice)
            }
        }
        .font(.system(size: max(11.5, uiFontSize - 0.5)))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: max(38, uiFontSize + 25))
        .background(.bar)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: model.notice)
    }

    private var languagePairControl: some View {
        HStack(spacing: 0) {
            Menu {
                Button("自动检测") {
                    model.sourceLanguage = nil
                    onSourceLanguageChange(nil)
                }
                Divider()
                ForEach(Language.allCases) { lang in
                    Button(lang.displayName) {
                        model.sourceLanguage = lang
                        onSourceLanguageChange(lang)
                    }
                }
            } label: {
                let itemSize = max(11.5, uiFontSize - 0.5)
                (
                    Text(model.sourceLanguage?.displayName ?? "自动检测")
                        .font(.system(size: itemSize, weight: .medium))
                        .foregroundColor(model.sourceLanguage == nil ? .secondary : .primary)
                    + Text(" ")
                    + Text(Image(systemName: "chevron.down"))
                        .font(.system(size: max(8, itemSize - 4), weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverFeedback("选择源语言")

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) { swapAngle += 180 }
                onSwapLanguages()
            } label: {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: max(9.5, uiFontSize - 3), weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .rotationEffect(.degrees(swapAngle))
                    .frame(width: max(24, uiFontSize + 12), height: max(24, uiFontSize + 10))
                    .background(Circle().fill(Color.accentColor.opacity(0.10)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .hoverFeedback("交换源语言与目标语言")

            Menu {
                ForEach(Language.allCases) { lang in
                    Button(lang.displayName) {
                        model.targetLanguage = lang
                        onTargetLanguageChange(lang)
                    }
                }
            } label: {
                let itemSize = max(11.5, uiFontSize - 0.5)
                (
                    Text(model.targetLanguage.displayName)
                        .font(.system(size: itemSize, weight: .semibold))
                        .foregroundColor(.primary)
                    + Text(" ")
                    + Text(Image(systemName: "chevron.down"))
                        .font(.system(size: max(8, itemSize - 4), weight: .bold))
                        .foregroundColor(.secondary.opacity(0.7))
                )
                .padding(.horizontal, 9)
                .padding(.vertical, 4.5)
                .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .hoverFeedback("选择目标语言")
        }
        .background(capsuleBackground)
        .overlay(capsuleBorder)
    }

    private var engineControl: some View {
        Menu {
            if settings.offlineOnlyMode {
                Text("已开启纯离线隐私模式（仅 Apple 本地）")
            } else {
                Button { onEngineChange(nil) } label: {
                    Text(model.engineOverride == nil ? "✓ 跟随主引擎设置" : "跟随主引擎设置")
                }
                Divider()
                ForEach(switchableEngines) { engine in
                    let label = engine == .openai
                        ? "\(settings.activeAIProfile.name) (\(settings.activeAIProfile.model))"
                        : engine.displayName
                    Button { onEngineChange(engine) } label: {
                        Text(model.engineOverride == engine ? "✓ \(label)" : label)
                    }
                }
            }
        } label: {
            let itemSize = max(11.5, uiFontSize - 0.5)
            (
                Text(Image(systemName: settings.offlineOnlyMode ? "lock.shield.fill" : "circle.fill"))
                    .font(.system(size: settings.offlineOnlyMode ? max(10, itemSize - 2) : 6.5))
                    .foregroundColor(settings.offlineOnlyMode ? .green : (model.isLiveTranslating || model.phase == .translating ? .orange : .green))
                + Text("  \(engineDisplayName) ")
                    .font(.system(size: itemSize, weight: .medium))
                    .foregroundColor(.primary.opacity(0.88))
                + Text(Image(systemName: "chevron.down"))
                    .font(.system(size: max(8, itemSize - 4), weight: .bold))
                    .foregroundColor(.secondary.opacity(0.7))
            )
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(capsuleBackground)
            .overlay(capsuleBorder)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverFeedback("切换翻译引擎（立即重译）")
    }

    private var styleControl: some View {
        Menu {
            ForEach(TranslationStyle.allCases) { style in
                Button { onStyleChange(style) } label: {
                    Text(activeStyle == style ? "✓ \(style.displayName)" : style.displayName)
                }
            }
        } label: {
            let itemSize = max(11.5, uiFontSize - 0.5)
            HStack(spacing: 4) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: max(10, itemSize - 1.5)))
                    .foregroundStyle(Color.accentColor.opacity(0.85))
                Text(activeStyle.shortName)
                    .font(.system(size: itemSize, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.85))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(capsuleBackground)
            .overlay(capsuleBorder)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .hoverFeedback("切换 AI 翻译风格（通用 / 技术 / 学术 / 简洁）")
    }

    private func noticeBadge(_ notice: ResultModel.Notice) -> some View {
        let color: Color
        let icon: String
        switch notice.kind {
        case .success: color = .green; icon = "checkmark.circle.fill"
        case .info: color = .accentColor; icon = "info.circle.fill"
        case .warning: color = .orange; icon = "exclamationmark.triangle.fill"
        case .error: color = .red; icon = "xmark.octagon.fill"
        }
        let itemSize = max(11.5, uiFontSize - 0.5)
        return HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: max(11, itemSize - 0.5), weight: .bold)).foregroundStyle(color)
            Text(notice.text).font(.system(size: itemSize, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(color.opacity(0.12))
                .overlay(Capsule().stroke(color.opacity(0.32), lineWidth: 0.6))
        )
        .transition(.asymmetric(insertion: .scale(scale: 0.92).combined(with: .opacity), removal: .opacity))
    }

    private var capsuleBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(STTheme.panelSurface)
            .shadow(color: Color.black.opacity(0.05), radius: 1.5, x: 0, y: 1)
    }

    private var capsuleBorder: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(STTheme.hairlineBorder, lineWidth: 0.6)
    }
}
