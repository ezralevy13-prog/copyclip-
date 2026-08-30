import SwiftUI
import AppKit

/// Right-hand detail view. Renders each kind the way it actually wants to be
/// seen: an image as an image, a color as a swatch, code with highlighting.
struct PreviewPane: View {
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        Group {
            if let item = viewModel.selectedItem {
                VStack(alignment: .leading, spacing: 0) {
                    PreviewHeader(item: item)
                    Divider()
                    content(for: item)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                // Rebuild when the selection changes so previews don't linger.
                .id(item.id)
            } else {
                Color.clear
            }
        }
    }

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        switch item.kind {
        case .image:    ImagePreview(item: item, viewModel: viewModel)
        case .color:    ColorPreview(item: item)
        case .file:     FilePreview(item: item)
        case .link:     LinkPreview(item: item, viewModel: viewModel)
        case .code:     CodePreview(item: item, viewModel: viewModel)
        case .richText: RichTextPreview(item: item, viewModel: viewModel)
        case .text:     PlainTextPreview(item: item, viewModel: viewModel)
        }
    }
}

private struct PreviewHeader: View {
    let item: ClipItem

    var body: some View {
        HStack(spacing: 8) {
            Label(item.kind.displayName, systemImage: item.kind.symbolName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let language = item.meta.codeLanguage {
                Text(language)
                    .font(.system(size: 10, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color(nsColor: .quaternaryLabelColor), in: Capsule())
            }

            Spacer()

            Text(item.subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

// MARK: - Per-kind previews

private struct ImagePreview: View {
    let item: ClipItem
    @ObservedObject var viewModel: HistoryViewModel
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(14)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Text found by OCR. Shown as well as indexed, so it's obvious why
            // a screenshot matched a search and the text can be selected out.
            if let recognized = item.meta.recognizedText, !recognized.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Label("Text in image", systemImage: "text.viewfinder")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    ScrollView {
                        Text(recognized)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Full-size bytes are loaded only when a preview is actually shown, and
        // off the main thread so selecting a 40 MP screenshot doesn't hitch.
        .task(id: item.id) {
            let loaded = await Task.detached(priority: .userInitiated) {
                viewModel.fullImage(for: item)
            }.value
            await MainActor.run { self.image = loaded }
        }
    }
}

private struct ColorPreview: View {
    let item: ClipItem

    var body: some View {
        let nsColor = NSColor.fromHex(item.meta.colorHex) ?? .gray
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: nsColor))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, lineWidth: 1))
                .frame(height: 130)

            VStack(spacing: 6) {
                Text(item.meta.colorHex ?? item.previewText)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                Text(rgbDescription(nsColor))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                if item.previewText != item.meta.colorHex {
                    Text("copied as \(item.previewText)")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(18)
    }

    private func rgbDescription(_ color: NSColor) -> String {
        guard let srgb = color.usingColorSpace(.sRGB) else { return "" }
        return String(
            format: "rgb(%d, %d, %d)",
            Int(srgb.redComponent * 255),
            Int(srgb.greenComponent * 255),
            Int(srgb.blueComponent * 255)
        )
    }
}

private struct FilePreview: View {
    let item: ClipItem

    var body: some View {
        let paths = item.meta.filePaths ?? []
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    let exists = FileManager.default.fileExists(atPath: path)
                    HStack(spacing: 9) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                            .resizable()
                            .frame(width: 26, height: 26)
                            .opacity(exists ? 1 : 0.4)

                        VStack(alignment: .leading, spacing: 1) {
                            Text((path as NSString).lastPathComponent)
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Text((path as NSString).deletingLastPathComponent)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }

                        Spacer()

                        // File captures store paths, not bytes, so an item can
                        // outlive the file it points at. Say so rather than
                        // failing silently at paste time.
                        if !exists {
                            Text("missing")
                                .font(.system(size: 9, weight: .medium))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(14)
        }
    }
}

private struct LinkPreview: View {
    let item: ClipItem
    @ObservedObject var viewModel: HistoryViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let urlString = item.meta.linkURL, let url = URL(string: urlString) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(url.host ?? urlString)
                        .font(.system(size: 15, weight: .medium))
                    Text(urlString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open in Browser", systemImage: "arrow.up.right.square")
                }
                .controlSize(.small)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
    }
}

private struct CodePreview: View {
    let item: ClipItem
    @ObservedObject var viewModel: HistoryViewModel
    @State private var text: String = ""

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(CodeHighlighter.highlight(text, language: item.meta.codeLanguage))
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.id) {
            let loaded = await Task.detached(priority: .userInitiated) {
                viewModel.plainText(for: item) ?? item.previewText
            }.value
            await MainActor.run { self.text = loaded }
        }
    }
}

private struct RichTextPreview: View {
    let item: ClipItem
    @ObservedObject var viewModel: HistoryViewModel
    @State private var attributed: AttributedString?
    @State private var fallback: String = ""

    var body: some View {
        ScrollView {
            Group {
                if let attributed {
                    Text(attributed)
                } else {
                    Text(fallback)
                }
            }
            .textSelection(.enabled)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.id) {
            let rendered = await Task.detached(priority: .userInitiated) {
                () -> (AttributedString?, String) in
                let attributedString = viewModel.attributedText(for: item)
                let plain = viewModel.plainText(for: item) ?? item.previewText
                // Round-trip through AttributedString so SwiftUI can draw the
                // real formatting rather than a stripped-down version.
                if let attributedString {
                    return (try? AttributedString(attributedString, including: \.appKit), plain)
                }
                return (nil, plain)
            }.value
            await MainActor.run {
                self.attributed = rendered.0
                self.fallback = rendered.1
            }
        }
    }
}

private struct PlainTextPreview: View {
    let item: ClipItem
    @ObservedObject var viewModel: HistoryViewModel
    @State private var text: String = ""

    var body: some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: item.id) {
            let loaded = await Task.detached(priority: .userInitiated) {
                viewModel.plainText(for: item) ?? item.previewText
            }.value
            await MainActor.run { self.text = loaded }
        }
    }
}
