import Foundation
import Vision
import AppKit

/// Extracts text from images so they can be found by search.
///
/// The hard part of an image clipboard history isn't storing images, it's
/// finding one again three days later. Scrolling a wall of thumbnails does not
/// scale, and an image otherwise contributes nothing to the search index. OCR
/// is what makes "that screenshot of the invoice" a search rather than a hunt.
enum TextRecognizer {

    /// OCR accuracy stops improving well before full retina resolution while
    /// cost keeps climbing, so oversized images are downsampled first.
    private static let maxAnalysisPixel: CGFloat = 2000

    /// Recognized text, or nil if the image has none.
    ///
    /// Synchronous and slow (100ms to several seconds). Never call it on the
    /// capture path -- `HistoryStore` runs it on a background queue after the
    /// item is already saved.
    static func recognizeText(in imageData: Data) -> String? {
        let analysisData = downsampleIfNeeded(imageData) ?? imageData

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(data: analysisData, options: [:])
        do {
            try handler.perform([request])
        } catch {
            Log.capture.error("OCR failed: \(String(describing: error), privacy: .public)")
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else { return nil }

        let lines = observations.compactMap { observation -> String? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Low-confidence results are usually texture misread as letters,
            // and polluting the search index with them is worse than missing.
            guard candidate.confidence >= 0.4 else { return nil }
            return candidate.string
        }

        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func downsampleIfNeeded(_ data: Data) -> Data? {
        guard let size = ImageUtil.pixelSize(of: data),
              max(size.width, size.height) > maxAnalysisPixel
        else { return nil }
        return ImageUtil.thumbnail(from: data, maxPixel: maxAnalysisPixel)
    }
}
