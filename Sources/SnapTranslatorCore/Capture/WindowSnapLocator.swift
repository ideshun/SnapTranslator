import AppKit
import CoreGraphics

/// QQ 式窗口吸附定位器：查询光标下最上层的普通应用窗口
public enum WindowSnapLocator {
    public static func windowRect(under mouse: NSPoint, primaryTopY: CGFloat) -> CGRect? {
        guard let infos = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let cgPoint = CGPoint(x: mouse.x, y: primaryTopY - mouse.y)

        for info in infos {
            guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID else { continue }
            guard (info[kCGWindowLayer as String] as? Int ?? 0) == 0 else { continue }
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha <= 0.01 { continue }
            guard let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let cgRect = CGRect(dictionaryRepresentation: bounds)
            else { continue }
            guard cgRect.width > 48, cgRect.height > 48, cgRect.contains(cgPoint) else { continue }

            return CGRect(
                x: cgRect.minX,
                y: primaryTopY - cgRect.maxY,
                width: cgRect.width,
                height: cgRect.height
            )
        }
        return nil
    }
}
