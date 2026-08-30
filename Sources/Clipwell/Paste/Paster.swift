import Foundation
import AppKit
import Carbon.HIToolbox

/// Puts an item back on the pasteboard and, optionally, presses Cmd-V for you.
enum Paster {

    /// Restores every stored representation, rebuilding the original multi-item
    /// structure. This is what makes a paste land with the same fidelity as the
    /// original copy -- formatting intact in Word, image intact in Photoshop.
    static func writeToPasteboard(itemID: Int64, store: HistoryStore, plainTextOnly: Bool) {
        let groups = store.representations(for: itemID)
        guard !groups.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if plainTextOnly {
            // Strip everything but text: paste-as-plain-text, which is the one
            // thing people reliably want a modifier for.
            let text = groups.compactMap { group -> String? in
                for uti in UTIs.plainTextFamily {
                    if let data = group[uti], let string = String(data: data, encoding: .utf8) { return string }
                }
                return nil
            }.joined(separator: "\n")

            if !text.isEmpty {
                pasteboard.setString(text, forType: .string)
                return
            }
        }

        var pasteboardItems: [NSPasteboardItem] = []
        for group in groups {
            let pasteboardItem = NSPasteboardItem()
            for (uti, data) in group {
                pasteboardItem.setData(data, forType: NSPasteboard.PasteboardType(uti))
            }
            pasteboardItems.append(pasteboardItem)
        }
        pasteboard.writeObjects(pasteboardItems)
    }

    /// Synthesizes Cmd-V into whatever app currently has focus.
    ///
    /// Requires Accessibility permission. The panel is a non-activating one, so
    /// the app the user was in never lost focus and receives this directly.
    static func sendPasteKeystroke() {
        guard hasAccessibilityPermission() else {
            Log.paste.warning("no accessibility permission; skipping synthetic paste")
            return
        }

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        // Suppress our own synthetic events from being re-read as local input.
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyCode = CGKeyCode(kVK_ANSI_V)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cgAnnotatedSessionEventTap)
        keyUp.post(tap: .cgAnnotatedSessionEventTap)
    }

    static func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system permission prompt. Only call in response to the user
    /// asking for it -- an unsolicited prompt at launch is obnoxious.
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
