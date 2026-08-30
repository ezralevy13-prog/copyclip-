import SwiftUI
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

struct SettingsView: View {
    let store: HistoryStore
    let monitor: ClipboardMonitor
    var onHotKeyChanged: () -> Void

    @State private var maxItems = Preferences.shared.maxItems
    @State private var maxDisk = Preferences.shared.maxDiskMegabytes
    @State private var maxItemSize = Preferences.shared.maxItemMegabytes
    @State private var pollInterval = Preferences.shared.pollInterval
    @State private var pasteAutomatically = Preferences.shared.pasteAutomatically
    @State private var launchAtLogin = Preferences.shared.launchAtLogin
    @State private var excluded = Preferences.shared.excludedBundleIDs.sorted()
    @State private var stats: HistoryStore.Stats?
    @State private var hasAccessibility = Paster.hasAccessibilityPermission()

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            storageTab.tabItem { Label("Storage", systemImage: "internaldrive") }
            privacyTab.tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 480, height: 380)
        .onAppear { refreshStats() }
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            LabeledContent("Shortcut") {
                HotKeyRecorder(onChange: onHotKeyChanged)
            }

            Toggle("Paste automatically after choosing", isOn: $pasteAutomatically)
                .onChange(of: pasteAutomatically) { newValue in
                    Preferences.shared.pasteAutomatically = newValue
                }

            // Auto-paste is the one feature that needs a system permission, and
            // an unsigned build loses the grant whenever the binary changes, so
            // surface the live state rather than letting it fail silently.
            if pasteAutomatically && !hasAccessibility {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accessibility permission needed").font(.system(size: 11, weight: .medium))
                        Text("Without it, items are copied but you press \u{2318}V yourself.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Grant\u{2026}") {
                        Paster.requestAccessibilityPermission()
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
            }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    Preferences.shared.launchAtLogin = newValue
                    applyLaunchAtLogin(newValue)
                }

            LabeledContent("Check clipboard every") {
                HStack {
                    Slider(value: $pollInterval, in: 0.1...1.0, step: 0.1)
                    Text(String(format: "%.1fs", pollInterval)).monospacedDigit().frame(width: 40)
                }
            }
            .onChange(of: pollInterval) { newValue in
                Preferences.shared.pollInterval = newValue
                monitor.restart()
            }

            Text("macOS has no clipboard-change notification, so Clipwell polls. Faster catches rapid copies; slower uses marginally less power.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .formStyle(.grouped)
        .onAppear { hasAccessibility = Paster.hasAccessibilityPermission() }
    }

    // MARK: - Storage

    private var storageTab: some View {
        Form {
            Section {
                LabeledContent("Keep at most") {
                    HStack {
                        TextField("", value: $maxItems, format: .number)
                            .frame(width: 70)
                            .onSubmit { Preferences.shared.maxItems = maxItems }
                        Text("items").foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Disk limit") {
                    HStack {
                        TextField("", value: $maxDisk, format: .number)
                            .frame(width: 70)
                            .onSubmit { Preferences.shared.maxDiskMegabytes = maxDisk }
                        Text("MB").foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Skip items larger than") {
                    HStack {
                        TextField("", value: $maxItemSize, format: .number)
                            .frame(width: 70)
                            .onSubmit { Preferences.shared.maxItemMegabytes = maxItemSize }
                        Text("MB").foregroundStyle(.secondary)
                    }
                }

                Text("Oldest unpinned items are removed first. Pinned items are never evicted.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Section("Current usage") {
                if let stats {
                    LabeledContent("Items", value: "\(stats.itemCount)  (\(stats.pinnedCount) pinned)")
                    LabeledContent("On disk", value: ByteCountFormatter.string(
                        fromByteCount: stats.diskBytes, countStyle: .file))
                }
                HStack {
                    Button("Refresh") { refreshStats() }
                    Spacer()
                    Button("Clear Unpinned") {
                        store.clearAll(includingPinned: false)
                        refreshStats()
                    }
                    Button("Clear All") {
                        store.clearAll(includingPinned: true)
                        refreshStats()
                    }
                    .foregroundStyle(.red)
                }
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Privacy

    private var privacyTab: some View {
        Form {
            Section("Ignored apps") {
                Text("Anything copied while one of these apps is frontmost is never recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                List {
                    ForEach(excluded, id: \.self) { bundleID in
                        HStack {
                            Text(bundleID).font(.system(size: 11, design: .monospaced))
                            Spacer()
                            Button {
                                removeExclusion(bundleID)
                            } label: {
                                Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(height: 130)

                Button("Add Application\u{2026}") { addExclusion() }
                    .controlSize(.small)
            }

            Section {
                Label(
                    "Clipwell always ignores content marked confidential by password managers, whatever this list says.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Actions

    private func refreshStats() {
        Task.detached(priority: .utility) {
            let snapshot = store.stats()
            await MainActor.run { self.stats = snapshot }
        }
    }

    private func removeExclusion(_ bundleID: String) {
        var current = Preferences.shared.excludedBundleIDs
        current.remove(bundleID)
        Preferences.shared.excludedBundleIDs = current
        excluded = current.sorted()
    }

    private func addExclusion() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }

        var current = Preferences.shared.excludedBundleIDs
        for url in panel.urls {
            if let bundleID = Bundle(url: url)?.bundleIdentifier {
                current.insert(bundleID)
            }
        }
        Preferences.shared.excludedBundleIDs = current
        excluded = current.sorted()
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Unsigned builds can be refused here; report it rather than
            // leaving the toggle silently lying about its state.
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
