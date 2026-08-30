import Foundation
import AppKit
import SwiftUI

/// An NSPanel that can take keyboard focus without activating the app.
///
/// This is the crux of the whole paste flow: `.nonactivatingPanel` means the
/// app the user was typing in stays frontmost, so when we synthesize Cmd-V it
/// lands there rather than in us.
final class ClipwellPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController {

    private var panel: ClipwellPanel?
    private var keyMonitor: Any?
    private let store: HistoryStore
    private let monitor: ClipboardMonitor
    let viewModel: HistoryViewModel

    var isVisible: Bool { panel?.isVisible ?? false }

    init(store: HistoryStore, monitor: ClipboardMonitor) {
        self.store = store
        self.monitor = monitor
        self.viewModel = HistoryViewModel(store: store)

        viewModel.onDismiss = { [weak self] in self?.hide() }
        viewModel.onPaste = { [weak self] item, plainTextOnly in
            self?.paste(item, plainTextOnly: plainTextOnly)
        }
    }

    // MARK: - Show / hide

    func toggle() {
        if isVisible { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel

        viewModel.prepareForShow()
        positionOnActiveScreen(panel)

        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    private func makePanel() -> ClipwellPanel {
        let panel = ClipwellPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 460),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let root = HistoryView(viewModel: viewModel)
        let hosting = NSHostingView(rootView: root)
        panel.contentView = hosting
        return panel
    }

    /// Opens on whichever screen has the mouse, centred slightly above middle.
    private func positionOnActiveScreen(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2 + frame.height * 0.08
        )
        panel.setFrameOrigin(origin)
    }

    // MARK: - Keyboard

    /// Arrow keys, Return, Escape and the Cmd-1..9 quick picks are handled with
    /// a local monitor rather than SwiftUI focus plumbing, which keeps the
    /// search field permanently focused for typing while navigation still works.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Cmd-1 through Cmd-9 paste the Nth visible item outright.
        if flags.contains(.command),
           let characters = event.charactersIgnoringModifiers,
           let digit = Int(characters), (1...9).contains(digit) {
            viewModel.selectIndex(digit - 1)
            viewModel.activateSelected()
            return true
        }

        switch Int(event.keyCode) {
        case 53: // Escape
            hide()
            return true
        case 125: // Down
            viewModel.moveSelection(by: 1)
            return true
        case 126: // Up
            viewModel.moveSelection(by: -1)
            return true
        case 121: // Page Down
            viewModel.moveSelection(by: 8)
            return true
        case 116: // Page Up
            viewModel.moveSelection(by: -8)
            return true
        case 36, 76: // Return, Keypad Enter
            // Option-Return strips formatting.
            viewModel.activateSelected(plainTextOnly: flags.contains(.option))
            return true
        case 51: // Delete
            // Only when the search field is empty, so backspace still edits text.
            if viewModel.searchQuery.isEmpty {
                viewModel.deleteSelected()
                return true
            }
            return false
        case 48: // Tab -- toggle list/grid
            viewModel.isGridMode.toggle()
            return true
        default:
            break
        }

        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "p" {
            viewModel.togglePinSelected()
            return true
        }
        return false
    }

    // MARK: - Paste

    private func paste(_ item: ClipItem, plainTextOnly: Bool) {
        hide()
        store.markUsed(itemID: item.id)

        // Tell the capture side to disregard the change we're about to make,
        // otherwise every paste re-inserts itself at the top of the history.
        monitor.ignoreNextChange()
        Paster.writeToPasteboard(itemID: item.id, store: store, plainTextOnly: plainTextOnly)

        guard Preferences.shared.pasteAutomatically else { return }

        // A beat for the panel to close and focus to settle before the
        // keystroke goes out, or it can land in the wrong place.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            Paster.sendPasteKeystroke()
        }
    }
}
