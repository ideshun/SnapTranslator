import AppKit
import Carbon.HIToolbox

/// 全局快捷键：Carbon RegisterEventHotKey，无需辅助功能权限
public final class HotkeyManager {
    public enum Action: UInt32, CaseIterable, Sendable {
        case capture = 1
        case recapture = 2
        case togglePanel = 3
        case silentOCR = 4
        case translateClipboard = 5
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let handler: () -> Void
    }

    private var registrations: [Action: Registration] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private static let signature: OSType = 0x53545241 // 'STRA'

    public init() {}

    deinit {
        unregisterAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// 注册快捷键，键位冲突等失败时返回 false 并记录日志
    @discardableResult
    public func register(_ action: Action, spec: HotkeySpec, handler: @escaping () -> Void) -> Bool {
        unregister(action)
        guard spec.hasFunctionalModifier else {
            AppLogger.hotkey.warning("拒绝无功能修饰键的快捷键 action=\(action.rawValue) spec=\(spec.display, privacy: .public)")
            return false
        }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: action.rawValue)
        let status = RegisterEventHotKey(
            spec.keyCode,
            spec.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            AppLogger.hotkey.error("注册全局快捷键失败 action=\(action.rawValue) spec=\(spec.display, privacy: .public) status=\(status)")
            return false
        }
        registrations[action] = Registration(ref: ref, handler: handler)
        installEventHandlerIfNeeded()
        return true
    }

    public func unregister(_ action: Action) {
        if let registration = registrations.removeValue(forKey: action) {
            UnregisterEventHotKey(registration.ref)
        }
    }

    public func unregisterAll() {
        for action in Action.allCases {
            unregister(action)
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil, !registrations.isEmpty else { return }
        var eventSpec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
            manager.dispatch(hotKeyID.id)
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventSpec,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )
    }

    private func dispatch(_ rawID: UInt32) {
        guard let action = Action(rawValue: rawID),
              let registration = registrations[action]
        else { return }
        if Thread.isMainThread {
            registration.handler()
        } else {
            DispatchQueue.main.async(execute: registration.handler)
        }
    }
}
