import Foundation
import Carbon.HIToolbox

/// UserDefaults-backed settings, with the defaults that matter for an app that
/// runs all day.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let maxItems          = "maxItems"
        static let maxDiskMegabytes  = "maxDiskMegabytes"
        static let maxItemMegabytes  = "maxItemMegabytes"
        static let pollInterval      = "pollIntervalSeconds"
        static let excludedBundleIDs = "excludedBundleIDs"
        static let hotKeyCode        = "hotKeyCode"
        static let hotKeyModifiers   = "hotKeyModifiers"
        static let launchAtLogin     = "launchAtLogin"
        static let pasteAutomatically = "pasteAutomatically"
        static let recognizeText     = "recognizeTextInImages"
        static let skipSecrets       = "skipDetectedSecrets"
        static let displayCount      = "displayCount"
        static let recordHistory     = "recordHistory"
    }

    private init() {
        defaults.register(defaults: [
            Key.maxItems: 500,
            Key.maxDiskMegabytes: 2048,
            Key.maxItemMegabytes: 64,
            Key.pollInterval: 0.3,
            Key.hotKeyCode: Int(kVK_ANSI_V),
            Key.hotKeyModifiers: Int(cmdKey | shiftKey),
            Key.launchAtLogin: false,
            Key.pasteAutomatically: true,
            Key.recognizeText: true,
            Key.skipSecrets: true,
            Key.displayCount: 20,
            Key.recordHistory: true,
            // Password managers, pre-excluded. Most also set the concealed type,
            // but belt and braces on the one category where a leak actually hurts.
            Key.excludedBundleIDs: [
                "com.agilebits.onepassword7",
                "com.1password.1password",
                "com.bitwarden.desktop",
                "com.apple.keychainaccess"
            ]
        ])
    }

    /// How many clippings are kept in the history.
    var maxItems: Int {
        get { defaults.integer(forKey: Key.maxItems) }
        set { defaults.set(max(10, newValue), forKey: Key.maxItems) }
    }

    /// How many clippings the panel lists before you search or scroll.
    /// Separate from `maxItems`: you can remember a thousand and still want a
    /// short list in front of you.
    var displayCount: Int {
        get { min(max(5, defaults.integer(forKey: Key.displayCount)), maxItems) }
        set { defaults.set(max(5, newValue), forKey: Key.displayCount) }
    }

    /// Master switch for capture. Persisted, unlike the menu bar's pause, so
    /// turning it off survives a relaunch.
    var recordHistory: Bool {
        get { defaults.bool(forKey: Key.recordHistory) }
        set { defaults.set(newValue, forKey: Key.recordHistory) }
    }

    var maxDiskMegabytes: Int {
        get { defaults.integer(forKey: Key.maxDiskMegabytes) }
        set { defaults.set(max(64, newValue), forKey: Key.maxDiskMegabytes) }
    }

    /// Largest single representation we'll store, in bytes.
    var maxItemBytes: Int {
        max(1, defaults.integer(forKey: Key.maxItemMegabytes)) * 1024 * 1024
    }

    var maxItemMegabytes: Int {
        get { defaults.integer(forKey: Key.maxItemMegabytes) }
        set { defaults.set(max(1, newValue), forKey: Key.maxItemMegabytes) }
    }

    var pollInterval: TimeInterval {
        get { max(0.1, defaults.double(forKey: Key.pollInterval)) }
        set { defaults.set(max(0.1, min(2.0, newValue)), forKey: Key.pollInterval) }
    }

    var excludedBundleIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.excludedBundleIDs) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: Key.excludedBundleIDs) }
    }

    var hotKeyCode: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.hotKeyCode)) }
        set { defaults.set(Int(newValue), forKey: Key.hotKeyCode) }
    }

    var hotKeyModifiers: UInt32 {
        get { UInt32(defaults.integer(forKey: Key.hotKeyModifiers)) }
        set { defaults.set(Int(newValue), forKey: Key.hotKeyModifiers) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Key.launchAtLogin) }
        set { defaults.set(newValue, forKey: Key.launchAtLogin) }
    }

    /// When false, selecting an item only puts it on the clipboard and the user
    /// presses Cmd-V themselves.
    var pasteAutomatically: Bool {
        get { defaults.bool(forKey: Key.pasteAutomatically) }
        set { defaults.set(newValue, forKey: Key.pasteAutomatically) }
    }

    /// Run OCR over captured images so they can be found by their text.
    /// Costs some CPU shortly after each image copy.
    var recognizeTextInImages: Bool {
        get { defaults.bool(forKey: Key.recognizeText) }
        set { defaults.set(newValue, forKey: Key.recognizeText) }
    }

    /// Skip copies that look like credentials -- API keys, tokens, private
    /// keys, card numbers. On by default: a clipboard manager quietly keeping a
    /// searchable copy of your AWS keys is a worse failure than dropping a copy.
    var skipDetectedSecrets: Bool {
        get { defaults.bool(forKey: Key.skipSecrets) }
        set { defaults.set(newValue, forKey: Key.skipSecrets) }
    }
}
