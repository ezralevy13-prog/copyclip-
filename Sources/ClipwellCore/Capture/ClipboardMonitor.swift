import Foundation
import AppKit

/// Polls the general pasteboard and hands new contents to the store.
///
/// macOS publishes no "pasteboard changed" notification, so polling
/// `changeCount` is the only option available to any clipboard manager. The
/// read itself is a single integer compare, so a short interval is cheap; the
/// full pasteboard is only read once that integer actually moves.
final class ClipboardMonitor {

    private let store: HistoryStore
    private let pasteboard: NSPasteboard
    /// Which app is frontmost, injected so capture filtering can be tested
    /// without driving the real window server.
    private let frontmostApp: () -> (bundleID: String?, name: String?)
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.ezralevy.clipwell.capture", qos: .utility)

    private var lastChangeCount: Int
    /// changeCounts produced by our own paste-back, so we don't re-record what
    /// we just wrote.
    private var selfWrittenChangeCounts: Set<Int> = []

    private(set) var isPaused = false

    /// - Parameters:
    ///   - pasteboard: defaults to the general pasteboard. Tests pass a private
    ///     one so a test run never disturbs the user's real clipboard.
    ///   - frontmostApp: defaults to asking NSWorkspace.
    init(store: HistoryStore,
         pasteboard: NSPasteboard = .general,
         frontmostApp: @escaping () -> (bundleID: String?, name: String?) = {
             let app = NSWorkspace.shared.frontmostApplication
             return (app?.bundleIdentifier, app?.localizedName)
         }) {
        self.store = store
        self.pasteboard = pasteboard
        self.frontmostApp = frontmostApp
        self.lastChangeCount = pasteboard.changeCount
    }

    func start() {
        stop()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        let interval = Preferences.shared.pollInterval
        timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        Log.capture.info("monitor started at \(interval, privacy: .public)s")
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Call after restarting with a changed poll interval.
    func restart() { start() }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        // Resync on the capture queue so nothing copied while paused gets
        // swept up in one go on resume.
        queue.async {
            self.lastChangeCount = self.pasteboard.changeCount
        }
    }

    /// Registers a changeCount that we caused ourselves.
    func ignoreNextChange() {
        queue.async {
            self.selfWrittenChangeCounts.insert(self.pasteboard.changeCount)
            // Our write lands a moment after this call, so cover the next one too.
            self.selfWrittenChangeCounts.insert(self.pasteboard.changeCount + 1)
        }
    }

    private func tick() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if selfWrittenChangeCounts.contains(changeCount) {
            selfWrittenChangeCounts.remove(changeCount)
            return
        }
        guard !isPaused else { return }

        guard let snapshot = readPasteboard() else { return }
        store.insert(snapshot)
    }

    /// Reads every item and every type. Returns nil when the contents should
    /// not be recorded at all.
    func readPasteboard() -> PasteboardSnapshot? {
        guard let pasteboardItems = pasteboard.pasteboardItems, !pasteboardItems.isEmpty else { return nil }

        let allTypes = Set(pasteboardItems.flatMap { $0.types.map(\.rawValue) })

        // nspasteboard.org privacy conventions. Concealed means a password
        // manager explicitly asked not to be recorded; transient means the
        // content is throwaway. Both are honoured before anything is read.
        if allTypes.contains(UTIs.concealed) || allTypes.contains(UTIs.transient) {
            Log.capture.debug("skipping concealed/transient pasteboard contents")
            return nil
        }

        let frontmost = frontmostApp()
        let bundleID = frontmost.bundleID

        if let bundleID, Preferences.shared.excludedBundleIDs.contains(bundleID) {
            Log.capture.debug("skipping copy from excluded app")
            return nil
        }
        // Never record our own paste-backs.
        if bundleID == Bundle.main.bundleIdentifier { return nil }

        let maxBytes = Preferences.shared.maxItemBytes
        var snapshots: [PBItemSnapshot] = []

        for pasteboardItem in pasteboardItems {
            var representations: [String: Data] = [:]
            for type in pasteboardItem.types {
                let uti = type.rawValue
                // Skip the marker types themselves; they carry no content.
                if uti == UTIs.autoGenerated { continue }
                guard let data = pasteboardItem.data(forType: type), !data.isEmpty else { continue }
                // Oversized single representations (a 500 MB PSD on the
                // pasteboard) get dropped rather than blowing out the store.
                guard data.count <= maxBytes else {
                    Log.capture.debug("dropping oversized representation \(uti, privacy: .public)")
                    continue
                }
                representations[uti] = data
            }
            if !representations.isEmpty {
                snapshots.append(PBItemSnapshot(representations: representations))
            }
        }

        guard !snapshots.isEmpty else { return nil }

        let snapshot = PasteboardSnapshot(
            items: snapshots,
            sourceBundleID: bundleID,
            sourceAppName: frontmost.name,
            capturedAt: Date()
        )

        // Credential heuristics. The concealed-type convention above only works
        // when the source app cooperates, and terminals, editors and browsers
        // -- where people actually copy keys from -- never do.
        if Preferences.shared.skipDetectedSecrets,
           let text = snapshot.plainText,
           let finding = SecretDetector.scan(text) {
            Log.capture.info("skipping likely secret: \(finding.reason, privacy: .public)")
            NotificationCenter.default.post(
                name: ClipboardMonitor.didSkipSecretNotification,
                object: nil,
                userInfo: ["reason": finding.reason]
            )
            return nil
        }

        return snapshot
    }

    /// Posted when a capture is dropped because it looked like a credential, so
    /// the UI can say so rather than leaving the user wondering why their copy
    /// never showed up.
    static let didSkipSecretNotification = Notification.Name("ClipwellDidSkipSecret")
}
