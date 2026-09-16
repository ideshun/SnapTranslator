import AppKit
import CoreGraphics

/// 屏幕截图：CGDisplayCreateImage 截取指定屏幕的指定区域（Retina 自动处理）
enum ScreenCapture {
    /// 权限预检（不触发系统弹窗）
    static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 截取全屏幕原始画面（用于截屏框选前定格瞬态界面与悬浮菜单）
    static func captureScreen(displayID: CGDirectDisplayID) -> CGImage? {
        guard displayID != 0 else { return nil }
        let bounds = CGDisplayBounds(displayID)
        return CGDisplayCreateImage(displayID, rect: CGRect(origin: .zero, size: bounds.size))
    }

    /// 从全屏定格截图中根据屏幕点坐标裁剪出局部图像（自动处理 Retina 像素比率）
    static func crop(image: CGImage, screenFrame: CGRect, localPointRect: CGRect) -> NSImage? {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return nil }
        let scaleX = CGFloat(image.width) / screenFrame.width
        let scaleY = CGFloat(image.height) / screenFrame.height
        let pixelRect = CGRect(
            x: localPointRect.origin.x * scaleX,
            y: localPointRect.origin.y * scaleY,
            width: localPointRect.width * scaleX,
            height: localPointRect.height * scaleY
        )
        guard let cropped = image.cropping(to: pixelRect) else { return nil }
        return NSImage(
            cgImage: cropped,
            size: NSSize(width: localPointRect.width, height: localPointRect.height)
        )
    }

    /// 截取屏幕区域（动态截取，备用兜底），未授权时返回 nil
    static func capture(displayID: CGDirectDisplayID, rect: CGRect) -> NSImage? {
        guard displayID != 0 else { return nil }
        guard let cgImage = CGDisplayCreateImage(displayID, rect: rect) else { return nil }
        return NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
