import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Click-to-record shortcut field.
///
/// Uses a local event monitor rather than a first-responder NSView because the
/// settings window hosts SwiftUI, and a monitor is far less fragile than
/// fighting SwiftUI for responder status.
struct HotKeyRecorder: View {
    var onChange: () -> Void

    @State private var isRecording = false
    @State private var display = HotKeyManager.describeCurrentBinding()
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording { stopRecording() } else { startRecording() }
        } label: {
            Text(isRecording ? "Press keys\u{2026}" : display)
                .font(.system(size: 12, design: .rounded))
                .frame(minWidth: 90)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isRecording ? Color.accentColor.opacity(0.2)
                                          : Color(nsColor: .quaternaryLabelColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isRecording ? Color.accentColor : Color.clear, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            guard event.type == .keyDown else { return nil }

            // Escape abandons the recording rather than binding Escape.
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            let carbonModifiers = Self.carbonModifiers(from: event.modifierFlags)
            // A bare key would swallow that key system-wide, so require at
            // least one of Command / Control / Option.
            guard carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0 else {
                NSSound.beep()
                return nil
            }

            Preferences.shared.hotKeyCode = UInt32(event.keyCode)
            Preferences.shared.hotKeyModifiers = carbonModifiers
            display = HotKeyManager.describeCurrentBinding()
            stopRecording()
            onChange()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
    }

    /// NSEvent flags -> the Carbon bitmask `RegisterEventHotKey` expects.
    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift)   { result |= UInt32(shiftKey) }
        if flags.contains(.option)  { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}
