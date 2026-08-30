import Foundation
import SwiftUI
import AppKit

/// Small regex-based syntax highlighter.
///
/// Deliberately not a parser: it colours strings, comments, numbers and
/// keywords, which is all a preview pane needs. Anything more would be a
/// dependency or a lot of code for a pane you glance at.
enum CodeHighlighter {

    /// Guards against pathological input -- highlighting a 2 MB minified bundle
    /// would stall the UI for no benefit.
    private static let maxHighlightLength = 40_000

    private static let keywordsByLanguage: [String: Set<String>] = [
        "swift": ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum",
                  "protocol", "extension", "import", "for", "in", "while", "switch", "case", "default",
                  "private", "public", "internal", "static", "self", "nil", "true", "false", "try",
                  "throws", "async", "await", "some", "any", "where", "init", "deinit", "lazy", "weak"],
        "python": ["def", "class", "if", "elif", "else", "return", "import", "from", "for", "in",
                   "while", "try", "except", "finally", "with", "as", "lambda", "None", "True",
                   "False", "and", "or", "not", "pass", "raise", "yield", "async", "await", "self"],
        "javascript": ["function", "const", "let", "var", "if", "else", "return", "class", "import",
                       "export", "from", "for", "while", "switch", "case", "default", "new", "this",
                       "null", "undefined", "true", "false", "async", "await", "try", "catch", "typeof"],
        "typescript": ["function", "const", "let", "var", "if", "else", "return", "class", "interface",
                       "type", "import", "export", "from", "for", "while", "new", "this", "null",
                       "undefined", "true", "false", "async", "await", "public", "private", "readonly"],
        "rust": ["fn", "let", "mut", "if", "else", "match", "return", "struct", "enum", "impl",
                 "trait", "use", "pub", "for", "in", "while", "loop", "self", "Some", "None",
                 "Ok", "Err", "true", "false", "async", "await", "move", "ref", "where"],
        "go": ["func", "var", "const", "if", "else", "return", "type", "struct", "interface",
               "package", "import", "for", "range", "switch", "case", "default", "go", "defer",
               "chan", "map", "nil", "true", "false", "err"],
        "java": ["public", "private", "protected", "class", "interface", "extends", "implements",
                 "static", "final", "void", "int", "String", "boolean", "if", "else", "return",
                 "for", "while", "new", "this", "null", "true", "false", "import", "package"],
        "c": ["int", "char", "float", "double", "void", "struct", "typedef", "enum", "union",
              "if", "else", "return", "for", "while", "switch", "case", "break", "continue",
              "static", "const", "sizeof", "NULL", "include", "define"],
        "ruby": ["def", "end", "class", "module", "if", "elsif", "else", "unless", "return",
                 "require", "do", "each", "nil", "true", "false", "self", "attr_accessor", "yield"],
        "shell": ["if", "then", "else", "fi", "for", "do", "done", "while", "case", "esac",
                  "function", "return", "export", "local", "echo", "cd", "source"],
        "sql": ["SELECT", "FROM", "WHERE", "INSERT", "UPDATE", "DELETE", "JOIN", "LEFT", "RIGHT",
                "INNER", "OUTER", "ON", "GROUP", "BY", "ORDER", "HAVING", "LIMIT", "AS", "AND",
                "OR", "NOT", "NULL", "CREATE", "TABLE", "INDEX", "INTO", "VALUES", "SET"]
    ]

    private static let defaultKeywords: Set<String> = [
        "if", "else", "return", "for", "while", "function", "class", "import",
        "const", "let", "var", "def", "true", "false", "null", "nil"
    ]

    // Order matters at application time: comments and strings win over keywords.
    private static let stringPattern = try? NSRegularExpression(
        pattern: "(\"[^\"\\n]*\"|'[^'\\n]*'|`[^`]*`)"
    )
    private static let commentPattern = try? NSRegularExpression(
        pattern: "(//[^\\n]*|#[^\\n]*|/\\*[\\s\\S]*?\\*/|--[^\\n]*)"
    )
    private static let numberPattern = try? NSRegularExpression(
        pattern: "\\b(0x[0-9a-fA-F]+|\\d+\\.?\\d*)\\b"
    )
    private static let identifierPattern = try? NSRegularExpression(
        pattern: "\\b[A-Za-z_][A-Za-z0-9_]*\\b"
    )

    static func highlight(_ code: String, language: String?) -> AttributedString {
        guard code.count <= maxHighlightLength else { return AttributedString(code) }

        var attributed = AttributedString(code)
        attributed.foregroundColor = Color(nsColor: .labelColor)

        let nsRange = NSRange(code.startIndex..., in: code)
        let keywords = language.flatMap { keywordsByLanguage[$0] } ?? defaultKeywords

        // Keywords first, so strings and comments painted afterwards override
        // any keyword-looking word that happens to sit inside them.
        if let identifierPattern {
            for match in identifierPattern.matches(in: code, range: nsRange) {
                guard let range = Range(match.range, in: code) else { continue }
                let word = String(code[range])
                guard keywords.contains(word) else { continue }
                apply(color: .systemPink, to: match.range, in: code, of: &attributed)
            }
        }

        if let numberPattern {
            for match in numberPattern.matches(in: code, range: nsRange) {
                apply(color: .systemOrange, to: match.range, in: code, of: &attributed)
            }
        }

        if let stringPattern {
            for match in stringPattern.matches(in: code, range: nsRange) {
                apply(color: .systemRed, to: match.range, in: code, of: &attributed)
            }
        }

        if let commentPattern {
            for match in commentPattern.matches(in: code, range: nsRange) {
                apply(color: .systemGreen, to: match.range, in: code, of: &attributed)
            }
        }

        return attributed
    }

    private static func apply(
        color: NSColor,
        to nsRange: NSRange,
        in source: String,
        of attributed: inout AttributedString
    ) {
        guard let stringRange = Range(nsRange, in: source),
              let lower = AttributedString.Index(stringRange.lowerBound, within: attributed),
              let upper = AttributedString.Index(stringRange.upperBound, within: attributed)
        else { return }
        attributed[lower..<upper].foregroundColor = Color(nsColor: color)
    }
}
