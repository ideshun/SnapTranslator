import AppKit
import CoreGraphics

/// 屏幕截图：CGDisplayCreateImage 截取指定屏幕的指定区域（Retina 自动处理）
enum ScreenCapture {
    /// 权限预检（不触发系统弹窗）
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 截取屏幕区域，未授权时返回 nil
    static func capture(displayID: CGDirectDisplayID, rect: CGRect) -> NSImage? {
        guard displayID != 0 else { return nil }
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
