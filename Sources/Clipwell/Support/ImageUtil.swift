import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ImageUtil {

    /// Pixel dimensions without decoding the full image.
    static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double
        else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Downsampled JPEG thumbnail. Uses ImageIO's thumbnail path so a 20 MB
    /// screenshot is never fully decoded just to draw a 64pt row.
    static func thumbnail(from data: Data, maxPixel: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72])
    }

    /// Re-encode to PNG. macOS puts screenshots on the pasteboard as
    /// uncompressed TIFF, which routinely runs 10-20x the size of the
    /// equivalent PNG. Transcoding at capture is the single biggest disk win.
    static func transcodeToPNG(_ data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }

    static func isImageUTI(_ uti: String) -> Bool {
        guard let type = UTType(uti) else { return false }
        return type.conforms(to: .image)
    }
}
