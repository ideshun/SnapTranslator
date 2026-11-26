import AppKit
import SwiftUI

private struct STUIFontSizeKey: EnvironmentKey {
    static let defaultValue: CGFloat = 13
}

extension EnvironmentValues {
    /// 全局界面控件字号（由 SettingsStore.uiFontSize 驱动，页签/分栏头/状态栏/弹窗统一响应）
    var stUIFontSize: CGFloat {
        get { self[STUIFontSizeKey.self] }
        set { self[STUIFontSizeKey.self] = newValue }
    }
}

/// SnapTranslator 统一视觉设计系统（原生 macOS 质感：细腻层级、通透毛玻璃、克制微动效）
enum STTheme {
    // MARK: - 圆角
    static let radiusXS: CGFloat = 5
    static let radiusSM: CGFloat = 7
    static let radiusMD: CGFloat = 10
    static let radiusLG: CGFloat = 12

    // MARK: - 语义表面色（纯净通透底色 + 极浅层次区分，自动适配浅色/深色模式）
    /// 主内容画布：浅色模式为纯净纸白，深色模式为深邃石墨黑，与顶部/底部毛玻璃栏自然融合，无突兀灰底
    static let windowCanvas = Color(nsColor: .textBackgroundColor)
    /// 极浅副画布（分栏头、图片底板、译文微区分）
    static let secondaryCanvas = Color.primary.opacity(0.018)
    /// 轻量卡片表面（静息 / 悬停）
    static let cardSurface = Color.primary.opacity(0.026)
    static let cardHoverSurface = Color.primary.opacity(0.052)
    /// 控件与浮层表面（激活页签胶囊、快捷键键帽、状态栏胶囊）
    static let panelSurface = Color(nsColor: .controlBackgroundColor)
    static let subtleFill = Color.primary.opacity(0.04)
    static let hoverFill = Color.primary.opacity(0.075)
    static let hairlineBorder = Color.primary.opacity(0.08)
    static let strongBorder = Color.primary.opacity(0.14)

    // MARK: - 品牌渐变强调色
    static let accentGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.75)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroGlow = LinearGradient(
        colors: [
            Color.accentColor.opacity(0.22),
            Color.purple.opacity(0.10),
            Color.clear,
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// 统一卡片容器（设置页、详情页、空态引导共用）
struct STCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: STTheme.radiusMD, style: .continuous)
                    .fill(STTheme.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: STTheme.radiusMD, style: .continuous)
                    .stroke(STTheme.hairlineBorder, lineWidth: 0.75)
            )
    }
}

/// 设置/侧边栏图标徽章（macOS 系统设置风格的圆角彩色图标）
struct STSidebarBadge: View {
    let systemImage: String
    let color: Color
    var size: CGFloat = 22

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: color.opacity(0.28), radius: 2, y: 1)
            Image(systemName: systemImage)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// 面板内分栏头部（语种徽章 + 字数统计 + 快捷动作区）
struct STPaneHeader<Trailing: View>: View {
    @Environment(\.stUIFontSize) private var uiFontSize
    let title: String
    var subtitle: String? = nil
    var accentDot: Color? = nil
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if let accentDot {
                    Circle()
                        .fill(accentDot)
                        .frame(width: 6.5, height: 6.5)
                }
                Text(title)
                    .font(.system(size: uiFontSize, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: max(10.5, uiFontSize - 1.5), weight: .regular, design: .rounded))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 12)
        .frame(height: max(34, uiFontSize + 21))
        .background(STTheme.secondaryCanvas)
    }
}

/// 轻量骨架屏（译文等待首字返回时展示，告别干巴巴的转圈）
struct STTranslationSkeleton: View {
    @Environment(\.stUIFontSize) private var uiFontSize
    let targetLanguageName: String
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
                Text("正在翻译为\(targetLanguageName)…")
                    .font(.system(size: max(12, uiFontSize), weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 9) {
                skeletonBar(widthFactor: 0.92)
                skeletonBar(widthFactor: 0.78)
                skeletonBar(widthFactor: 0.58)
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.95).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func skeletonBar(widthFactor: CGFloat) -> some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(pulse ? 0.11 : 0.05))
                .frame(width: max(40, geo.size.width * widthFactor), height: 11)
        }
        .frame(height: 11)
    }
}

/// 浮动玻璃控制胶囊（图片缩放、1:1 译文图操作共用）
struct STFloatingHUD<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 3) {
            content()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .background(Capsule().fill(Color.black.opacity(0.32)))
        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 0.6))
        .shadow(color: .black.opacity(0.24), radius: 8, y: 3)
    }
}

/// 语音朗读律动指示器
struct STSpeakingWaveView: View {
    let active: Bool
    @State private var animate = false

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.accentColor)
                    .frame(width: 2, height: animate ? (index == 1 ? 10 : 6) : (index == 1 ? 5 : 9))
            }
        }
        .frame(width: 12, height: 12)
        .onAppear {
            if active {
                withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
        }
        .onChange(of: active) { _, isActive in
            if isActive {
                withAnimation(.easeInOut(duration: 0.42).repeatForever(autoreverses: true)) {
                    animate = true
                }
            } else {
                animate = false
            }
        }
    }
}

/// 精巧标签胶囊（生词本与详情页共用）
struct STTagChip: View {
    let text: String
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.accentColor)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
        .overlay(Capsule().stroke(Color.accentColor.opacity(0.22), lineWidth: 0.5))
    }
}

/// 均衡可拖拽水平双栏容器：默认精准 50% / 50% 均分（彻底解决原生 HSplitView 包裹 NSTextView 时左宽右窄失衡问题），
/// 支持拖拽中缝自由调节比例、双击中缝重置 50:50
struct STBalancedHSplit<Left: View, Right: View>: View {
    var minLeadingWidth: CGFloat = 180
    var minTrailingWidth: CGFloat = 180
    @State private var ratio: CGFloat = 0.5
    @State private var dragStartRatio: CGFloat?
    @State private var hoveringDivider = false
    @ViewBuilder var left: () -> Left
    @ViewBuilder var right: () -> Right

    var body: some View {
        GeometryReader { geo in
            let totalW = max(1, geo.size.width)
            let dividerW: CGFloat = 1
            let usableW = max(1, totalW - dividerW)
            let minRatio = min(0.45, minLeadingWidth / usableW)
            let maxRatio = max(0.55, 1.0 - minTrailingWidth / usableW)
            let clamped = min(max(ratio, minRatio), maxRatio)
            let leftW = (usableW * clamped).rounded()
            let rightW = max(1, usableW - leftW)

            HStack(spacing: 0) {
                left()
                    .frame(width: leftW, height: geo.size.height)

                ZStack {
                    Rectangle()
                        .fill(hoveringDivider ? Color.accentColor.opacity(0.55) : STTheme.hairlineBorder)
                        .frame(width: hoveringDivider ? 2 : dividerW)
                    Color.clear
                        .frame(width: 9)
                        .contentShape(Rectangle())
                }
                .frame(width: dividerW, height: geo.size.height)
                .zIndex(2)
                .onHover { inside in
                    hoveringDivider = inside
                    if inside {
                        NSCursor.resizeLeftRight.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .onTapGesture(count: 2) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        ratio = 0.5
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 1, coordinateSpace: .named("STSplitSpace"))
                        .onChanged { value in
                            if dragStartRatio == nil { dragStartRatio = clamped }
                            let base = dragStartRatio ?? 0.5
                            let next = base + value.translation.width / usableW
                            ratio = min(max(next, minRatio), maxRatio)
                        }
                        .onEnded { _ in
                            dragStartRatio = nil
                        }
                )

                right()
                    .frame(width: rightW, height: geo.size.height)
            }
            .coordinateSpace(name: "STSplitSpace")
        }
    }
}
