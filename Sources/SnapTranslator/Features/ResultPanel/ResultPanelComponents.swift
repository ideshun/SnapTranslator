import AppKit
import SnapTranslatorCore
import SwiftUI

/// 面板内分栏统一标题栏：左侧语种/标题与字数，右侧紧凑朗读与复制控件（合并原独立朗读条，空间更通透）
struct TextPaneHeaderBar<Extra: View>: View {
    @Environment(\.stUIFontSize) private var uiFontSize
    @ObservedObject var speech = SpeechManager.shared
    let title: String
    let text: String
    let language: Language?
    let selection: String
    var accentDot: Color? = nil
    var onCopied: (() -> Void)? = nil
    @ViewBuilder var extra: () -> Extra

    @State private var copied = false

    private var countLabel: String? {
        let count = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        return count > 0 ? "\(count) 字" : nil
    }

    var body: some View {
        let isSpeakingActive = speech.isSpeaking && !speech.isPausedState

        STPaneHeader(title: title, subtitle: countLabel, accentDot: accentDot) {
            HStack(spacing: 3) {
                if !selection.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "selection.pin.in.out")
                            .font(.system(size: max(9, uiFontSize - 3.5)))
                        Text("已选 \(selection.count) 字")
                            .font(.system(size: max(10.5, uiFontSize - 2), weight: .medium))
                    }
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.11)))
                    .padding(.trailing, 2)
                }

                extra()

                if isSpeakingActive {
                    STSpeakingWaveView(active: true)
                        .padding(.horizontal, 3)
                }

                SpeechBarButton(
                    systemImage: "speaker.wave.2",
                    tooltip: selection.isEmpty ? "朗读全文" : "朗读选中部分",
                    isActive: isSpeakingActive,
                    isDisabled: text.isEmpty
                ) {
                    speech.speak(selection.isEmpty ? text : selection, language: language)
                }

                if speech.isSpeaking {
                    SpeechBarButton(
                        systemImage: speech.isPausedState ? "play.fill" : "pause.fill",
                        tooltip: speech.isPausedState ? "继续朗读" : "暂停朗读"
                    ) {
                        speech.togglePause()
                    }
                    SpeechBarButton(
                        systemImage: "stop.fill",
                        tooltip: "停止朗读"
                    ) {
                        speech.stop()
                    }
                }

                SpeechBarButton(
                    systemImage: copied ? "checkmark" : "doc.on.doc",
                    tooltip: "复制此栏内容",
                    isActive: copied,
                    isDisabled: text.isEmpty
                ) {
                    NSPasteboard.writeString(text)
                    onCopied?()
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation(.easeOut(duration: 0.15)) { copied = false }
                    }
                }
            }
        }
    }
}

extension TextPaneHeaderBar where Extra == EmptyView {
    init(
        title: String,
        text: String,
        language: Language?,
        selection: String,
        accentDot: Color? = nil,
        onCopied: (() -> Void)? = nil
    ) {
        self.init(
            title: title,
            text: text,
            language: language,
            selection: selection,
            accentDot: accentDot,
            onCopied: onCopied,
            extra: { EmptyView() }
        )
    }
}

/// 浮动玻璃图片控制胶囊（实时缩放百分比 + 缩放 + 重置 + 桌面贴图）
struct ZoomControlBar: View {
    @Binding var scale: CGFloat
    var onPin: (() -> Void)? = nil

    var body: some View {
        STFloatingHUD {
            ZoomBarButton(systemImage: "minus", tooltip: "缩小") {
                withAnimation(.easeOut(duration: 0.15)) { scale = max(0.2, scale / 1.25) }
            }
            Text("\(Int((scale * 100).rounded()))%")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.92))
                .frame(minWidth: 34)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) { scale = 1.0 }
                }
                .hoverFeedback("点击重置为 100%")
            ZoomBarButton(systemImage: "plus", tooltip: "放大") {
                withAnimation(.easeOut(duration: 0.15)) { scale = min(5.0, scale * 1.25) }
            }
            if let onPin {
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 1, height: 12)
                    .padding(.horizontal, 2)
                ZoomBarButton(systemImage: "pin", tooltip: "钉在桌面（悬浮贴图）", action: onPin)
            }
        }
        .padding(10)
    }
}

/// AI 划词速释浮层卡片
struct QuickExplainCard: View {
    let state: ResultModel.QuickExplainState
    let onCollect: () -> Void
    let onCopy: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: 24, height: 24)
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.phrase)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("AI 语境速释")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !state.content.isEmpty {
                    SpeechBarButton(systemImage: "bookmark", tooltip: "收藏该词条及释义", action: onCollect)
                    SpeechBarButton(systemImage: "doc.on.doc", tooltip: "复制释义", action: onCopy)
                }
                SpeechBarButton(systemImage: "xmark", tooltip: "关闭 (ESC)", action: onDismiss)
            }

            Divider()

            if state.isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在结合语境解析词义…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            } else if let error = state.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            } else {
                ScrollView {
                    Text(state.content)
                        .font(.system(size: 13))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)
            }
        }
        .padding(14)
        .frame(maxWidth: 380)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: STTheme.radiusLG, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: STTheme.radiusLG, style: .continuous)
                .stroke(STTheme.strongBorder, lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.22), radius: 18, y: 8)
    }
}

/// 键盘快捷键按键外观
struct KbdShortcutView: View {
    let tokens: [String]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                Text(token)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.85))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(STTheme.panelSurface)
                            .shadow(color: Color.black.opacity(0.10), radius: 0.8, x: 0, y: 1)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .stroke(STTheme.hairlineBorder, lineWidth: 0.6)
                            )
                    )
            }
        }
    }
}

struct ClearActionButton: View {
    let isDisabled: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "trash")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(isDisabled ? Color.secondary.opacity(0.32) : (isHovered ? Color.red : Color.secondary))
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isHovered && !isDisabled ? Color.red.opacity(0.12) : STTheme.subtleFill)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .hoverFeedback("清空当前内容")
    }
}

struct ToolbarIconButton: View {
    let systemImage: String
    let tooltip: String
    var iconColor: Color? = nil
    var rotationAngle: Double = 0
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(iconColor ?? (isActive ? Color.accentColor : Color.primary.opacity(0.82)))
                .rotationEffect(.degrees(rotationAngle))
                .frame(width: 28, height: 26)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(Color.accentColor.opacity(0.16))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .stroke(Color.accentColor.opacity(0.28), lineWidth: 0.5)
                            )
                    } else if isHovered && !isDisabled {
                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                            .fill(STTheme.hoverFill)
                    }
                }
                .scaleEffect(isPressed ? 0.91 : 1.0)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.36 : 1.0)
        .onHover { isHovered = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .hoverFeedback(tooltip)
    }
}

struct ToolbarButton: View {
    @Environment(\.stUIFontSize) private var uiFontSize
    let title: String
    let systemImage: String
    let tooltip: String
    var isProminent: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4.5) {
                Image(systemName: systemImage)
                    .font(.system(size: max(11, uiFontSize - 1), weight: .medium))
                Text(title)
                    .font(.system(size: max(11.5, uiFontSize - 0.5), weight: .medium))
            }
            .foregroundStyle(
                isProminent
                    ? Color.white
                    : (isDisabled ? Color.secondary.opacity(0.38) : Color.primary.opacity(0.88))
            )
            .padding(.horizontal, 8.5)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                    .fill(
                        isProminent
                            ? Color.accentColor.opacity(isHovered ? 0.92 : 1.0)
                            : (isHovered && !isDisabled ? STTheme.hoverFill : STTheme.subtleFill)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .hoverFeedback(tooltip)
    }
}

struct SpeechBarButton: View {
    let systemImage: String
    let tooltip: String
    var isActive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isActive ? Color.accentColor : (isDisabled ? Color.secondary.opacity(0.35) : Color.secondary))
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isHovered && !isDisabled ? STTheme.hoverFill : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .onHover { isHovered = $0 }
        .hoverFeedback(tooltip)
    }
}

struct ZoomBarButton: View {
    let systemImage: String
    let tooltip: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.95))
                .frame(width: 24, height: 24)
                .background(Circle().fill(isHovered ? Color.white.opacity(0.22) : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .hoverFeedback(tooltip)
    }
}
