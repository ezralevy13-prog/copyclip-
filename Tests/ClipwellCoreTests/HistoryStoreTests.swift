import XCTest
@testable import ClipwellCore

final class HistoryStoreTests: XCTestCase {

    private var root: URL!
    private var store: HistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("clipwell-tests-\(UUID().uuidString)", isDirectory: true)
        store = try HistoryStore(root: root)
    }

    override func tearDownWithError() throws {
        store = nil
        if let root { try? FileManager.default.removeItem(at: root) }
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func textSnapshot(_ text: String) -> PasteboardSnapshot {
        PasteboardSnapshot(
            items: [PBItemSnapshot(representations: [UTIs.plainText: Data(text.utf8)])],
            sourceBundleID: "com.test.app",
            sourceAppName: "TestApp",
            capturedAt: Date()
        )
    }

    /// Larger than BlobStore.inlineThreshold, so it goes to a blob file.
    private func largeSnapshot(_ marker: UInt8) -> PasteboardSnapshot {
        let payload = Data(repeating: marker, count: BlobStore.inlineThreshold + 4096)
        return PasteboardSnapshot(
            items: [PBItemSnapshot(representations: ["com.test.blob": payload])],
            sourceBundleID: "com.test.app",
            sourceAppName: "TestApp",
            capturedAt: Date()
        )
    }

    // MARK: - Basics

    func testInsertAndRetrieve() {
        XCTAssertNotNil(store.insert(textSnapshot("hello world")))
        let items = store.items()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].previewText, "hello world")
        XCTAssertEqual(store.plainText(for: items[0].id), "hello world")
    }

    func testDuplicateCopyPromotesInsteadOfDuplicating() {
        let first = store.insert(textSnapshot("repeated"))
        let second = store.insert(textSnapshot("repeated"))
        XCTAssertEqual(first, second, "same content should reuse the same row")
        XCTAssertEqual(store.items().count, 1)
    }

    func testSearchFindsByContent() {
        store.insert(textSnapshot("alpha beta"))
        store.insert(textSnapshot("gamma delta"))
        XCTAssertEqual(store.items(matching: "beta").count, 1)
        XCTAssertEqual(store.items(matching: "gamma").count, 1)
        XCTAssertEqual(store.items(matching: "zzz").count, 0)
    }

    func testSearchIsPrefixMatching() {
        store.insert(textSnapshot("refactoring"))
        XCTAssertEqual(store.items(matching: "refac").count, 1)
    }

    func testKindFilter() {
        store.insert(textSnapshot("plain words here"))
        store.insert(textSnapshot("https://example.com"))
        XCTAssertEqual(store.items(kind: .link).count, 1)
        XCTAssertEqual(store.items(kind: .text).count, 1)
    }

    func testDeleteRemovesItem() {
        let id = store.insert(textSnapshot("temporary"))!
        store.delete(itemID: id)
        XCTAssertEqual(store.items().count, 0)
    }

    func testPinning() {
        let id = store.insert(textSnapshot("keep me"))!
        store.setPinned(true, itemID: id)
        XCTAssertTrue(store.items()[0].pinned)
        store.setPinned(false, itemID: id)
        XCTAssertFalse(store.items()[0].pinned)
    }

    func testClearAllRespectsPins() {
        let pinned = store.insert(textSnapshot("pinned item"))!
        store.insert(textSnapshot("unpinned item"))
        store.setPinned(true, itemID: pinned)

        store.clearAll(includingPinned: false)
        XCTAssertEqual(store.items().count, 1)

        store.clearAll(includingPinned: true)
        XCTAssertEqual(store.items().count, 0)
    }

    // MARK: - Targeted loading

    func testPlainTextDoesNotRequireLoadingEverything() {
        // Item carries both text and a large binary blob; reading the text must
        // return the right value regardless of the blob's presence.
        let snapshot = PasteboardSnapshot(
            items: [PBItemSnapshot(representations: [
                UTIs.plainText: Data("the text".utf8),
                "com.test.blob": Data(repeating: 7, count: BlobStore.inlineThreshold + 1024)
            ])],
            sourceBundleID: "com.test.app",
            sourceAppName: "TestApp",
            capturedAt: Date()
        )
        let id = store.insert(snapshot)!
        XCTAssertEqual(store.plainText(for: id), "the text")
    }

    func testRepresentationDataRespectsPreferenceOrder() {
        let snapshot = PasteboardSnapshot(
            items: [PBItemSnapshot(representations: [
                UTIs.plainText: Data("plain".utf8),
                UTIs.rtf: Data("rtf".utf8)
            ])],
            sourceBundleID: nil, sourceAppName: nil, capturedAt: Date()
        )
        let id = store.insert(snapshot)!
        // First UTI listed wins.
        XCTAssertEqual(store.representationData(for: id, preferring: [UTIs.rtf, UTIs.plainText]),
                       Data("rtf".utf8))
        XCTAssertEqual(store.representationData(for: id, preferring: [UTIs.plainText, UTIs.rtf]),
                       Data("plain".utf8))
        XCTAssertNil(store.representationData(for: id, preferring: ["com.absent.type"]))
    }

    func testFullRoundTripPreservesEveryRepresentation() {
        // The core promise: what goes onto the pasteboard comes back intact.
        let representations: [String: Data] = [
            UTIs.plainText: Data("hello".utf8),
            UTIs.rtf: Data("{\\rtf1 hello}".utf8),
            UTIs.html: Data("<b>hello</b>".utf8)
        ]
        let id = store.insert(PasteboardSnapshot(
            items: [PBItemSnapshot(representations: representations)],
            sourceBundleID: nil, sourceAppName: nil, capturedAt: Date()
        ))!

        let restored = store.representations(for: id)
        XCTAssertEqual(restored.count, 1)
        XCTAssertEqual(restored[0], representations)
    }

    func testMultiItemPasteboardSurvivesRoundTrip() {
        // A Finder copy of three files is three pasteboard items, not one.
        let items = (1...3).map { index in
            PBItemSnapshot(representations: [
                UTIs.fileURL: Data("file:///tmp/file\(index).txt".utf8)
            ])
        }
        let id = store.insert(PasteboardSnapshot(
            items: items, sourceBundleID: nil, sourceAppName: nil, capturedAt: Date()
        ))!

        let restored = store.representations(for: id)
        XCTAssertEqual(restored.count, 3, "pasteboard item structure must be preserved")
    }

    // MARK: - Eviction and blob accounting

    /// 10 is the floor the setter clamps to, so it's the smallest cap that can
    /// actually be exercised.
    private static let minimumCap = 10

    func testEvictionHonoursItemCap() {
        Preferences.shared.maxItems = Self.minimumCap
        defer { Preferences.shared.maxItems = 500 }

        for index in 0..<25 {
            store.insert(textSnapshot("item number \(index)"))
        }
        XCTAssertLessThanOrEqual(store.items().count, Self.minimumCap)
        XCTAssertGreaterThan(store.items().count, 0)
    }

    func testEvictionKeepsMostRecent() {
        Preferences.shared.maxItems = Self.minimumCap
        defer { Preferences.shared.maxItems = 500 }

        for index in 0..<25 {
            store.insert(textSnapshot("item number \(index)"))
        }
        // Eviction is least-recently-used, so the newest copy must survive.
        XCTAssertTrue(store.items().contains { $0.previewText == "item number 24" })
    }

    func testMaxItemsClampsToFloor() {
        Preferences.shared.maxItems = 1
        defer { Preferences.shared.maxItems = 500 }
        XCTAssertEqual(Preferences.shared.maxItems, Self.minimumCap,
                       "an absurdly small cap is clamped rather than accepted")
    }

    func testEvictionNeverRemovesPinnedItems() {
        Preferences.shared.maxItems = Self.minimumCap
        defer { Preferences.shared.maxItems = 500 }

        let pinned = store.insert(textSnapshot("important pinned thing"))!
        store.setPinned(true, itemID: pinned)

        for index in 0..<30 {
            store.insert(textSnapshot("filler \(index)"))
        }
        XCTAssertTrue(store.items().contains { $0.id == pinned },
                      "pinned items must survive eviction")
    }

    func testSharedBlobSurvivesUntilLastReferenceGoes() {
        // Two items referencing identical bytes share one blob file. Deleting
        // one must not break the other -- this is the invariant that makes
        // content-addressed storage safe to evict against.
        let payload = Data(repeating: 42, count: BlobStore.inlineThreshold + 2048)
        let makeSnapshot = { (marker: String) in
            PasteboardSnapshot(
                items: [PBItemSnapshot(representations: [
                    "com.test.blob": payload,
                    UTIs.plainText: Data(marker.utf8)
                ])],
                sourceBundleID: nil, sourceAppName: nil, capturedAt: Date()
            )
        }

        let first = store.insert(makeSnapshot("first"))!
        let second = store.insert(makeSnapshot("second"))!
        XCTAssertNotEqual(first, second)

        store.delete(itemID: first)

        let survivor = store.representationData(for: second, preferring: ["com.test.blob"])
        XCTAssertEqual(survivor, payload, "shared blob must survive while still referenced")
    }

    func testDiskUsageDropsWhenItemsAreDeleted() {
        let before = store.stats().diskBytes
        let id = store.insert(largeSnapshot(9))!
        let during = store.stats().diskBytes
        XCTAssertGreaterThan(during, before)

        store.delete(itemID: id)
        XCTAssertEqual(store.stats().diskBytes, before, "blob accounting must return to baseline")
    }

    func testStatsReflectContents() {
        store.insert(textSnapshot("one"))
        let id = store.insert(textSnapshot("two"))!
        store.setPinned(true, itemID: id)

        let stats = store.stats()
        XCTAssertEqual(stats.itemCount, 2)
        XCTAssertEqual(stats.pinnedCount, 1)
    }

    // MARK: - Reopening

    func testDataSurvivesReopen() throws {
        store.insert(textSnapshot("persisted across launches"))
        store = nil

        // Reopening runs the startup reconciliation pass, which must not
        // destroy anything it finds.
        let reopened = try HistoryStore(root: root)
        XCTAssertEqual(reopened.items().count, 1)
        XCTAssertEqual(reopened.items()[0].previewText, "persisted across launches")
    }

    func testReopenPreservesBlobs() throws {
        let id = store.insert(largeSnapshot(3))!
        let expected = store.representationData(for: id, preferring: ["com.test.blob"])
        XCTAssertNotNil(expected)
        store = nil

        let reopened = try HistoryStore(root: root)
        XCTAssertEqual(reopened.representationData(for: id, preferring: ["com.test.blob"]), expected,
                       "reconciliation must not delete referenced blobs")
    }
}

final class FTSQueryTests: XCTestCase {

    func testBuildsPrefixQuery() {
        XCTAssertEqual(HistoryStore.ftsQuery(from: "hello"), "\"hello\"*")
    }

    func testJoinsTokensWithAnd() {
        XCTAssertEqual(HistoryStore.ftsQuery(from: "hello world"), "\"hello\"* AND \"world\"*")
    }

    func testStripsOperatorSyntax() {
        // FTS operators in user input must not reach the query as operators.
        let query = HistoryStore.ftsQuery(from: "foo OR* bar\"")
        XCTAssertNotNil(query)
        XCTAssertFalse(query!.contains("OR*"))
    }

    func testReturnsNilForEmptyInput() {
        XCTAssertNil(HistoryStore.ftsQuery(from: ""))
        XCTAssertNil(HistoryStore.ftsQuery(from: "   "))
        XCTAssertNil(HistoryStore.ftsQuery(from: "!!!"))
    }
}

final class ClipMetaTests: XCTestCase {

    func testRoundTrip() {
        var meta = ClipMeta()
        meta.pixelWidth = 800
        meta.pixelHeight = 600
        meta.colorHex = "#FF0000"
        meta.filePaths = ["/tmp/a", "/tmp/b"]
        meta.recognizedText = "text from an image"

        let decoded = ClipMeta.decode(meta.encoded())
        XCTAssertEqual(decoded.pixelWidth, 800)
        XCTAssertEqual(decoded.pixelHeight, 600)
        XCTAssertEqual(decoded.colorHex, "#FF0000")
        XCTAssertEqual(decoded.filePaths, ["/tmp/a", "/tmp/b"])
        XCTAssertEqual(decoded.recognizedText, "text from an image")
    }

    func testDecodeToleratesGarbage() {
        XCTAssertNil(ClipMeta.decode(nil).colorHex)
        XCTAssertNil(ClipMeta.decode("not json").colorHex)
    }

    func testDimensionsLabel() {
        var meta = ClipMeta()
        XCTAssertNil(meta.imageDimensionsLabel)
        meta.pixelWidth = 1920
        meta.pixelHeight = 1080
        XCTAssertEqual(meta.imageDimensionsLabel, "1920 x 1080")
    }
}
