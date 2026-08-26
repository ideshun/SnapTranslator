import AppKit
import SwiftUI

/// 快捷键录制控件：点击进入录制态，按下组合键即捕获
struct HotkeyRecorder: NSViewRepresentable {
    @Binding var spec: HotkeySpec

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.current = spec
        view.onRecord = { newSpec in
            if let newSpec {
                spec = newSpec
            }
        }
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        if view.current != spec {
            view.current = spec
            view.needsDisplay = true
        }
    }
}

final class RecorderView: NSView {
    var onRecord: ((HotkeySpec?) -> Void)?
    var current: HotkeySpec?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        NSColor.separatorColor.setStroke()
        let border = NSBezierPath(roundedRect: NSInsetRect(bounds, 0.5, 0.5), xRadius: 6, yRadius: 6)
        border.lineWidth = 1
        border.stroke()

        let title: String
        var color: NSColor = .labelColor
        if recording {
            title = "按下新快捷键…（ESC 取消）"
            color = .systemBlue
        } else if let current {
            title = current.display
        } else {
            title = "点击录入快捷键"
            color = .secondaryLabelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: color,
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: bounds.midX - size.width / 2,
            y: bounds.midY - size.height / 2
        )
        (title as NSString).draw(at: origin, withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        recording = true
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        // ESC 取消录制
        if event.keyCode == 53 {
            recording = false
            needsDisplay = true
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard flags.contains(.command) || flags.contains(.option) || flags.contains(.control)
        else {
            NSSound.beep()
            return
        }
        let newSpec = HotkeySpec(
            keyCode: UInt32(event.keyCode),
            modifiers: HotkeySpec.carbon(from: flags)
        )
        current = newSpec
        recording = false
        needsDisplay = true
        onRecord?(newSpec)
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        needsDisplay = true
        return true
    }
}
