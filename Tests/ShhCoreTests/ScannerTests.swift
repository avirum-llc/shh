import XCTest
@testable import ShhCore

final class TokenCounterParseModelTests: XCTestCase {
    func testGeminiModelFromRestPath() {
        let m = TokenCounter.extractGeminiModel(fromPath: "/v1beta/models/gemini-2.5-flash:generateContent")
        XCTAssertEqual(m, "gemini-2.5-flash")
    }

    func testGeminiModelWithQueryString() {
        let m = TokenCounter.extractGeminiModel(fromPath: "/v1beta/models/gemini-2.5-pro:streamGenerateContent?alt=sse")
        XCTAssertEqual(m, "gemini-2.5-pro")
    }

    func testGeminiModelDispatchUsesPath() {
        let body = Data("{\"contents\":[]}".utf8)
        let m = TokenCounter.parseModel(provider: .gemini, path: "/v1beta/models/gemini-2.5-flash:generateContent", body: body)
        XCTAssertEqual(m, "gemini-2.5-flash")
    }

    func testAnthropicDispatchUsesBody() {
        let body = Data("{\"model\":\"claude-haiku-4-5\",\"messages\":[]}".utf8)
        let m = TokenCounter.parseModel(provider: .anthropic, path: "/v1/messages", body: body)
        XCTAssertEqual(m, "claude-haiku-4-5")
    }

    func testGeminiCostResolvesAfterExtraction() {
        let rates = PriceTable.bundled
        let cost = rates.cost(provider: .gemini, model: "gemini-2.5-flash", inputTokens: 1_000_000, outputTokens: 1_000_000)
        XCTAssertEqual(cost, 0.3 + 2.5, accuracy: 0.001)
    }
}

final class MigratorExtractKeyTests: XCTestCase {
    func testExtractsAnthropicFromJSONBlob() {
        let suffix = String(repeating: "x", count: 95)
        let blob = #"{"claudeAiOauth":{"accessToken":"sk-ant-api03-\#(suffix)","refreshToken":"rt","expiresAt":1734000000}}"#
        let out = Migrator.extractKey(from: blob, provider: .anthropic, patterns: KeyPattern.catalog)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.hasPrefix("sk-ant-api03-"))
        XCTAssertFalse(out!.contains("{"), "Extracted key should not contain JSON braces")
    }

    func testExtractsGeminiFromSettingsBlob() {
        let suffix = String(repeating: "a", count: 35)
        let blob = #"{"env":{"GEMINI_API_KEY":"AIza\#(suffix)"}}"#
        let out = Migrator.extractKey(from: blob, provider: .gemini, patterns: KeyPattern.catalog)
        XCTAssertNotNil(out)
        XCTAssertTrue(out!.hasPrefix("AIza"))
    }

    func testNilWhenBlobHasNoKeyPattern() {
        let blob = #"{"version":"1.0","config":"nothing-secret-like-in-here"}"#
        let out = Migrator.extractKey(from: blob, provider: .anthropic, patterns: KeyPattern.catalog)
        XCTAssertNil(out)
    }

    func testBase64PaddingAloneReturnsNil() {
        let blob = "PQ=="
        let out = Migrator.extractKey(from: blob, provider: .anthropic, patterns: KeyPattern.catalog)
        XCTAssertNil(out)
    }
}

final class KeychainScannerClassifyTests: XCTestCase {
    func testClassifyAnthropicByService() {
        let c = KeychainScanner.classify(service: "Anthropic API", account: "token", label: nil)
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.provider, .anthropic)
        XCTAssertEqual(c?.confidence, .high)
    }

    func testClassifyAnthropicByEnvVarAccount() {
        let c = KeychainScanner.classify(service: "roast-eval", account: "ANTHROPIC_API_KEY", label: nil)
        XCTAssertNotNil(c)
        XCTAssertEqual(c?.provider, .anthropic)
        XCTAssertEqual(c?.confidence, .high)
    }

    func testClassifyOpenAIEnvVarOnlyGivesMediumHint() {
        // Account shaped like an env var for a provider whose name itself
        // is *not* present → lands in the mediumHint bucket.
        let c = KeychainScanner.classify(service: "deploy-bot", account: "HF_TOKEN", label: nil)
        XCTAssertEqual(c?.provider, .huggingface)
        XCTAssertEqual(c?.confidence, .mediumHint)
    }

    func testClassifyGeminiAiStudio() {
        let c = KeychainScanner.classify(service: "aistudio.google.com", account: "user", label: nil)
        XCTAssertEqual(c?.provider, .gemini)
        XCTAssertEqual(c?.confidence, .high)
    }

    func testClassifyGenericApiKey() {
        let c = KeychainScanner.classify(service: "some-service", account: "api_key", label: nil)
        XCTAssertEqual(c?.provider.rawValue, "generic")
        XCTAssertEqual(c?.confidence, .low)
    }

    func testClassifyReturnsNilForWifi() {
        let c = KeychainScanner.classify(service: "airport", account: "HomeWifi", label: nil)
        XCTAssertNil(c)
    }

    func testClassifyReturnsNilForPlainText() {
        let c = KeychainScanner.classify(service: "Notes", account: "manish", label: nil)
        XCTAssertNil(c)
    }

    func testClassifyLabelContributes() {
        let c = KeychainScanner.classify(service: "opaque", account: "key", label: "OpenAI Production")
        XCTAssertEqual(c?.provider, .openai)
    }
}

final class KeyPatternCatalogTests: XCTestCase {
    func testCatalogCompilesAllRegexes() {
        for pattern in KeyPattern.catalog {
            XCTAssertNoThrow(
                try NSRegularExpression(pattern: pattern.regex, options: []),
                "Pattern for \(pattern.provider.rawValue) did not compile: \(pattern.regex)"
            )
        }
    }

    func testAnthropicPatternMatches() {
        let catalog = KeyPattern.catalog.first { $0.provider == .anthropic }
        XCTAssertNotNil(catalog)
        let regex = catalog!.compiledRegex()
        let sample = "sk-ant-api03-" + String(repeating: "a", count: 95)
        let matches = regex.matches(in: sample, options: [], range: NSRange(location: 0, length: sample.utf16.count))
        XCTAssertEqual(matches.count, 1)
    }

    func testOpenAIProjectPattern() {
        let catalog = KeyPattern.catalog.first {
            $0.provider == .openai && $0.regex.contains("svcacct")
        }
        XCTAssertNotNil(catalog)
        let sample = "OPENAI_API_KEY=sk-proj-\(String(repeating: "x", count: 60))"
        let regex = catalog!.compiledRegex()
        let matches = regex.matches(in: sample, options: [], range: NSRange(location: 0, length: sample.utf16.count))
        XCTAssertEqual(matches.count, 1)
    }

    func testGeminiPatternDoesNotMatchShortString() {
        let regex = KeyPattern.catalog.first { $0.provider == .gemini }!.compiledRegex()
        let short = "AIza_short"
        let matches = regex.matches(in: short, options: [], range: NSRange(location: 0, length: short.utf16.count))
        XCTAssertEqual(matches.count, 0)
    }
}

final class FileScannerTests: XCTestCase {
    func testScansEnvFileForAnthropicKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shh-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let envFile = dir.appendingPathComponent(".env")
        let content = """
        # dev env
        ANTHROPIC_API_KEY=sk-ant-api03-\(String(repeating: "a", count: 90))
        OPENAI_API_KEY=sk-proj-\(String(repeating: "b", count: 60))
        IRRELEVANT=hello
        """
        try content.write(to: envFile, atomically: true, encoding: .utf8)

        let scanner = FileScanner(roots: [envFile])
        let detections = scanner.scan()

        XCTAssertEqual(detections.count, 2)
        XCTAssertTrue(detections.contains { $0.provider == .anthropic })
        XCTAssertTrue(detections.contains { $0.provider == .openai })

        let anthropicHit = detections.first { $0.provider == .anthropic }!
        XCTAssertEqual(anthropicHit.confidence, .high)
        XCTAssertEqual(anthropicHit.envHintMatched, "ANTHROPIC_API_KEY")
    }

    func testNoDetectionsOnCleanFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shh-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent(".env")
        try "DATABASE_URL=postgres://user:pass@localhost/db\n".write(to: file, atomically: true, encoding: .utf8)

        let scanner = FileScanner(roots: [file])
        XCTAssertTrue(scanner.scan().isEmpty)
    }
}

final class MigratorTests: XCTestCase {
    func testMigrateRewritesSource() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("shh-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let envFile = dir.appendingPathComponent(".env")
        let realKey = "sk-ant-api03-" + String(repeating: "q", count: 90)
        try "ANTHROPIC_API_KEY=\(realKey)\n".write(to: envFile, atomically: true, encoding: .utf8)

        let scanner = FileScanner(roots: [envFile])
        let detections = scanner.scan()
        XCTAssertEqual(detections.count, 1)

        // Use an isolated vault + keychain store service so the test doesn't
        // touch the user's real vault.
        let metadataPath = dir.appendingPathComponent("meta.json")
        let store = KeychainStore(service: "com.avirumapps.shh.tests-\(UUID().uuidString)")
        let vault = Vault(store: store, metadataPath: metadataPath)
        let migrator = Migrator(vault: vault)

        let outcomes = await migrator.migrate(detections)
        XCTAssertEqual(outcomes.count, 1)

        // Check source file was rewritten (real key no longer present)
        let rewritten = try String(contentsOf: envFile, encoding: .utf8)
        XCTAssertFalse(rewritten.contains(realKey))
        XCTAssertTrue(rewritten.contains("migrated to shh vault"))

        // Clean up the keychain entry from the test store.
        if case .success(let key) = outcomes[0].result {
            try? store.remove(id: key.id)
        }
    }
}
