import XCTest
@testable import ShhCore

final class VaultKeyTests: XCTestCase {
    func testMakeIDSlugifiesLabel() {
        let id = VaultKey.makeID(provider: .anthropic, label: "My Personal")
        XCTAssertEqual(id, "anthropic-my-personal")
    }

    func testMakeIDLowercasesArbitraryProvider() {
        let id = VaultKey.makeID(provider: VaultKey.Provider(rawValue: "Anthropic"), label: "work")
        XCTAssertEqual(id, "anthropic-work")
    }

    func testProviderCaseInsensitive() {
        XCTAssertEqual(VaultKey.Provider(rawValue: "ANTHROPIC"), VaultKey.Provider.anthropic)
        XCTAssertEqual("Anthropic" as VaultKey.Provider, VaultKey.Provider.anthropic)
    }

    func testBucketRawValues() {
        XCTAssertEqual(VaultKey.Bucket.personal.rawValue, "personal")
        XCTAssertEqual(VaultKey.Bucket.work.rawValue, "work")
    }

    func testMeteredSet() {
        XCTAssertTrue(VaultKey.Provider.metered.contains(.anthropic))
        XCTAssertTrue(VaultKey.Provider.metered.contains(.openai))
        XCTAssertTrue(VaultKey.Provider.metered.contains(.gemini))
        XCTAssertFalse(VaultKey.Provider.metered.contains(.groq))
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let original = VaultKey(
            id: "anthropic-personal",
            provider: .anthropic,
            label: "personal",
            bucket: .personal,
            fingerprint: "wK4z",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastUsedAt: nil
        )
        let encoded = try encoder.encode(original)
        let decoded = try decoder.decode(VaultKey.self, from: encoded)
        XCTAssertEqual(original, decoded)
    }

    func testSlugifiedEdgeCases() {
        XCTAssertEqual("Hello World".slugified, "hello-world")
        XCTAssertEqual("FOO_BAR-baz".slugified, "foo_bar-baz")
        XCTAssertEqual("   spaces   ".slugified, "---spaces---")
        XCTAssertEqual("weird!@#$chars".slugified, "weirdchars")
    }
}

final class KeychainStoreConstructionTests: XCTestCase {
    // Keychain integration tests need a signed test bundle with biometric
    // entitlements — deferred to Phase 1B (Xcode project). The only
    // swift-test-runnable check is that the type constructs correctly.
    func testDefaultInitialization() {
        let store = KeychainStore()
        XCTAssertEqual(store.service, "com.avirumapps.shh")
        XCTAssertEqual(store.reuseDuration, 300)
    }

    func testCustomInitialization() {
        let store = KeychainStore(service: "com.test.shh", reuseDuration: 60)
        XCTAssertEqual(store.service, "com.test.shh")
        XCTAssertEqual(store.reuseDuration, 60)
    }
}
