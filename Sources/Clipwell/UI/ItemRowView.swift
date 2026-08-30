import SwiftUI
import AppKit

struct ItemRowView: View {
    let item: ClipItem
    let index: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            leadingGlyph
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(displayTitle)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .foregroundStyle(isSelected ? Color.white : Color.primary)

                Text(item.subtitle)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.75) : Color.secondary)
            }

            Spacer(minLength: 4)

            if item.pinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color.secondary)
            }

            // Quick-pick affordance for the first nine rows.
            if index < 9 {
                Text("\u{2318}\(index + 1)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.6) : Color.tertiaryLabel)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }

    /// Collapses whitespace so a multi-line copy still reads as one tidy line.
    private var displayTitle: String {
        let collapsed = item.previewText
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? item.kind.displayName : String(collapsed.prefix(200))
    }

    @ViewBuilder
    private var leadingGlyph: some View {
        switch item.kind {
        case .image:
            // Renders from the cached thumbnail, never the full image -- this is
            // what keeps scrolling smooth with a history full of screenshots.
            if let path = item.thumbnailPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                glyphBadge
            }
        case .color:
            RoundedRectangle(cornerRadius: 5)
                .fill(Color(nsColor: NSColor.fromHex(item.meta.colorHex) ?? .gray))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary, lineWidth: 1))
        case .file:
            if let first = item.meta.filePaths?.first {
                Image(nsImage: NSWorkspace.shared.icon(forFile: first))
                    .resizable()
                    .frame(width: 28, height: 28)
            } else {
                glyphBadge
            }
        default:
            glyphBadge
        }
    }

    private var glyphBadge: some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(isSelected ? Color.white.opacity(0.2) : Color(nsColor: .quaternaryLabelColor).opacity(0.5))
            .overlay(
                Image(systemName: item.kind.symbolName)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.secondary)
            )
    }
}

extension Color {
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)
}

extension NSColor {
    /// Parses `#RRGGBB` / `#RRGGBBAA` as produced by `ColorDetector`.
    static func fromHex(_ hex: String?) -> NSColor? {
        guard var hex else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else { return nil }

        if hex.count == 6 {
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        }
        return NSColor(
            srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
            green: CGFloat((value >> 16) & 0xFF) / 255,
            blue: CGFloat((value >> 8) & 0xFF) / 255,
            alpha: CGFloat(value & 0xFF) / 255
        )
    }
}
