import Foundation
import AppKit

struct ClassificationResult {
    var kind: ClipKind
    var previewText: String
    var searchText: String
    var meta: ClipMeta
}

enum ContentClassifier {

    static func classify(_ snapshot: PasteboardSnapshot) -> ClassificationResult {
        let utis = snapshot.allUTIs
        let text = snapshot.plainText
        let hasImage = utis.contains { ImageUtil.isImageUTI($0) } || utis.contains(UTIs.pdf)

        // Files first: a Finder copy carries file URLs plus a text fallback of
        // the filenames, and the files are unambiguously the real payload.
        if !snapshot.fileURLs.isEmpty {
            return classifyFiles(snapshot)
        }

        // The genuinely ambiguous case is "image AND text together", which
        // happens in two opposite situations:
        //
        //   Copy a range from Excel  -> RTF + HTML + text + TIFF. Wanted: text.
        //   Copy an image in Safari  -> TIFF + the image's URL as text. Wanted: image.
        //
        // What separates them is whether the text is real content or just a
        // bare URL / trivial label tagging along with the picture.
        // When an image is present, the text alongside it decides the verdict:
        // substantial text means the image is a bonus rendering, incidental
        // text means the image is the point.
        if hasImage {
            let textIsSubstantial = text.map { !isIncidentalText($0) } ?? false
            if !textIsSubstantial { return classifyImage(snapshot) }
        }

        guard let text, !text.isEmpty else {
            // Something is on the pasteboard but we can't render it. Still worth
            // keeping: the representations round-trip fine even if we can't
            // preview them.
            let label = utis.sorted().first ?? "unknown"
            return ClassificationResult(
                kind: .text,
                previewText: "(\(label))",
                searchText: "",
                meta: ClipMeta()
            )
        }

        if let hex = ColorDetector.detect(in: text) {
            var meta = ClipMeta()
            meta.colorHex = hex
            return ClassificationResult(kind: .color, previewText: text, searchText: text, meta: meta)
        }

        if let url = LinkDetector.detect(in: text) {
            var meta = ClipMeta()
            meta.linkURL = url.absoluteString
            return ClassificationResult(kind: .link, previewText: text, searchText: text, meta: meta)
        }

        if CodeDetector.looksLikeCode(text) {
            var meta = ClipMeta()
            meta.codeLanguage = CodeDetector.guessLanguage(text)
            return ClassificationResult(kind: .code, previewText: text, searchText: text, meta: meta)
        }

        if !utis.isDisjoint(with: Set(UTIs.richTextFamily)) {
            return ClassificationResult(kind: .richText, previewText: text, searchText: text, meta: ClipMeta())
        }

        return ClassificationResult(kind: .text, previewText: text, searchText: text, meta: ClipMeta())
    }

    // MARK: - Per-kind builders

    private static func classifyFiles(_ snapshot: PasteboardSnapshot) -> ClassificationResult {
        let urls = snapshot.fileURLs
        let names = urls.map { $0.lastPathComponent }
        var meta = ClipMeta()
        meta.filePaths = urls.map { $0.path }

        let preview: String
        if names.count == 1 {
            preview = names[0]
        } else {
            preview = "\(names.count) items - " + names.prefix(3).joined(separator: ", ")
        }
        // Search on full paths so "Downloads" finds things by folder too.
        let searchText = (names + urls.map { $0.path }).joined(separator: " ")
        return ClassificationResult(kind: .file, previewText: preview, searchText: searchText, meta: meta)
    }

    private static func classifyImage(_ snapshot: PasteboardSnapshot) -> ClassificationResult {
        var meta = ClipMeta()
        var preview = "Image"
        if let image = snapshot.bestImage() {
            if let size = ImageUtil.pixelSize(of: image.data) {
                meta.pixelWidth = Int(size.width)
                meta.pixelHeight = Int(size.height)
                preview = "Image \(Int(size.width)) x \(Int(size.height))"
            }
        }
        // Searching for the source app name is the realistic way people find an
        // image again ("that thing I copied out of Figma").
        let searchText = [preview, snapshot.sourceAppName ?? ""].joined(separator: " ")
        return ClassificationResult(kind: .image, previewText: preview, searchText: searchText, meta: meta)
    }

    /// True when accompanying text is just a tag-along (a bare URL, a short
    /// filename-ish label) rather than the actual content being copied.
    private static func isIncidentalText(_ text: String) -> Bool {
        if text.count > 220 { return false }
        if text.contains("\n") { return false }
        if LinkDetector.detect(in: text) != nil { return true }
        // A short single-word label next to an image is decoration, not content.
        if text.count <= 40 && !text.contains(" ") { return true }
        return false
    }
}

// MARK: - Detectors

enum ColorDetector {
    private static let hexPattern = try? NSRegularExpression(
        pattern: "^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$"
    )
    private static let functionalPattern = try? NSRegularExpression(
        pattern: "^(rgb|rgba|hsl|hsla)\\(\\s*[0-9.]+%?\\s*,?\\s*[0-9.]+%?\\s*,?\\s*[0-9.]+%?\\s*(,\\s*[0-9.]+%?\\s*)?\\)$",
        options: [.caseInsensitive]
    )

    /// Returns a normalised `#RRGGBB`/`#RRGGBBAA` string, or nil.
    static func detect(in text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 32 else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)

        if let match = hexPattern?.firstMatch(in: trimmed, range: range),
           let digitsRange = Range(match.range(at: 1), in: trimmed) {
            var digits = String(trimmed[digitsRange])
            if digits.count == 3 {
                digits = digits.map { "\($0)\($0)" }.joined()
            }
            return "#" + digits.uppercased()
        }

        if functionalPattern?.firstMatch(in: trimmed, range: range) != nil {
            return normaliseFunctional(trimmed)
        }
        return nil
    }

    private static func normaliseFunctional(_ text: String) -> String? {
        let numbers = text
            .components(separatedBy: CharacterSet(charactersIn: "(),"))
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")) }
        guard numbers.count >= 3 else { return nil }
        if text.lowercased().hasPrefix("rgb") {
            let clamped = numbers.prefix(3).map { Int(max(0, min(255, $0))) }
            return String(format: "#%02X%02X%02X", clamped[0], clamped[1], clamped[2])
        }
        // HSL -> RGB
        let hue = numbers[0].truncatingRemainder(dividingBy: 360) / 360
        let saturation = max(0, min(1, numbers[1] / 100))
        let lightness = max(0, min(1, numbers[2] / 100))
        let (red, green, blue) = hslToRGB(hue: hue, saturation: saturation, lightness: lightness)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private static func hslToRGB(hue: Double, saturation: Double, lightness: Double) -> (Double, Double, Double) {
        if saturation == 0 { return (lightness, lightness, lightness) }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func component(_ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }
        return (component(hue + 1.0 / 3.0), component(hue), component(hue - 1.0 / 3.0))
    }
}

enum LinkDetector {
    /// Only matches when the *entire* trimmed string is one URL -- a paragraph
    /// that happens to contain a link is still text.
    static func detect(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 2048,
              !trimmed.contains(" "),
              !trimmed.contains("\n"),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "ftp", "mailto"].contains(scheme),
              url.host != nil || scheme == "mailto"
        else { return nil }
        return url
    }
}

enum CodeDetector {
    private static let signals: [String] = [
        "function ", "const ", "let ", "var ", "=> {", "def ", "class ", "import ",
        "#include", "public static", "return ", "if (", "for (", "while (",
        "</", "/>", "};", "});", "()", "::", "&&", "||", "!=", "==", "->",
        // Indentation-significant languages, which carry none of the bracket
        // punctuation above.
        "elif ", "self.", "lambda ", "):", "__init__"
    ]

    static func looksLikeCode(_ text: String) -> Bool {
        guard text.count >= 24 else { return false }
        let lines = text.components(separatedBy: .newlines)

        var score = 0
        for signal in signals where text.contains(signal) { score += 1 }

        // Indented continuation lines are a strong structural hint.
        let indented = lines.filter { $0.hasPrefix("  ") || $0.hasPrefix("\t") }.count
        if lines.count >= 3 && indented >= max(1, lines.count / 3) { score += 2 }

        // Block structure.
        //
        // Checking only for braces and semicolons is a C-family assumption, and
        // it reads Python as prose: `def f():` / `for x in y:` has no bracket
        // punctuation anywhere. Each language family opens or closes blocks its
        // own way, so each gets its own marker.
        let trimmedLines = lines.map { $0.trimmingCharacters(in: .whitespaces) }

        // C family: braces and statement terminators.
        let braceTerminated = trimmedLines.filter {
            $0.hasSuffix(";") || $0.hasSuffix("{") || $0.hasSuffix("}")
        }.count
        if braceTerminated >= 2 { score += 2 }

        // Python family: blocks open with a trailing colon. Two or more, so a
        // list with a couple of headings ("Ingredients:") doesn't qualify.
        let colonOpeners = trimmedLines.filter { $0.hasSuffix(":") && $0.count > 1 }.count
        if colonOpeners >= 2 { score += 2 }

        // Ruby and Lua close blocks with a bare `end`, which is distinctive
        // enough on its own line to count by itself.
        let bareEnds = trimmedLines.filter { $0 == "end" }.count
        if bareEnds >= 1 { score += 2 }

        // Prose check: real sentences push back against a code verdict.
        let sentenceEnds = text.components(separatedBy: CharacterSet(charactersIn: ".!?")).count - 1
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
        if words > 25 && sentenceEnds >= 3 && score < 6 { return false }

        return score >= 4
    }

    static func guessLanguage(_ text: String) -> String? {
        let checks: [(String, [String])] = [
            ("swift",      ["func ", "guard let", "-> ", "@State", "var body:", "SwiftUI"]),
            ("python",     ["def ", "self.", "import ", "elif ", "__init__", "None"]),
            ("javascript", ["function ", "const ", "=>", "console.log", "require(", "export "]),
            ("typescript", ["interface ", ": string", ": number", "implements ", "type "]),
            ("rust",       ["fn ", "let mut", "impl ", "pub fn", "->", "::"]),
            ("go",         ["func ", ":=", "package ", "import (", "nil"]),
            ("java",       ["public class", "public static void", "System.out", "@Override"]),
            ("c",          ["#include", "int main", "printf(", "malloc("]),
            ("ruby",       ["def ", "end", "puts ", "require ", "@"]),
            ("shell",      ["#!/bin", "echo ", "$(", "fi", "esac"]),
            ("sql",        ["SELECT ", "FROM ", "WHERE ", "INSERT INTO", "JOIN "]),
            ("html",       ["<div", "<span", "<html", "</", "<!DOCTYPE"]),
            ("css",        ["{", "}", "px;", "color:", "margin:"]),
            ("json",       ["{\"", "\": ", "null", "[{"])
        ]
        var best: (String, Int)?
        for (language, markers) in checks {
            let hits = markers.filter { text.contains($0) }.count
            if hits >= 2, best == nil || hits > best!.1 {
                best = (language, hits)
            }
        }
        return best?.0
    }
}
