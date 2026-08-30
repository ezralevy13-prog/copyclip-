import XCTest
import AppKit
@testable import ClipwellCore

/// Exercises what the monitor decides to record, driving a private pasteboard
/// so a test run never touches the user's real clipboard.
final class CaptureTests: XCTestCase {

    private var root: URL!
    private var store: HistoryStore!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipwell-capture-\(UUID().uuidString)", isDirectory: true)
        store = try HistoryStore(root: root)
        pasteboard = NSPasteboard(name: NSPasteboard.Name("com.ezralevy.clipwell.tests.\(UUID().uuidString)"))
    }

    override func tearDownWithError() throws {
        pasteboard?.releaseGlobally()
        pasteboard = nil
        store = nil
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    private func makeMonitor(bundleID: String? = "com.test.source",
                             appName: String? = "TestApp") -> ClipboardMonitor {
        ClipboardMonitor(store: store, pasteboard: pasteboard, frontmostApp: { (bundleID, appName) })
    }

    private func write(_ representations: [String: Data]) {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        for (uti, data) in representations {
            item.setData(data, forType: NSPasteboard.PasteboardType(uti))
        }
        pasteboard.writeObjects([item])
    }

    // MARK: - Normal capture

    func testCapturesPlainText() {
        write([UTIs.plainText: Data("hello clipboard".utf8)])
        let snapshot = makeMonitor().readPasteboard()
        XCTAssertNotNil(snapshot)
        XCTAssertEqual(snapshot?.plainText, "hello clipboard")
        XCTAssertEqual(snapshot?.sourceBundleID, "com.test.source")
        XCTAssertEqual(snapshot?.sourceAppName, "TestApp")
    }

    func testCapturesEveryRepresentation() {
        // The core promise: nothing on the pasteboard is dropped.
        write([
            UTIs.plainText: Data("hello".utf8),
            UTIs.rtf: Data("{\\rtf1 hello}".utf8),
            UTIs.html: Data("<b>hello</b>".utf8)
        ])
        let snapshot = makeMonitor().readPasteboard()
        XCTAssertEqual(snapshot?.allUTIs.isSuperset(of: [UTIs.plainText, UTIs.rtf, UTIs.html]), true)
    }

    func testEmptyPasteboardIsNotCaptured() {
        pasteboard.clearContents()
        XCTAssertNil(makeMonitor().readPasteboard())
    }

    // MARK: - Privacy filters

    /// The nspasteboard.org convention password managers use. Honouring it is
    /// the single most important thing this app does with someone's data.
    func testConcealedContentIsNeverCaptured() {
        write([
            UTIs.plainText: Data("hunter2".utf8),
            UTIs.concealed: Data()
        ])
        XCTAssertNil(makeMonitor().readPasteboard(),
                     "content marked concealed must never be recorded")
    }

    func testTransientContentIsNotCaptured() {
        write([
            UTIs.plainText: Data("throwaway".utf8),
            UTIs.transient: Data()
        ])
        XCTAssertNil(makeMonitor().readPasteboard())
    }

    func testExcludedAppIsNotCaptured() {
        let excluded = "com.test.excluded"
        let original = Preferences.shared.excludedBundleIDs
        Preferences.shared.excludedBundleIDs = original.union([excluded])
        defer { Preferences.shared.excludedBundleIDs = original }

        write([UTIs.plainText: Data("from an excluded app".utf8)])
        XCTAssertNil(makeMonitor(bundleID: excluded).readPasteboard())
        // ...but the identical copy from any other app is fine.
        XCTAssertNotNil(makeMonitor(bundleID: "com.test.allowed").readPasteboard())
    }

    func testSecretsAreSkippedWhenEnabled() {
        let original = Preferences.shared.skipDetectedSecrets
        Preferences.shared.skipDetectedSecrets = true
        defer { Preferences.shared.skipDetectedSecrets = original }

        write([UTIs.plainText: Data("AKIAIOSFODNN7EXAMPLE".utf8)])
        XCTAssertNil(makeMonitor().readPasteboard())
    }

    func testSecretSkippingCanBeTurnedOff() {
        let original = Preferences.shared.skipDetectedSecrets
        Preferences.shared.skipDetectedSecrets = false
        defer { Preferences.shared.skipDetectedSecrets = original }

        write([UTIs.plainText: Data("AKIAIOSFODNN7EXAMPLE".utf8)])
        XCTAssertNotNil(makeMonitor().readPasteboard(),
                        "the heuristic must be defeatable by preference")
    }

    func testSkippingASecretPostsANotification() {
        let original = Preferences.shared.skipDetectedSecrets
        Preferences.shared.skipDetectedSecrets = true
        defer { Preferences.shared.skipDetectedSecrets = original }

        // A silently dropped copy would look like a broken app, so the skip is
        // announced for the menu bar to show.
        let expectation = expectation(
            forNotification: ClipboardMonitor.didSkipSecretNotification,
            object: nil
        ) { notification in
            (notification.userInfo?["reason"] as? String)?.isEmpty == false
        }

        write([UTIs.plainText: Data("AKIAIOSFODNN7EXAMPLE".utf8)])
        _ = makeMonitor().readPasteboard()
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Size guard

    func testOversizedRepresentationsAreDropped() {
        let huge = Data(repeating: 0, count: Preferences.shared.maxItemBytes + 1024)
        write([UTIs.plainText: Data("small text".utf8), "com.test.huge": huge])

        let snapshot = makeMonitor().readPasteboard()
        XCTAssertNotNil(snapshot, "the small representation should still be kept")
        XCTAssertFalse(snapshot?.allUTIs.contains("com.test.huge") ?? true,
                       "an oversized representation must not reach the store")
    }
}
