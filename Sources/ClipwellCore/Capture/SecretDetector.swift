import Foundation

/// Heuristics for content that should not be written to a permanent,
/// searchable history.
///
/// The `org.nspasteboard.ConcealedType` convention only helps when the source
/// app cooperates, and the places people most often copy credentials from --
/// a terminal, an editor, a cloud console in a browser -- never set it. Without
/// something like this, one `export AWS_SECRET_ACCESS_KEY=...` lives in the
/// history until eviction gets around to it.
///
/// Tuned to favour precision: every pattern here targets a format with a
/// distinctive, credential-specific shape, because a false positive silently
/// drops something the user wanted.
enum SecretDetector {

    enum Finding: Equatable {
        case privateKey
        case providerToken(String)
        case creditCard
        case credentialAssignment

        var reason: String {
            switch self {
            case .privateKey:              return "private key block"
            case .providerToken(let name): return "\(name) token"
            case .creditCard:              return "payment card number"
            case .credentialAssignment:    return "credential assignment"
            }
        }
    }

    /// Distinctive credential prefixes. Each is specific enough that a match is
    /// almost never accidental.
    private static let tokenPatterns: [(name: String, pattern: String)] = [
        ("AWS access key",  "\\bAKIA[0-9A-Z]{16}\\b"),
        ("GitHub",          "\\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\\b"),
        ("GitHub PAT",      "\\bgithub_pat_[A-Za-z0-9_]{50,}\\b"),
        ("Slack",           "\\bxox[baprs]-[A-Za-z0-9-]{10,}\\b"),
        ("Stripe",          "\\b(sk|rk)_live_[A-Za-z0-9]{20,}\\b"),
        ("Google API key",  "\\bAIza[0-9A-Za-z_-]{35}\\b"),
        ("OpenAI",          "\\bsk-(proj-)?[A-Za-z0-9_-]{32,}\\b"),
        ("Anthropic",       "\\bsk-ant-[A-Za-z0-9_-]{32,}\\b"),
        ("JSON Web Token",  "\\beyJ[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\.[A-Za-z0-9_-]{10,}\\b")
    ]

    private static let privateKeyPattern =
        "-----BEGIN (RSA |DSA |EC |OPENSSH |PGP )?PRIVATE KEY( BLOCK)?-----"

    /// `password = "…"` style assignments. Requires a quoted or clearly
    /// delimited value of real length so prose like "my password is wrong"
    /// doesn't trip it.
    private static let assignmentPattern =
        "(?i)\\b(password|passwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)\\b"
        + "\\s*[:=]\\s*[\"']?[^\\s\"']{8,}"

    private static let cardPattern = "\\b(?:\\d[ -]*?){13,19}\\b"

    /// Returns why the text looks like a secret, or nil if it doesn't.
    static func scan(_ text: String) -> Finding? {
        // A whole document pasted around is not a credential even if it mentions
        // one; this targets the short strings people copy to move a secret.
        guard text.count <= 4096 else { return nil }
        let range = NSRange(text.startIndex..., in: text)

        if matches(privateKeyPattern, text, range) { return .privateKey }

        for (name, pattern) in tokenPatterns where matches(pattern, text, range) {
            return .providerToken(name)
        }

        if matches(assignmentPattern, text, range) { return .credentialAssignment }

        if let card = firstMatch(cardPattern, text, range) {
            let digits = card.filter(\.isNumber)
            // Luhn plus a length check keeps this off order numbers and IDs.
            if (13...19).contains(digits.count), passesLuhn(digits) { return .creditCard }
        }

        return nil
    }

    // MARK: - Helpers

    private static func matches(_ pattern: String, _ text: String, _ range: NSRange) -> Bool {
        firstMatch(pattern, text, range) != nil
    }

    private static func firstMatch(_ pattern: String, _ text: String, _ range: NSRange) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range, in: text)
        else { return nil }
        return String(text[matchRange])
    }

    /// Standard Luhn checksum, as used by every major card network.
    static func passesLuhn(_ digits: String) -> Bool {
        guard !digits.isEmpty, digits.allSatisfy(\.isNumber) else { return false }
        var sum = 0
        // Double every second digit counting from the right.
        for (offset, character) in digits.reversed().enumerated() {
            guard let value = character.wholeNumberValue else { return false }
            if offset % 2 == 1 {
                let doubled = value * 2
                sum += doubled > 9 ? doubled - 9 : doubled
            } else {
                sum += value
            }
        }
        return sum % 10 == 0
    }
}
