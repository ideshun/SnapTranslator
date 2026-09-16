import AppKit
import SwiftUI

/// 统一悬浮反馈 modifier：鼠标悬停时显示小手（pointingHand）光标，
/// 可选附带功能名称 tooltip。用于所有可交互元素（按钮/菜单/分段控件/列表行），
/// 保证全应用悬浮行为与样式一致。
private struct HoverFeedback: ViewModifier {
    var tooltip: String?
    @State private var hovering = false

    func body(content: Content) -> some View {
        let base = content
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
            // 视图在悬停中被移除（如禁用/切换页签）时 onHover(false) 不保证触发，
            // 这里兜底弹掉光标，避免小手卡住
            .onDisappear {
                if hovering {
                    NSCursor.pop()
                    hovering = false
                }
            }
        if let tooltip, !tooltip.isEmpty {
            base.help(tooltip)
        } else {
            base
        }
    }
}

extension View {
    /// 统一悬浮反馈：小手光标 + tooltip（tooltip 传空则只给光标）
    func hoverFeedback(_ tooltip: String? = nil) -> some View {
        modifier(HoverFeedback(tooltip: tooltip))
    }
}
