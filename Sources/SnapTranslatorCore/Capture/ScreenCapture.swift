import AppKit
import CoreGraphics
import ScreenCaptureKit

/// 现代屏幕截图引擎：
/// - 基于 macOS 14+ ScreenCaptureKit（SCScreenshotManager），彻底替代已废弃的 CGDisplayCreateImage
/// - 可通过 SCContentFilter 原生排除 SnapTranslator 自身窗口，截图不入镜且无需闪隐面板
/// - 统一 Retina 语义：返回 NSImage.size 始终为逻辑点尺寸
public enum ScreenCapture {
    public static var hasPermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    public static func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    public static func captureAllScreens(excludingOwnWindows: Bool) async -> [CGDirectDisplayID: CGImage] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let excludedApps = excludingOwnWindows
                ? content.applications.filter { $0.processID == ownPID }
                : []

            var snapshots: [CGDirectDisplayID: CGImage] = [:]
            for display in content.displays {
                let filter = SCContentFilter(
                    display: display,
                    excludingApplications: excludedApps,
                    exceptingWindows: []
                )
                let config = SCStreamConfiguration()
                let scale = backingScaleFactor(for: display.displayID)
                config.width = Int(CGFloat(display.width) * scale)
                config.height = Int(CGFloat(display.height) * scale)
                config.showsCursor = false
                config.capturesAudio = false

                if let cgImage = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                ) {
                    snapshots[display.displayID] = cgImage
                }
            }
            return snapshots
        } catch {
            AppLogger.capture.warning("ScreenCaptureKit 全屏抓取失败: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
    }

    public static func captureRegion(
        displayID: CGDirectDisplayID,
        localTopLeftPointRect: CGRect,
        excludingOwnWindows: Bool
    ) async -> NSImage? {
        guard displayID != 0, localTopLeftPointRect.width > 4, localTopLeftPointRect.height > 4 else {
            return nil
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
                return nil
            }
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let excludedApps = excludingOwnWindows
                ? content.applications.filter { $0.processID == ownPID }
                : []
            let filter = SCContentFilter(
                display: display,
                excludingApplications: excludedApps,
                exceptingWindows: []
            )
            let scale = backingScaleFactor(for: displayID)
            let config = SCStreamConfiguration()
            config.sourceRect = localTopLeftPointRect
            config.width = max(1, Int((localTopLeftPointRect.width * scale).rounded()))
            config.height = max(1, Int((localTopLeftPointRect.height * scale).rounded()))
            config.showsCursor = false
            config.capturesAudio = false

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return NSImage(
                cgImage: cgImage,
                size: NSSize(width: localTopLeftPointRect.width, height: localTopLeftPointRect.height)
            )
        } catch {
            AppLogger.capture.error("ScreenCaptureKit 局部截图失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    public static func crop(image: CGImage, screenFrame: CGRect, localPointRect: CGRect) -> NSImage? {
        guard screenFrame.width > 0, screenFrame.height > 0 else { return nil }
        let scaleX = CGFloat(image.width) / screenFrame.width
        let scaleY = CGFloat(image.height) / screenFrame.height
        let pixelRect = CGRect(
            x: max(0, localPointRect.origin.x * scaleX),
            y: max(0, localPointRect.origin.y * scaleY),
            width: localPointRect.width * scaleX,
            height: localPointRect.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))

        guard pixelRect.width >= 2, pixelRect.height >= 2,
              let cropped = image.cropping(to: pixelRect)
        else { return nil }

        return NSImage(
            cgImage: cropped,
            size: NSSize(width: localPointRect.width, height: localPointRect.height)
        )
    }

    private static func backingScaleFactor(for displayID: CGDirectDisplayID) -> CGFloat {
        if let screen = NSScreen.screens.first(where: { $0.displayID == displayID }) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }
}
