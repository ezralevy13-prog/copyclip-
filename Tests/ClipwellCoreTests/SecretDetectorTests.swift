import XCTest
@testable import ClipwellCore

final class SecretDetectorTests: XCTestCase {

    func testDetectsPrivateKeyBlocks() {
        let key = """
        -----BEGIN RSA PRIVATE KEY-----
        MIIEowIBAAKCAQEA1234567890
        -----END RSA PRIVATE KEY-----
        """
        XCTAssertEqual(SecretDetector.scan(key), .privateKey)
        XCTAssertEqual(SecretDetector.scan("-----BEGIN OPENSSH PRIVATE KEY-----"), .privateKey)
    }

    func testDetectsProviderTokens() {
        XCTAssertEqual(SecretDetector.scan("AKIAIOSFODNN7EXAMPLE"),
                       .providerToken("AWS access key"))
        XCTAssertEqual(SecretDetector.scan("ghp_" + String(repeating: "a", count: 36)),
                       .providerToken("GitHub"))
        XCTAssertEqual(SecretDetector.scan("xoxb-123456789012-abcdefghijkl"),
                       .providerToken("Slack"))
        XCTAssertEqual(SecretDetector.scan("sk_live_" + String(repeating: "z", count: 24)),
                       .providerToken("Stripe"))
    }

    func testDetectsJWT() {
        let jwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
                + ".eyJzdWIiOiIxMjM0NTY3ODkwIn0"
                + ".dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        XCTAssertEqual(SecretDetector.scan(jwt), .providerToken("JSON Web Token"))
    }

    func testDetectsCredentialAssignments() {
        XCTAssertEqual(SecretDetector.scan("password = \"hunter2hunter2\""), .credentialAssignment)
        XCTAssertEqual(SecretDetector.scan("API_KEY=abcdef1234567890"), .credentialAssignment)
        XCTAssertEqual(SecretDetector.scan("client_secret: s0mel0ngsecret"), .credentialAssignment)
    }

    func testDetectsCardNumbersViaLuhn() {
        // Well-known test numbers that satisfy Luhn.
        XCTAssertEqual(SecretDetector.scan("4111111111111111"), .creditCard)
        XCTAssertEqual(SecretDetector.scan("4111 1111 1111 1111"), .creditCard)
    }

    func testIgnoresDigitsThatFailLuhn() {
        // A long number that isn't a card: an order ID, a phone number, an ISBN.
        XCTAssertNil(SecretDetector.scan("1234567812345678"))
    }

    // MARK: - False positives are the expensive failure here

    func testAllowsOrdinaryProse() {
        XCTAssertNil(SecretDetector.scan("I forgot my password again"))
        XCTAssertNil(SecretDetector.scan("the secret to good bread is time"))
        XCTAssertNil(SecretDetector.scan("Let's meet at 3pm to discuss the API key rotation plan"))
    }

    func testAllowsCodeThatMerelyMentionsCredentials() {
        let code = """
        const token = process.env.ACCESS_TOKEN;
        if (!token) throw new Error("missing token");
        """
        XCTAssertNil(SecretDetector.scan(code), "referencing an env var is not a leaked secret")
    }

    func testIgnoresLongDocuments() {
        // A whole document that happens to contain a key-like string is not the
        // short copy-a-credential case this targets.
        let long = String(repeating: "lorem ipsum dolor sit amet ", count: 300) + "AKIAIOSFODNN7EXAMPLE"
        XCTAssertNil(SecretDetector.scan(long))
    }

    func testLuhnItself() {
        XCTAssertTrue(SecretDetector.passesLuhn("4111111111111111"))
        XCTAssertTrue(SecretDetector.passesLuhn("79927398713"))
        XCTAssertFalse(SecretDetector.passesLuhn("79927398710"))
        XCTAssertFalse(SecretDetector.passesLuhn(""))
        XCTAssertFalse(SecretDetector.passesLuhn("not digits"))
    }
}
