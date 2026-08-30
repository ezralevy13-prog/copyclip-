import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var store: HistoryStore?
    private var monitor: ClipboardMonitor?
    private var panel: PanelController?
    private var settings: SettingsWindowController?
    private var menuBar: MenuBarController?
    private let hotKey = HotKeyManager()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store: HistoryStore
        do {
            store = try HistoryStore()
        } catch {
            presentFatal(error)
            return
        }

        let monitor = ClipboardMonitor(store: store)
        let panel = PanelController(store: store, monitor: monitor)
        let settings = SettingsWindowController(store: store, monitor: monitor) { [weak self] in
            self?.hotKey.register()
        }

        self.store = store
        self.monitor = monitor
        self.panel = panel
        self.settings = settings
        self.menuBar = MenuBarController(store: store, monitor: monitor, panel: panel, settings: settings)

        // The Carbon callback is not actor-isolated, so hop explicitly.
        hotKey.onTrigger = { [weak panel] in
            Task { @MainActor in panel?.toggle() }
        }
        hotKey.register()
        monitor.start()

        Log.ui.info("Clipwell launched; storage at \(store.storageRoot.path, privacy: .public)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKey.unregister()
    }

    /// Menu-bar app: closing the settings window shouldn't quit.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func presentFatal(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Clipwell couldn't open its database"
        alert.informativeText = String(describing: error)
        alert.runModal()
        NSApp.terminate(nil)
    }
}
