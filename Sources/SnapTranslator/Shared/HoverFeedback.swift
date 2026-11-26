import AppKit
import SwiftUI

/// 统一悬浮反馈 modifier：
/// 使用计数管理 pointingHand 光标，避免多个控件同时切换或嵌套时出现 NSCursor 栈失衡卡死
@MainActor
private final class HoverCursorTracker {
    static let shared = HoverCursorTracker()
    private var depth = 0

    func enter() {
        depth += 1
        if depth == 1 {
            NSCursor.pointingHand.push()
        }
    }

    func leave() {
        guard depth > 0 else { return }
        depth -= 1
        if depth == 0 {
            NSCursor.pop()
        }
    }
}

private struct HoverFeedback: ViewModifier {
    var tooltip: String?
    @State private var hovering = false

    func body(content: Content) -> some View {
        let base = content
            .onHover { inside in
                guard inside != hovering else { return }
                hovering = inside
                if inside {
                    HoverCursorTracker.shared.enter()
                } else {
                    HoverCursorTracker.shared.leave()
                }
            }
            .onDisappear {
                if hovering {
                    HoverCursorTracker.shared.leave()
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
    func hoverFeedback(_ tooltip: String? = nil) -> some View {
        modifier(HoverFeedback(tooltip: tooltip))
    }
}
