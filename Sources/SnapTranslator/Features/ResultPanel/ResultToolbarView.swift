import AppKit
import SnapTranslatorCore
import SwiftUI

/// 一体化毛玻璃顶部标题工具栏（精准避让左上角红绿灯，消除割裂的空白标题条）
struct ResultToolbarView: View {
    @Environment(\.stUIFontSize) private var uiFontSize
    @ObservedObject var model: ResultModel
    @ObservedObject var settings: SettingsStore

    let onStartCapture: () -> Void
    let onCollect: (String, String) -> Void
    let onRetry: () -> Void
    let onTogglePin: () -> Void
    let onOpenWordBook: () -> Void
    let onOpenHistory: () -> Void
    let onToggleCompare: () -> Void

    @Namespace private var tabAnimation
    @State private var justCopied = false
    @State private var retryAngle: Double = 0
    @State private var hoveredTab: PanelTab?

    var body: some View {
        HStack(spacing: 8) {
            // 左侧预留红绿灯窗口控制区，视觉齐平
            tabBar

            Spacer(minLength: 8)

            // 快捷截屏入口按钮
            ToolbarIconButton(
                systemImage: "viewfinder",
                tooltip: "截屏翻译 (\(settings.hotkeyCapture.display))",
                iconColor: Color.accentColor
            ) {
                onStartCapture()
            }

            if model.phase == .done || !model.translatedText.isEmpty {
                ToolbarButton(
                    title: activeSelection.isEmpty ? "收藏" : "收藏选中",
                    systemImage: activeSelection.isEmpty ? "bookmark" : "bookmark.fill",
                    tooltip: activeSelection.isEmpty ? "收藏整句到生词本" : "收藏选中词条到生词本",
                    isDisabled: model.sourceText.isEmpty && model.translatedText.isEmpty
                ) {
                    let phrase = activeSelection.isEmpty
                        ? (model.sourceText.isEmpty ? model.translatedText : model.sourceText)
                        : activeSelection
                    let ctx = model.sourceText.isEmpty ? model.translatedText : model.sourceText
                    onCollect(phrase, ctx)
                }
            }

            headerDivider

            if model.tab == .translation {
                ToolbarIconButton(
                    systemImage: "rectangle.split.2x2",
                    tooltip: model.compareEnabled
                        ? "关闭双引擎对比"
                        : "开启双引擎对比（对比 \(settings.compareSecondaryEngine.shortName)）",
                    isActive: model.compareEnabled,
                    isDisabled: settings.offlineOnlyMode
                ) {
                    onToggleCompare()
                }
            }

            ToolbarIconButton(systemImage: "clock.arrow.circlepath", tooltip: "识别历史 (⌘H)") {
                onOpenHistory()
            }

            ToolbarIconButton(systemImage: "books.vertical", tooltip: "生词本") {
                onOpenWordBook()
            }

            headerDivider

            ToolbarIconButton(
                systemImage: justCopied ? "checkmark" : "doc.on.doc",
                tooltip: "复制译文或原文 (⌘C)",
                iconColor: justCopied ? .green : nil,
                isDisabled: model.translatedText.isEmpty && model.sourceText.isEmpty
            ) {
                let copiedTranslation = !model.translatedText.isEmpty
                let text = copiedTranslation ? model.translatedText : model.sourceText
                NSPasteboard.writeString(text)
                withAnimation(.spring(response: 0.25, dampingFraction: 0.65)) { justCopied = true }
                model.showNotice(copiedTranslation ? "已复制译文" : "已复制原文", kind: .success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { justCopied = false }
                }
            }

            ToolbarIconButton(
                systemImage: settings.alwaysOnTop ? "pin.fill" : "pin",
                tooltip: settings.alwaysOnTop ? "取消置顶" : "置顶窗口",
                isActive: settings.alwaysOnTop
            ) {
                onTogglePin()
            }

            ToolbarIconButton(
                systemImage: "arrow.clockwise",
                tooltip: "重新识别与翻译 (⌘R)",
                rotationAngle: retryAngle,
                isDisabled: model.image == nil && model.sourceText.isEmpty
            ) {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { retryAngle += 360 }
                onRetry()
            }
        }
        .padding(.leading, 82) // unifiedCompact 下红绿灯右缘为 72pt，留出 10pt 呼吸间距
        .padding(.trailing, 10)
        .frame(height: max(40, uiFontSize + 27))
        .background(.bar)
    }

    private var headerDivider: some View {
        Rectangle()
            .fill(STTheme.hairlineBorder)
            .frame(width: 1, height: 14)
            .padding(.horizontal, 1)
    }

    private var activeSelection: String {
        !model.selectedText.isEmpty ? model.selectedText : model.leftSelectedText
    }

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(PanelTab.allCases) { tab in
                let isSelected = model.tab == tab
                let isEnabled = (model.phase == .done || model.phase == .idle)
                let isHovered = hoveredTab == tab

                Button {
                    guard isEnabled else { return }
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { model.tab = tab }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: tab.iconName)
                            .font(.system(size: max(11, uiFontSize - 1), weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                        Text(tab.rawValue)
                            .font(.system(size: uiFontSize, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? Color.primary : (isHovered ? Color.primary : Color.secondary))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4.5)
                    .background {
                        ZStack {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(STTheme.panelSurface)
                                    .shadow(color: Color.black.opacity(0.10), radius: 2.5, x: 0, y: 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                            .stroke(STTheme.hairlineBorder, lineWidth: 0.5)
                                    )
                                    .matchedGeometryEffect(id: "activeTabBackground", in: tabAnimation)
                            } else if isHovered && isEnabled {
                                RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                    .fill(STTheme.subtleFill)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .opacity(isEnabled ? 1.0 : 0.45)
                .onHover { inside in if isEnabled { hoveredTab = inside ? tab : nil } }
                .hoverFeedback(tab.tooltip)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.055))
        )
    }
}
