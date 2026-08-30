import Foundation
import Carbon.HIToolbox
import AppKit

/// Global hotkey registration via Carbon's `RegisterEventHotKey`.
///
/// Carbon is ancient, but it remains the only way to get a system-wide hotkey
/// without requiring Accessibility permission -- a CGEventTap would work too
/// and would need that permission just to open the window.
final class HotKeyManager {

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let signature: OSType = 0x434C5057 // 'CLPW'
    private let hotKeyID: UInt32 = 1

    /// Carbon's callback is a bare C function pointer and cannot capture
    /// context, so the handler is reached through this global.
    fileprivate static var handlers: [UInt32: () -> Void] = [:]

    var onTrigger: (() -> Void)? {
        didSet { HotKeyManager.handlers[hotKeyID] = onTrigger }
    }

    func register() {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &eventType, nil, &eventHandler)

        var hotKeyID = EventHotKeyID(signature: signature, id: self.hotKeyID)
        let status = RegisterEventHotKey(
            Preferences.shared.hotKeyCode,
            Preferences.shared.hotKeyModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status != noErr {
            Log.ui.error("hotkey registration failed with status \(status, privacy: .public)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    deinit { unregister() }

    /// Human-readable form of the current binding, for the settings UI.
    static func describeCurrentBinding() -> String {
        let modifiers = Preferences.shared.hotKeyModifiers
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("^") }
        if modifiers & UInt32(optionKey)  != 0 { parts.append("\u{2325}") }
        if modifiers & UInt32(shiftKey)   != 0 { parts.append("\u{21E7}") }
        if modifiers & UInt32(cmdKey)     != 0 { parts.append("\u{2318}") }
        parts.append(keyName(for: Preferences.shared.hotKeyCode))
        return parts.joined()
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D",
            kVK_ANSI_E: "E", kVK_ANSI_F: "F", kVK_ANSI_G: "G", kVK_ANSI_H: "H",
            kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P",
            kVK_ANSI_Q: "Q", kVK_ANSI_R: "R", kVK_ANSI_S: "S", kVK_ANSI_T: "T",
            kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_Space: "Space"
        ]
        return names[Int(keyCode)] ?? "Key\(keyCode)"
    }
}

/// C callback trampoline. Dispatches to the registered Swift closure.
private func hotKeyEventHandler(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
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
    guard status == noErr else { return status }

    if let handler = HotKeyManager.handlers[hotKeyID.id] {
        DispatchQueue.main.async { handler() }
    }
    return noErr
}
