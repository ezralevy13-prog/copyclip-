import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: HistoryStore
    let monitor: ClipboardMonitor
    var onHotKeyChanged: () -> Void

    @State private var tab: SettingsTab = .general

    var body: some View {
        VStack(spacing: 0) {
            SettingsToolbar(selection: $tab)
            Divider()
            ScrollView {
                Group {
                    switch tab {
                    case .general:         GeneralPane(onHotKeyChanged: onHotKeyChanged, monitor: monitor)
                    case .ignoredApps:     IgnoredAppsPane()
                    case .clipsManagement: ClipsManagementPane(store: store, monitor: monitor)
                    case .about:           AboutPane(store: store)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 540, height: 460)
    }
}

// MARK: - General

private struct GeneralPane: View {
    var onHotKeyChanged: () -> Void
    let monitor: ClipboardMonitor

    @State private var maxItems = Preferences.shared.maxItems
    @State private var displayCount = Preferences.shared.displayCount
    @State private var launchAtLogin = Preferences.shared.launchAtLogin
    @State private var recordHistory = Preferences.shared.recordHistory
    @State private var pasteAutomatically = Preferences.shared.pasteAutomatically
    @State private var hasAccessibility = Paster.hasAccessibilityPermission()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Clippings") {
                SettingsNumberRow(label: "Remember:", unit: "clippings",
                                  value: maxItems, range: 10...100_000) { newValue in
                    Preferences.shared.maxItems = newValue
                    maxItems = Preferences.shared.maxItems
                    // Showing more than we keep makes no sense.
                    if displayCount > maxItems {
                        Preferences.shared.displayCount = maxItems
                        displayCount = Preferences.shared.displayCount
                    }
                }
                SettingsNumberRow(label: "Display:", unit: "clippings",
                                  value: displayCount, range: 5...100_000) { newValue in
                    Preferences.shared.displayCount = newValue
                    displayCount = Preferences.shared.displayCount
                }
                SettingsFootnote("Remember is how many clippings are kept. Display is how many the panel lists before you search or scroll.")
            }

            SettingsSection("Options") {
                Toggle("Start Clipwell at system startup", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { applyLaunchAtLogin($0) }

                Toggle("Record clipboard history", isOn: $recordHistory)
                    .onChange(of: recordHistory) { newValue in
                        Preferences.shared.recordHistory = newValue
                        monitor.setPaused(!newValue)
                    }

                Toggle("Paste automatically after choosing", isOn: $pasteAutomatically)
                    .onChange(of: pasteAutomatically) { newValue in
                        Preferences.shared.pasteAutomatically = newValue
                        hasAccessibility = Paster.hasAccessibilityPermission()
                    }

                if pasteAutomatically && !hasAccessibility {
                    AccessibilityWarning { hasAccessibility = Paster.hasAccessibilityPermission() }
                }
            }

            SettingsSection("Shortcut") {
                HStack(spacing: 10) {
                    Text("Show history:")
                    HotKeyRecorder(onChange: onHotKeyChanged)
                    Spacer(minLength: 0)
                }
                SettingsFootnote("Click and press the keys you want. Needs at least one of Command, Control or Option.")
            }
        }
        .onAppear { hasAccessibility = Paster.hasAccessibilityPermission() }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            Preferences.shared.launchAtLogin = enabled
        } catch {
            // Unsigned builds can be refused here. Report it rather than
            // leaving the toggle lying about its state.
            Log.ui.error("launch at login failed: \(String(describing: error), privacy: .public)")
            launchAtLogin = !enabled
            Preferences.shared.launchAtLogin = !enabled

            let alert = NSAlert()
            alert.messageText = "Couldn't change launch at login"
            alert.informativeText = "macOS refused the request. This usually means the app isn't signed with a stable identity. See scripts/make-signing-cert.sh."
            alert.runModal()
        }
    }
}

private struct AccessibilityWarning: View {
    var onRequested: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility permission needed")
                    .font(.system(size: 11, weight: .medium))
                Text("Without it, items are copied but you press \u{2318}V yourself.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button("Grant\u{2026}") {
                Paster.requestAccessibilityPermission()
                onRequested()
            }
            .controlSize(.small)
        }
        .padding(9)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Ignored Apps

private struct IgnoredAppsPane: View {
    @State private var excluded = Preferences.shared.excludedBundleIDs.sorted()
    @State private var selection: String?
    @State private var skipSecrets = Preferences.shared.skipDetectedSecrets

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Ignored Applications") {
                SettingsFootnote("Anything copied while one of these apps is frontmost is never recorded.")

                List(selection: $selection) {
                    ForEach(excluded, id: \.self) { bundleID in
                        HStack(spacing: 8) {
                            Image(nsImage: icon(for: bundleID))
                                .resizable()
                                .frame(width: 16, height: 16)
                            Text(displayName(for: bundleID))
                            Spacer(minLength: 0)
                            Text(bundleID)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .tag(bundleID)
                    }
                }
                .frame(height: 170)
                .border(Color(nsColor: .separatorColor), width: 1)

                HStack(spacing: 8) {
                    Button {
                        addApplications()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        if let selection { remove(selection) }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selection == nil)
                    Spacer(minLength: 0)
                }
                .controlSize(.small)
            }

            SettingsSection("Credentials") {
                Toggle("Don't record things that look like secrets", isOn: $skipSecrets)
                    .onChange(of: skipSecrets) { Preferences.shared.skipDetectedSecrets = $0 }
                SettingsFootnote("Detects API keys, access tokens, private key blocks and card numbers, and skips the copy entirely. The menu bar icon flashes when this happens, so a skipped copy is never silent.")
            }

            SettingsSection {
                Label("Content marked confidential by a password manager is always ignored, whatever these settings say.",
                      systemImage: "lock.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func icon(for bundleID: String) -> NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .application)
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            // Not installed on this machine -- keep the rule, show the raw id.
            return bundleID.components(separatedBy: ".").last ?? bundleID
        }
        return url.deletingPathExtension().lastPathComponent
    }

    private func remove(_ bundleID: String) {
        var current = Preferences.shared.excludedBundleIDs
        current.remove(bundleID)
        Preferences.shared.excludedBundleIDs = current
        excluded = current.sorted()
        selection = nil
    }

    private func addApplications() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }

        var current = Preferences.shared.excludedBundleIDs
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier { current.insert(bundleID) }
        }
        Preferences.shared.excludedBundleIDs = current
        excluded = current.sorted()
    }
}

// MARK: - Clips Management

private struct ClipsManagementPane: View {
    let store: HistoryStore
    let monitor: ClipboardMonitor

    @State private var maxDisk = Preferences.shared.maxDiskMegabytes
    @State private var maxItemSize = Preferences.shared.maxItemMegabytes
    @State private var pollInterval = Preferences.shared.pollInterval
    @State private var recognizeText = Preferences.shared.recognizeTextInImages
    @State private var stats: HistoryStore.Stats?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SettingsSection("Storage Limits") {
                SettingsNumberRow(label: "Disk limit:", unit: "MB",
                                  value: maxDisk, range: 64...512_000) { newValue in
                    Preferences.shared.maxDiskMegabytes = newValue
                    maxDisk = Preferences.shared.maxDiskMegabytes
                }
                SettingsNumberRow(label: "Skip above:", unit: "MB per clipping",
                                  value: maxItemSize, range: 1...4096) { newValue in
                    Preferences.shared.maxItemMegabytes = newValue
                    maxItemSize = Preferences.shared.maxItemMegabytes
                }
                SettingsFootnote("Oldest unpinned clippings are removed first. Pinned clippings are never removed.")
            }

            SettingsSection("Images") {
                Toggle("Find text inside images", isOn: $recognizeText)
                    .onChange(of: recognizeText) { Preferences.shared.recognizeTextInImages = $0 }
                SettingsFootnote("Reads text out of screenshots shortly after they're copied so you can search for them by their contents. Uses some CPU per image.")
            }

            SettingsSection("Capture") {
                HStack(spacing: 8) {
                    Text("Check every:")
                        .frame(width: 92, alignment: .trailing)
                    Slider(value: $pollInterval, in: 0.1...1.0, step: 0.1)
                        .frame(width: 170)
                    Text(String(format: "%.1fs", pollInterval))
                        .monospacedDigit()
                }
                .onChange(of: pollInterval) { newValue in
                    Preferences.shared.pollInterval = newValue
                    monitor.restart()
                }
                SettingsFootnote("macOS has no clipboard-change notification, so Clipwell checks on a timer. Faster catches rapid copies; slower uses marginally less power.")
            }

            SettingsSection("Current Usage") {
                if let stats {
                    HStack(spacing: 24) {
                        UsageStat(label: "Clippings", value: "\(stats.itemCount)")
                        UsageStat(label: "Pinned", value: "\(stats.pinnedCount)")
                        UsageStat(label: "On disk",
                                  value: ByteCountFormatter.string(fromByteCount: stats.diskBytes, countStyle: .file))
                    }
                } else {
                    ProgressView().controlSize(.small)
                }

                HStack(spacing: 8) {
                    Button("Refresh") { refreshStats() }
                    Spacer(minLength: 0)
                    Button("Remove Unpinned") {
                        store.clearAll(includingPinned: false)
                        refreshStats()
                    }
                    Button("Remove All") {
                        confirmRemoveAll()
                    }
                }
                .controlSize(.small)
            }
        }
        .onAppear { refreshStats() }
    }

    private func refreshStats() {
        Task.detached(priority: .utility) {
            let snapshot = store.stats()
            await MainActor.run { self.stats = snapshot }
        }
    }

    private func confirmRemoveAll() {
        // Destroys pinned clippings too, so it asks first.
        let alert = NSAlert()
        alert.messageText = "Remove all clippings?"
        alert.informativeText = "This deletes your entire clipboard history, including pinned clippings. It cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.clearAll(includingPinned: true)
        refreshStats()
    }
}

private struct UsageStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 15, weight: .medium))
            Text(label).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

// MARK: - About

private struct AboutPane: View {
    let store: HistoryStore

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "dev"
        return short
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Clipwell").font(.system(size: 20, weight: .semibold))
                    Text("Version \(version)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }

            SettingsSection {
                Text("A clipboard manager that keeps everything you copy \u{2014} images, rich text, files, colours, links and code, not just plain text.")
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
                SettingsFootnote("Every representation of a copy is stored, so pasting later keeps the formatting the original had. Nothing leaves your machine; there is no network code in this app.")
            }

            SettingsSection("Storage Location") {
                HStack(spacing: 8) {
                    Text(store.storageRoot.path)
                        .font(.system(size: 10, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.storageRoot])
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}
