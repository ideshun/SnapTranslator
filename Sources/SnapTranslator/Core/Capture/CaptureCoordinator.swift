import AppKit

/// 截屏流程编排：瞬间定格 → 遮罩框选 → 精准裁剪 → 回调
@MainActor
final class CaptureCoordinator {
    private var overlays: [OverlayWindow] = []
    private var escMonitor: Any?

    var onCaptured: ((NSImage, CGRect) -> Void)?
    var onPermissionDenied: (() -> Void)?
    /// 用户取消框选（Esc / 右键）时回调，供上层恢复被隐藏的翻译面板
    var onCancelled: (() -> Void)?

    private static let lastRectKey = "st.lastCaptureRect"

    // MARK: - 框选流程

    /// 开始框选：瞬间抓取所有屏幕画面定格，并覆盖遮罩
    func begin() {
        guard overlays.isEmpty else { return }

        // ① 瞬间定格：在激活应用/转移焦点前立刻抓取各屏幕的整屏快照！
        // 确保右键菜单、下拉列表、Hover 浮层、临时提示等瞬间被冻结在内存底图中
        var screenSnapshots: [CGDirectDisplayID: CGImage] = [:]
        for screen in NSScreen.screens {
            if let snapshot = ScreenCapture.captureScreen(displayID: screen.displayID) {
                screenSnapshots[screen.displayID] = snapshot
            }
        }

        // ② 判定当前光标所在屏幕，优先将该屏幕的 Overlay 设为 KeyWindow
        let mouseLocation = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main

        NSApp.activate(ignoringOtherApps: true)

        for screen in NSScreen.screens {
            let snapshot = screenSnapshots[screen.displayID]
            let overlay = OverlayWindow(screen: screen, snapshot: snapshot)
            overlay.onRegionSelected = { [weak self] globalRect, localRect, frozenSnapshot in
                self?.finishSelection(
                    globalRect: globalRect,
                    localRect: localRect,
                    screen: screen,
                    snapshot: frozenSnapshot
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

        NSCursor.crosshair.push()
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            Task { @MainActor in
                self?.cancel()
            }
            return nil
        }
    }

    func cancel() {
        teardownOverlays()
        onCancelled?()
    }

    private func finishSelection(
        globalRect: CGRect,
        localRect: CGRect,
        screen: NSScreen,
        snapshot: CGImage?
    ) {
        teardownOverlays()

        // 优先从内存中的定格画面直接裁剪（零延迟 + 100% 保持按下瞬间的状态）
        if let snapshot,
           let croppedImage = ScreenCapture.crop(image: snapshot, screenFrame: screen.frame, localPointRect: localRect) {
            Self.saveLastRect(globalRect)
            onCaptured?(croppedImage, globalRect)
            return
        }

        // 兜底回退：若无底图快照则现场直接截图
        capture(rect: globalRect)
    }

    private func teardownOverlays() {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        if let escMonitor {
            NSEvent.removeMonitor(escMonitor)
            self.escMonitor = nil
        }
        NSCursor.pop()
    }

    // MARK: - 直接截图

    /// 直接截取全局坐标区域（重截上次区域时使用）
    func capture(rect: CGRect) {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        guard let screen else { return }
        let clamped = rect.intersection(screen.frame)
        guard clamped.width > 4, clamped.height > 4 else { return }

        // 全局 AppKit 坐标 → 屏幕内坐标（原点左上）
        let rectInDisplay = CGRect(
            x: clamped.minX - screen.frame.minX,
            y: screen.frame.maxY - clamped.maxY,
            width: clamped.width,
            height: clamped.height
        )
        guard let image = ScreenCapture.capture(displayID: screen.displayID, rect: rectInDisplay) else {
            onPermissionDenied?()
            return
        }
        Self.saveLastRect(clamped)
        onCaptured?(image, clamped)
    }

    // MARK: - 上次选区记忆

    static func lastRect() -> CGRect? {
        guard let raw = UserDefaults.standard.string(forKey: lastRectKey) else { return nil }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    /// 上次选区适配当前屏幕布局：完全离开所有屏幕时平移回主屏
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
