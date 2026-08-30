import Foundation

/// The single "primary" kind used for display, filtering and iconography.
///
/// This is deliberately separate from what the item actually *stores*: an item
/// always keeps every pasteboard representation it was captured with, and the
/// kind is only a label for how to present it.
enum ClipKind: String, Codable, CaseIterable {
    case text
    case richText
    case image
    case file
    case color
    case link
    case code

    var displayName: String {
        switch self {
        case .text:     return "Text"
        case .richText: return "Rich Text"
        case .image:    return "Image"
        case .file:     return "Files"
        case .color:    return "Color"
        case .link:     return "Link"
        case .code:     return "Code"
        }
    }

    var symbolName: String {
        switch self {
        case .text:     return "text.alignleft"
        case .richText: return "doc.richtext"
        case .image:    return "photo"
        case .file:     return "folder"
        case .color:    return "paintpalette"
        case .link:     return "link"
        case .code:     return "chevron.left.forwardslash.chevron.right"
        }
    }
}
