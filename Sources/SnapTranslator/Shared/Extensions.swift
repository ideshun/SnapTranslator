import AppKit
import CoreGraphics

/// 文本面板滚动视图：macOS 27 SDK 起 NSScrollView 不再把文本视图宽度自动铺满可视区
/// （程序化创建的 NSTextView 初始宽度保持 0，表现为整个文本面板空白），
/// 在布局时显式把 documentView 宽度同步为可视区宽度
class TextPaneScrollView: NSScrollView {
    override func layout() {
        super.layout()
        guard let textView = documentView as? NSTextView else { return }
        let targetWidth = contentView.frame.width
        if targetWidth > 0, abs(textView.frame.width - targetWidth) > 0.5 {
            textView.frame.size.width = targetWidth
        }
    }
}

extension NSImage {
    /// 通用 CGImage 转换：走 TIFF 编解码，兼容所有 NSImage 表示
    var cgImage: CGImage? {
        guard let tiff = tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff)
        else { return nil }
        return rep.cgImage
    }
}

extension NSScreen {
    /// 屏幕的 CGDirectDisplayID
    var displayID: CGDirectDisplayID {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
    }
}

extension NSPasteboard {
    /// 清空后写入纯文本
    static func writeString(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
