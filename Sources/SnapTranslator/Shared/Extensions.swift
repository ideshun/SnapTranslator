import AppKit
import CoreGraphics

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
