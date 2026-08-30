import Foundation

/// Kind-specific extras, stored as a JSON blob on the item row.
///
/// Kept in one optional-heavy struct rather than separate tables because it is
/// only ever read as a whole alongside its item, and it lets new kinds add
/// fields without a migration.
struct ClipMeta: Codable {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var colorHex: String?
    var linkURL: String?
    var filePaths: [String]?
    var codeLanguage: String?
    /// Text found inside an image by OCR. Folded into the search
    /// index so screenshots are findable by their contents.
    var recognizedText: String?

    init() {}

    var imageDimensionsLabel: String? {
        guard let width = pixelWidth, let height = pixelHeight else { return nil }
        return "\(width) x \(height)"
    }

    func encoded() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ json: String?) -> ClipMeta {
        guard let json, let data = json.data(using: .utf8),
              let meta = try? JSONDecoder().decode(ClipMeta.self, from: data)
        else { return ClipMeta() }
        return meta
    }
}
