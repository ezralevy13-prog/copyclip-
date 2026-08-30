import XCTest
@testable import ClipwellCore

/// Builds pasteboard snapshots by hand so classification can be tested without
/// a real pasteboard.
private func snapshot(_ representations: [String: String],
                      binary: [String: Data] = [:],
                      app: String = "TestApp") -> PasteboardSnapshot {
    var reps: [String: Data] = binary
    for (uti, text) in representations {
        reps[uti] = Data(text.utf8)
    }
    return PasteboardSnapshot(
        items: [PBItemSnapshot(representations: reps)],
        sourceBundleID: "com.test.app",
        sourceAppName: app,
        capturedAt: Date()
    )
}

/// A one-pixel PNG, so image branches can be exercised for real.
private let tinyPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)!

final class ContentClassifierTests: XCTestCase {

    func testPlainTextIsText() {
        let result = ContentClassifier.classify(snapshot([UTIs.plainText: "just some notes"]))
        XCTAssertEqual(result.kind, .text)
        XCTAssertEqual(result.previewText, "just some notes")
    }

    func testRichTextWinsWhenRTFPresent() {
        let result = ContentClassifier.classify(snapshot([
            UTIs.plainText: "some formatted words here",
            UTIs.rtf: "{\\rtf1 some formatted words here}"
        ]))
        XCTAssertEqual(result.kind, .richText)
    }

    /// Copying a screenshot: image bytes, no text at all.
    func testImageOnlyIsImage() {
        let result = ContentClassifier.classify(snapshot([:], binary: [UTIs.png: tinyPNG]))
        XCTAssertEqual(result.kind, .image)
        XCTAssertEqual(result.meta.pixelWidth, 1)
        XCTAssertEqual(result.meta.pixelHeight, 1)
    }

    /// Copying an image in a browser: the image plus its URL as text. The image
    /// is what the user wants, so incidental text must not win.
    func testImageWithIncidentalURLTextIsImage() {
        let result = ContentClassifier.classify(snapshot(
            [UTIs.plainText: "https://example.com/cat.png"],
            binary: [UTIs.png: tinyPNG]
        ))
        XCTAssertEqual(result.kind, .image)
    }

    /// Copying a range from a spreadsheet: RTF + HTML + text + a rendered
    /// image. Here the text is the real payload and must beat the image.
    func testImageWithSubstantialTextIsNotImage() {
        let result = ContentClassifier.classify(snapshot(
            [
                UTIs.plainText: "Region\tRevenue\nNorth\t1200\nSouth\t900\nEast\t1500",
                UTIs.rtf: "{\\rtf1 table}",
                UTIs.html: "<table><tr><td>North</td></tr></table>"
            ],
            binary: [UTIs.tiff: tinyPNG]
        ))
        XCTAssertNotEqual(result.kind, .image, "substantial text should outrank the tag-along image")
        XCTAssertEqual(result.kind, .richText)
    }

    func testFilesWinOverEverything() {
        let result = ContentClassifier.classify(snapshot(
            [
                UTIs.fileURL: "file:///Users/test/Documents/report.pdf",
                UTIs.plainText: "report.pdf"
            ],
            binary: [UTIs.png: tinyPNG]
        ))
        XCTAssertEqual(result.kind, .file)
        XCTAssertEqual(result.meta.filePaths, ["/Users/test/Documents/report.pdf"])
        XCTAssertEqual(result.previewText, "report.pdf")
    }

    func testColorIsDetected() {
        let result = ContentClassifier.classify(snapshot([UTIs.plainText: "#3366FF"]))
        XCTAssertEqual(result.kind, .color)
        XCTAssertEqual(result.meta.colorHex, "#3366FF")
    }

    func testLinkIsDetected() {
        let result = ContentClassifier.classify(snapshot([UTIs.plainText: "https://example.com/page"]))
        XCTAssertEqual(result.kind, .link)
        XCTAssertEqual(result.meta.linkURL, "https://example.com/page")
    }

    func testCodeIsDetected() {
        let code = """
        function total(items) {
            const sum = items.reduce((a, b) => a + b, 0);
            return sum;
        }
        """
        let result = ContentClassifier.classify(snapshot([UTIs.plainText: code]))
        XCTAssertEqual(result.kind, .code)
        XCTAssertEqual(result.meta.codeLanguage, "javascript")
    }

    func testUnrenderableContentStillClassifies() {
        // An unknown private type: we can't preview it, but it must not crash
        // and the item still round-trips through storage.
        let result = ContentClassifier.classify(
            snapshot([:], binary: ["com.example.private": Data([0x01, 0x02, 0x03])])
        )
        XCTAssertEqual(result.kind, .text)
        XCTAssertTrue(result.previewText.contains("com.example.private"))
    }
}

final class HashingTests: XCTestCase {

    func testHashIsStableAcrossRepresentationOrder() {
        // Dictionaries don't preserve order, so the hash must not depend on it.
        let a = snapshot([UTIs.plainText: "hello", UTIs.rtf: "{\\rtf1 hello}"])
        let b = snapshot([UTIs.rtf: "{\\rtf1 hello}", UTIs.plainText: "hello"])
        XCTAssertEqual(Hashing.snapshotHash(a), Hashing.snapshotHash(b))
    }

    func testHashChangesWithContent() {
        let a = snapshot([UTIs.plainText: "hello"])
        let b = snapshot([UTIs.plainText: "hello!"])
        XCTAssertNotEqual(Hashing.snapshotHash(a), Hashing.snapshotHash(b))
    }

    func testHashIgnoresSourceApp() {
        // The same bytes copied from two apps are the same clipboard content.
        let a = snapshot([UTIs.plainText: "hello"], app: "Safari")
        let b = snapshot([UTIs.plainText: "hello"], app: "Notes")
        XCTAssertEqual(Hashing.snapshotHash(a), Hashing.snapshotHash(b))
    }
}
