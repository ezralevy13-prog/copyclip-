import Foundation

/// A row from `items`. Deliberately does not carry representation bytes --
/// the list renders from `previewText` and `thumbnailPath` only, so scrolling a
/// history full of screenshots never touches the full-size image data.
struct ClipItem: Identifiable, Equatable {
    var id: Int64
    var contentHash: String
    var kind: ClipKind
    var previewText: String
    var sourceBundleID: String?
    var sourceAppName: String?
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int
    var pinned: Bool
    var byteSize: Int
    var thumbnailPath: String?
    var meta: ClipMeta

    static func == (lhs: ClipItem, rhs: ClipItem) -> Bool {
        lhs.id == rhs.id
            && lhs.pinned == rhs.pinned
            && lhs.lastUsedAt == rhs.lastUsedAt
    }

    var sizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteSize), countStyle: .file)
    }

    var subtitle: String {
        var parts: [String] = []
        if let name = sourceAppName, !name.isEmpty { parts.append(name) }
        if let dimensions = meta.imageDimensionsLabel { parts.append(dimensions) }
        if kind == .image || byteSize > 64 * 1024 { parts.append(sizeLabel) }
        parts.append(Self.relativeFormatter.localizedString(for: createdAt, relativeTo: Date()))
        return parts.joined(separator: "  ·  ")
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
}
