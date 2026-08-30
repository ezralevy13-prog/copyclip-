import AppKit

/// The status-bar item: left-click opens history, right-click opens the menu.
@MainActor
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    private let panel: PanelController
    private let settings: SettingsWindowController

    init(store: HistoryStore,
         monitor: ClipboardMonitor,
         panel: PanelController,
         settings: SettingsWindowController) {
        self.store = store
        self.monitor = monitor
        self.panel = panel
        self.settings = settings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // NSObject subclass: @objc selectors for the status item and menu
        // actions require Objective-C runtime visibility.
        super.init()

        configureButton()
        observeSkippedSecrets()
    }

    // MARK: - Skipped-secret feedback

    private var skipFeedbackWorkItem: DispatchWorkItem?

    /// Silently dropping a copy would leave the user thinking the app is
    /// broken, so the icon briefly changes to say what happened.
    private func observeSkippedSecrets() {
        NotificationCenter.default.addObserver(
            forName: ClipboardMonitor.didSkipSecretNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Task rather than MainActor.assumeIsolated, which is macOS 14+.
            let reason = notification.userInfo?["reason"] as? String
            Task { @MainActor in self?.flashSkipped(reason: reason) }
        }
    }

    private func flashSkipped(reason: String?) {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "lock.shield.fill",
            accessibilityDescription: "Skipped a copy that looked like a secret"
        )
        button.image?.isTemplate = true
        button.toolTip = reason.map { "Not recorded: \($0)" }

        skipFeedbackWorkItem?.cancel()
        let restore = DispatchWorkItem { [weak self] in
            self?.configureButton()
            self?.statusItem.button?.toolTip = nil
        }
        skipFeedbackWorkItem = restore
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: restore)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clipwell"
        )
        button.image?.isTemplate = true
        button.target = self
        button.action = #selector(handleClick)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func handleClick() {
        let isRightClick = NSApp.currentEvent?.type == .rightMouseUp
            || NSApp.currentEvent?.modifierFlags.contains(.control) == true

        if isRightClick {
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()

        let toggleTitle = monitor.isPaused ? "Resume Capturing" : "Pause Capturing"
        menu.addItem(withTitle: toggleTitle, action: #selector(togglePause), keyEquivalent: "")
            .target = self

        menu.addItem(.separator())

        menu.addItem(withTitle: "Show History  \(HotKeyManager.describeCurrentBinding())",
                     action: #selector(showHistory), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Settings\u{2026}", action: #selector(showSettings), keyEquivalent: ",")
            .target = self

        menu.addItem(.separator())

        menu.addItem(withTitle: "Quit Clipwell", action: #selector(quit), keyEquivalent: "q")
            .target = self

        // Attaching the menu only for this click keeps left-click free to open
        // the panel instead of popping the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePause() {
        let paused = !monitor.isPaused
        monitor.setPaused(paused)
        // Same setting as "Record clipboard history" in Preferences, so keep
        // the two in step rather than letting them disagree.
        Preferences.shared.recordHistory = !paused
        statusItem.button?.appearsDisabled = paused
    }

    @objc private func showHistory() { panel.show() }
    @objc private func showSettings() { settings.show() }
    @objc private func quit() { NSApp.terminate(nil) }
}
