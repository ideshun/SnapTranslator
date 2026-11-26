import AppKit
import SnapTranslatorCore

/// 截屏后的执行动作
public enum CaptureAction: String, CaseIterable, Identifiable {
    case translate = "翻译"
    case silentOCR = "仅提文字"
    case pinImage = "贴图置顶"
    case saveImage = "保存截图"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .translate: return "character.bubble"
        case .silentOCR: return "doc.text.viewfinder"
        case .pinImage: return "pin"
        case .saveImage: return "square.and.arrow.down"
        }
    }
}

/// 截屏流程编排：ScreenCaptureKit 瞬间定格（原生排除自身面板） → 多屏遮罩框选/窗口吸附 → 裁剪回调
@MainActor
final class CaptureCoordinator {
    private var overlays: [OverlayWindow] = []
    private var escMonitor: Any?
    private var captureTask: Task<Void, Never>?
    private var crosshairPushed = false

    var onCaptured: ((NSImage, CGRect, CaptureAction) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var onCancelled: (() -> Void)?
    var onDirectCaptureFailed: (() -> Void)?

    private static let lastRectKey = "st.lastCaptureRect"

    /// 开始交互式框选
    func begin(
        defaultAction: CaptureAction = .translate,
        refineMode: Bool = false,
        excludeOwnWindows: Bool = true
    ) {
        guard overlays.isEmpty else { return }

        if !ScreenCapture.hasPermission {
            _ = ScreenCapture.requestPermission()
            onPermissionDenied?()
            return
        }

        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            let screenSnapshots = await ScreenCapture.captureAllScreens(excludingOwnWindows: excludeOwnWindows)
            guard !Task.isCancelled else { return }
            self.presentOverlays(
                snapshots: screenSnapshots,
                defaultAction: defaultAction,
                refineMode: refineMode
            )
        }
    }

    private func presentOverlays(
        snapshots: [CGDirectDisplayID: CGImage],
        defaultAction: CaptureAction,
        refineMode: Bool
    ) {
        guard overlays.isEmpty else { return }
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main

        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let snapshot = snapshots[screen.displayID]
            let overlay = OverlayWindow(
                screen: screen,
                snapshot: snapshot,
                defaultAction: defaultAction,
                refineMode: refineMode
            )
            overlay.onRegionSelected = { [weak self] globalRect, localRect, frozenSnapshot, action in
                self?.finishSelection(
                    globalRect: globalRect,
                    localRect: localRect,
                    screen: screen,
                    snapshot: frozenSnapshot,
                    action: action
                )
            }
            overlay.onCancelled = { [weak self] in
                self?.cancel()
            }
            overlays.append(overlay)
            overlay.orderFront(nil)
            if screen == activeScreen {
                overlay.makeKeyAndOrderFront(nil)
            }
        }

        if !crosshairPushed {
            NSCursor.crosshair.push()
            crosshairPushed = true
        }
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // ESC
                Task { @MainActor in self?.cancel() }
                return nil
            }
            return event
        }
    }

    func cancel() {
        captureTask?.cancel()
        teardownOverlays()
        onCancelled?()
    }

    private func finishSelection(
        globalRect: CGRect,
        localRect: CGRect,
        screen: NSScreen,
        snapshot: CGImage?,
        action: CaptureAction
    ) {
        teardownOverlays()

        if let snapshot,
           let croppedImage = ScreenCapture.crop(
               image: snapshot,
               screenFrame: screen.frame,
               localPointRect: localRect
           ) {
            Self.saveLastRect(globalRect)
            onCaptured?(croppedImage, globalRect, action)
            return
        }

        capture(rect: globalRect, action: action, excludeOwnWindows: true)
    }

    private func teardownOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        if crosshairPushed {
            NSCursor.pop()
            crosshairPushed = false
        }
    }

    // MARK: - 直接截图（重截上次区域）

    func capture(rect: CGRect, action: CaptureAction = .translate, excludeOwnWindows: Bool = true) {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        guard let screen else {
            onDirectCaptureFailed?()
            return
        }
        let clamped = rect.intersection(screen.frame)
        guard clamped.width > 4, clamped.height > 4 else {
            onDirectCaptureFailed?()
            return
        }

        let rectInDisplay = CGRect(
            x: clamped.minX - screen.frame.minX,
            y: screen.frame.maxY - clamped.maxY,
            width: clamped.width,
            height: clamped.height
        )

        captureTask?.cancel()
        captureTask = Task { [weak self] in
            guard let self else { return }
            let image = await ScreenCapture.captureRegion(
                displayID: screen.displayID,
                localTopLeftPointRect: rectInDisplay,
                excludingOwnWindows: excludeOwnWindows
            )
            guard !Task.isCancelled else { return }
            guard let image else {
                if !ScreenCapture.hasPermission {
                    self.onPermissionDenied?()
                }
                self.onDirectCaptureFailed?()
                return
            }
            Self.saveLastRect(clamped)
            self.onCaptured?(image, clamped, action)
        }
    }

    // MARK: - 上次选区记忆

    static func lastRect() -> CGRect? {
        guard let raw = UserDefaults.standard.string(forKey: lastRectKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    static func adjustedLastRect() -> CGRect? {
        guard let last = lastRect() else { return nil }
        for screen in NSScreen.screens where screen.frame.intersects(last) {
            return last.intersection(screen.frame)
        }
        guard let main = NSScreen.main else { return nil }
        return CGRect(
            x: main.frame.minX + 40,
            y: main.frame.maxY - last.height - 80,
            width: last.width,
            height: last.height
        )
    }

    private static func saveLastRect(_ rect: CGRect) {
        let raw = "\(rect.origin.x),\(rect.origin.y),\(rect.width),\(rect.height)"
        UserDefaults.standard.set(raw, forKey: lastRectKey)
    }
}
