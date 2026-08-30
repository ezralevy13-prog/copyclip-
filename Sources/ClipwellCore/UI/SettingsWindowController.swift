import AppKit
import SwiftUI

/// Holds the settings window so it survives being closed and reopened.
@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let onHotKeyChanged: () -> Void

    init(store: HistoryStore, monitor: ClipboardMonitor, onHotKeyChanged: @escaping () -> Void) {
        self.store = store
        self.monitor = monitor
        self.onHotKeyChanged = onHotKeyChanged
    }

    func show() {
        if window == nil {
            let view = SettingsView(store: store, monitor: monitor, onHotKeyChanged: onHotKeyChanged)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 460),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Preferences"
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }
        // Settings is a real window, so the app does come forward here --
        // unlike the history panel, which must never steal focus.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
