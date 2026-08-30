import XCTest
import AppKit
@testable import ClipwellCore

/// Copy -> store -> paste, through a private pasteboard.
///
/// This is the app's central claim: what you copied is what gets pasted, with
/// every representation intact. Until now it was only checkable by hand.
final class PasteTests: XCTestCase {

    private var root: URL!
    private var store: HistoryStore!
    private var pasteboard: NSPasteboard!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipwell-paste-\(UUID().uuidString)", isDirectory: true)
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

    private func insert(_ representations: [String: Data]) -> Int64 {
        store.insert(PasteboardSnapshot(
            items: [PBItemSnapshot(representations: representations)],
            sourceBundleID: "com.test.app", sourceAppName: "TestApp", capturedAt: Date()
        ))!
    }

    func testRestoresEveryRepresentation() {
        // A copy out of a word processor: three views of the same content.
        let representations: [String: Data] = [
            UTIs.plainText: Data("hello world".utf8),
            UTIs.rtf: Data("{\\rtf1\\ansi hello world}".utf8),
            UTIs.html: Data("<b>hello world</b>".utf8)
        ]
        let id = insert(representations)

        Paster.writeToPasteboard(itemID: id, store: store, plainTextOnly: false, pasteboard: pasteboard)

        for (uti, expected) in representations {
            let actual = pasteboard.data(forType: NSPasteboard.PasteboardType(uti))
            XCTAssertEqual(actual, expected, "representation \(uti) did not survive the round trip")
        }
    }

    func testPlainTextOnlyStripsFormatting() {
        let id = insert([
            UTIs.plainText: Data("hello world".utf8),
            UTIs.rtf: Data("{\\rtf1\\ansi hello world}".utf8)
        ])

        Paster.writeToPasteboard(itemID: id, store: store, plainTextOnly: true, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "hello world")
        XCTAssertNil(pasteboard.data(forType: NSPasteboard.PasteboardType(UTIs.rtf)),
                     "paste-as-plain-text must not carry the formatting through")
    }

    func testMultipleItemsAreRestoredSeparately() {
        // A Finder copy of three files is three pasteboard items, and pasting
        // it must produce three again -- not one item with the last file's URL.
        let paths = (1...3).map { "file:///tmp/clipwell-test-\($0).txt" }
        let id = store.insert(PasteboardSnapshot(
            items: paths.map { PBItemSnapshot(representations: [UTIs.fileURL: Data($0.utf8)]) },
            sourceBundleID: nil, sourceAppName: nil, capturedAt: Date()
        ))!

        Paster.writeToPasteboard(itemID: id, store: store, plainTextOnly: false, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.pasteboardItems?.count, 3)
        let restored = pasteboard.pasteboardItems?.compactMap {
            $0.string(forType: NSPasteboard.PasteboardType(UTIs.fileURL))
        }
        XCTAssertEqual(restored?.sorted(), paths.sorted())
    }

    func testPlainTextOnlyFallsBackWhenThereIsNoText() {
        // An image has no text representation; asking for plain text should
        // still paste something rather than silently clearing the clipboard.
        let png = Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        )!
        let id = insert([UTIs.png: png])

        Paster.writeToPasteboard(itemID: id, store: store, plainTextOnly: true, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.data(forType: NSPasteboard.PasteboardType(UTIs.png)), png)
    }

    func testPastingAnUnknownItemLeavesThePasteboardAlone() {
        pasteboard.clearContents()
        pasteboard.setString("existing clipboard contents", forType: .string)

        Paster.writeToPasteboard(itemID: 999_999, store: store, plainTextOnly: false, pasteboard: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "existing clipboard contents",
                       "a missing item must not wipe the clipboard")
    }
}
