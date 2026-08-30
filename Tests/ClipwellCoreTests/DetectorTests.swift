import XCTest
@testable import ClipwellCore

final class ColorDetectorTests: XCTestCase {

    func testDetectsSixDigitHex() {
        XCTAssertEqual(ColorDetector.detect(in: "#FF8800"), "#FF8800")
        XCTAssertEqual(ColorDetector.detect(in: "#ff8800"), "#FF8800")
        XCTAssertEqual(ColorDetector.detect(in: "  #ff8800  "), "#FF8800")
    }

    func testExpandsThreeDigitHex() {
        XCTAssertEqual(ColorDetector.detect(in: "#f80"), "#FF8800")
        XCTAssertEqual(ColorDetector.detect(in: "#fff"), "#FFFFFF")
    }

    func testDetectsHexWithoutHash() {
        XCTAssertEqual(ColorDetector.detect(in: "FF8800"), "#FF8800")
    }

    func testNormalisesRGBFunction() {
        XCTAssertEqual(ColorDetector.detect(in: "rgb(255, 136, 0)"), "#FF8800")
        XCTAssertEqual(ColorDetector.detect(in: "rgba(255, 136, 0, 0.5)"), "#FF8800")
    }

    func testNormalisesHSLFunction() {
        // hsl(0, 0%, 100%) is white regardless of hue.
        XCTAssertEqual(ColorDetector.detect(in: "hsl(0, 0%, 100%)"), "#FFFFFF")
        XCTAssertEqual(ColorDetector.detect(in: "hsl(0, 0%, 0%)"), "#000000")
    }

    func testRejectsNonColors() {
        XCTAssertNil(ColorDetector.detect(in: "hello world"))
        XCTAssertNil(ColorDetector.detect(in: "#12345"))          // wrong digit count
        XCTAssertNil(ColorDetector.detect(in: "#GGGGGG"))         // not hex
        XCTAssertNil(ColorDetector.detect(in: ""))
    }

    func testRejectsHexLikeWordsOfWrongLength() {
        // "deadbeef" is 8 hex digits, so it IS a valid #RRGGBBAA colour.
        // "facade" is 6 and likewise valid. This documents that ambiguity
        // rather than pretending it doesn't exist.
        XCTAssertEqual(ColorDetector.detect(in: "facade"), "#FACADE")
        XCTAssertNil(ColorDetector.detect(in: "coffee shop"))
    }
}

final class LinkDetectorTests: XCTestCase {

    func testDetectsBareURLs() {
        XCTAssertNotNil(LinkDetector.detect(in: "https://example.com"))
        XCTAssertNotNil(LinkDetector.detect(in: "http://example.com/a/b?c=d"))
        XCTAssertNotNil(LinkDetector.detect(in: "  https://example.com  "))
        XCTAssertNotNil(LinkDetector.detect(in: "mailto:someone@example.com"))
    }

    func testRejectsProseContainingAURL() {
        // Only a string that is entirely one URL counts as a link.
        XCTAssertNil(LinkDetector.detect(in: "see https://example.com for details"))
    }

    func testRejectsNonHTTPSchemes() {
        XCTAssertNil(LinkDetector.detect(in: "javascript:alert(1)"))
        XCTAssertNil(LinkDetector.detect(in: "file:///etc/passwd"))
    }

    func testRejectsPlainText() {
        XCTAssertNil(LinkDetector.detect(in: "just some words"))
        XCTAssertNil(LinkDetector.detect(in: ""))
    }
}

final class CodeDetectorTests: XCTestCase {

    func testDetectsSwift() {
        let code = """
        func greet(name: String) -> String {
            guard !name.isEmpty else { return "hi" }
            return "hello \\(name)";
        }
        """
        XCTAssertTrue(CodeDetector.looksLikeCode(code))
        XCTAssertEqual(CodeDetector.guessLanguage(code), "swift")
    }

    func testDetectsPython() {
        let code = """
        def process(items):
            for item in items:
                if item is None:
                    continue
                self.handle(item)
        """
        XCTAssertTrue(CodeDetector.looksLikeCode(code))
        XCTAssertEqual(CodeDetector.guessLanguage(code), "python")
    }

    /// Ruby closes blocks with a bare `end` and has no colons or semicolons,
    /// so it exercises a different branch of the block-structure check.
    func testDetectsRuby() {
        let code = """
        def process(items)
          items.each do |item|
            next if item.nil?
            handle(item)
          end
        end
        """
        XCTAssertTrue(CodeDetector.looksLikeCode(code))
    }

    // MARK: - False positives

    /// Lists with headings end lines in colons without being code. The colon
    /// rule requires other signals alongside it for exactly this reason.
    func testRejectsListsWithColonHeadings() {
        let recipe = """
        Ingredients:
        - flour
        - water
        Instructions:
        - mix well
        """
        XCTAssertFalse(CodeDetector.looksLikeCode(recipe))
    }

    func testRejectsMeetingNotes() {
        let notes = """
        Agenda:
        Discuss the roadmap
        Review headcount
        Next steps:
        Follow up with finance
        """
        XCTAssertFalse(CodeDetector.looksLikeCode(notes))
    }

    func testRejectsProse() {
        let prose = """
        The quick brown fox jumps over the lazy dog. This is an ordinary \
        paragraph of writing. It has several sentences. None of them are code.
        """
        XCTAssertFalse(CodeDetector.looksLikeCode(prose))
    }

    func testRejectsShortStrings() {
        XCTAssertFalse(CodeDetector.looksLikeCode("if (x)"))
        XCTAssertFalse(CodeDetector.looksLikeCode(""))
    }
}
