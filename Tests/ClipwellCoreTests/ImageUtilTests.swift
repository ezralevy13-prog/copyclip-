import XCTest
import AppKit
@testable import ClipwellCore

final class ImageUtilTests: XCTestCase {

    /// A real image with known dimensions, drawn rather than hardcoded so the
    /// size assertions mean something.
    private func makeImage(width: Int, height: Int) -> Data {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.systemTeal.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])!
    }

    func testReadsPixelSize() {
        let size = ImageUtil.pixelSize(of: makeImage(width: 320, height: 200))
        XCTAssertEqual(size?.width, 320)
        XCTAssertEqual(size?.height, 200)
    }

    func testPixelSizeRejectsNonImages() {
        XCTAssertNil(ImageUtil.pixelSize(of: Data("not an image".utf8)))
    }

    func testThumbnailIsBoundedByMaxPixel() {
        let thumbnail = ImageUtil.thumbnail(from: makeImage(width: 2000, height: 1000), maxPixel: 400)
        XCTAssertNotNil(thumbnail)
        let size = ImageUtil.pixelSize(of: thumbnail!)
        XCTAssertEqual(max(size!.width, size!.height), 400, accuracy: 1)
    }

    func testThumbnailPreservesAspectRatio() {
        let thumbnail = ImageUtil.thumbnail(from: makeImage(width: 800, height: 400), maxPixel: 200)!
        let size = ImageUtil.pixelSize(of: thumbnail)!
        XCTAssertEqual(size.width / size.height, 2.0, accuracy: 0.05)
    }

    /// The capture path relies on this: macOS hands over screenshots as
    /// uncompressed TIFF, and storing those unchanged is what would make an
    /// image history run to gigabytes.
    func testTIFFTranscodesToASmallerPNG() throws {
        let source = makeImage(width: 600, height: 400)
        let tiff = NSBitmapImageRep(data: source)!.tiffRepresentation!

        let png = try XCTUnwrap(ImageUtil.transcodeToPNG(tiff))
        XCTAssertLessThan(png.count, tiff.count, "transcoding must actually save space")

        // And the image must survive intact.
        let size = ImageUtil.pixelSize(of: png)
        XCTAssertEqual(size?.width, 600)
        XCTAssertEqual(size?.height, 400)
    }

    func testTranscodeRejectsGarbage() {
        XCTAssertNil(ImageUtil.transcodeToPNG(Data("still not an image".utf8)))
    }

    func testRecognisesImageUTIs() {
        XCTAssertTrue(ImageUtil.isImageUTI(UTIs.png))
        XCTAssertTrue(ImageUtil.isImageUTI(UTIs.tiff))
        XCTAssertTrue(ImageUtil.isImageUTI(UTIs.jpeg))
        XCTAssertFalse(ImageUtil.isImageUTI(UTIs.plainText))
        XCTAssertFalse(ImageUtil.isImageUTI("com.example.nonsense"))
    }
}
