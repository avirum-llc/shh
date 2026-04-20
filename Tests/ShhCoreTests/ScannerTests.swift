import XCTest
@testable import ShhCore

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
