import AppKit
import SwiftUI

/// 轻量悬浮 HUD 提示器：用于静默 OCR / 截图保存等不唤起主面板的场景
@MainActor
final class HUDNotifier {
    static let shared = HUDNotifier()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ message: String, systemImage: String = "checkmark.circle.fill", duration: Double = 2.0) {
        hideTask?.cancel()

        let view = HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.green)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        .padding(8)

        let hosting = NSHostingView(rootView: view)
        let fitting = hosting.fittingSize

        let hud: NSPanel
        if let existing = panel {
            hud = existing
        } else {
            hud = NSPanel(
                contentRect: NSRect(origin: .zero, size: fitting),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            hud.level = .statusBar
            hud.isOpaque = false
            hud.backgroundColor = .clear
            hud.hasShadow = false
            hud.ignoresMouseEvents = true
            hud.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel = hud
        }

        hud.contentView = hosting
        hud.setContentSize(fitting)
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            hud.setFrameOrigin(NSPoint(
                x: visible.midX - fitting.width / 2,
                y: visible.minY + 64
            ))
        }
        hud.alphaValue = 1
        hud.orderFrontRegardless()

        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
        }
    }
}
