import Foundation

/// Moves detected keys from source files into the vault and rewrites the
/// source file so the real key is replaced with a comment marker. Intended
/// to be idempotent: re-scanning after migration yields no new detections
/// for the same key.
public actor Migrator {
    private let vault: Vault
    private let fileManager: FileManager

    public init(vault: Vault, fileManager: FileManager = .default) {
        self.vault = vault
        self.fileManager = fileManager
    }

    public struct Outcome: Sendable {
        public let detection: Detection
        public let result: Result<VaultKey, Error>
    }

    /// Migrate a batch of detections. Returns per-detection outcomes so the
    /// caller can surface which succeeded and which failed.
    public func migrate(_ detections: [Detection], bucket: VaultKey.Bucket = .personal) async -> [Outcome] {
        var outcomes: [Outcome] = []
        // Group by source file so we rewrite each file once.
        let byFile = Dictionary(grouping: detections) { $0.sourcePath }

        for (sourcePath, fileDetections) in byFile {
            // First: add each detection to the vault. Do this before the file
            // rewrite so a Keychain failure doesn't orphan the user's key.
            var keysToReplace: [(Detection, VaultKey)] = []
            for detection in fileDetections {
                do {
                    let key = try await addWithUniqueLabel(
                        provider: detection.provider,
                        baseLabel: detection.suggestedLabel,
                        bucket: bucket,
                        secret: detection.key
                    )
                    keysToReplace.append((detection, key))
                    outcomes.append(Outcome(detection: detection, result: .success(key)))
                } catch {
                    outcomes.append(Outcome(detection: detection, result: .failure(error)))
                }
            }

            guard !keysToReplace.isEmpty else { continue }

            do {
                try rewriteFile(at: sourcePath, replacing: keysToReplace)
            } catch {
                // File rewrite failure doesn't roll back the vault add; surface it
                // on every detection for this file so the user knows to clean up
                // manually.
                for i in 0..<outcomes.count where
                    outcomes[i].detection.sourcePath == sourcePath
                    && (try? outcomes[i].result.get()) != nil {
                    outcomes[i] = Outcome(detection: outcomes[i].detection, result: .failure(error))
                }
            }
        }
        return outcomes
    }

    /// Wrapper around `vault.add` that retries with an incremented suffix
    /// if the base label collides with an existing vault entry. Without
    /// this, two keys in the same source file (e.g., `OPENAI_API_KEY` and
    /// `OPENAI_API_KEY_SECOND`) both derive the same filename-based label
    /// and the second silently fails to migrate — leaving its plaintext
    /// secret in the source file.
    private func addWithUniqueLabel(
        provider: VaultKey.Provider,
        baseLabel: String,
        bucket: VaultKey.Bucket,
        secret: String
    ) async throws -> VaultKey {
        var attempt = 2
        var lastError: Error = KeychainError.duplicateItem
        // Try the base label first, then `-2`, `-3`, ... up to 20.
        for label in [baseLabel] + (2...20).map({ "\(baseLabel)-\($0)" }) {
            do {
                return try await vault.add(
                    provider: provider,
                    label: label,
                    bucket: bucket,
                    secret: secret
                )
            } catch KeychainError.duplicateItem {
                lastError = KeychainError.duplicateItem
                attempt += 1
                continue
            }
        }
        throw lastError
    }

    private func rewriteFile(at url: URL, replacing replacements: [(Detection, VaultKey)]) throws {
        let data = try Data(contentsOf: url)
        guard var text = String(data: data, encoding: .utf8) else {
            throw MigratorError.notUTF8(url)
        }

        // Replace each key value with a marker comment. We leave the rest of
        // the line (env var name, quotes, etc) alone so the file structure is
        // preserved.
        for (detection, vaultKey) in replacements {
            let marker = "shh-\(vaultKey.provider.rawValue)-\(vaultKey.label.slugified) # migrated to shh vault"
            text = text.replacingOccurrences(of: detection.key, with: marker)
        }

        try Data(text.utf8).write(to: url, options: [.atomic])
    }

    public enum MigratorError: Error, LocalizedError {
        case notUTF8(URL)
        case noKeyPatternInSecret(String, String)

        public var errorDescription: String? {
            switch self {
            case .notUTF8(let url):
                return "\(url.path) is not UTF-8 encoded"
            case .noKeyPatternInSecret(let service, let account):
                let identifier = service.isEmpty ? account : "\(service) · \(account)"
                return "\(identifier) didn't contain a recognizable API key — skipped"
            }
        }
    }

    // MARK: - Keychain imports

    public struct KeychainOutcome: Sendable {
        public let hit: KeychainHit
        public let result: Result<VaultKey, Error>
    }

    /// Import Keychain hits into the shh vault. Each hit triggers its own
    /// auth prompt (user can cancel individual entries). Originals in the
    /// source Keychain are left intact so other tools keep working.
    ///
    /// Many Keychain secrets are JSON blobs or base64-wrapped payloads that
    /// happen to *contain* an API key (Claude Code's `claude-code-credentials`
    /// is a JSON object with the key as a field, Chrome's `Safe Storage` is
    /// base64 of an opaque blob). Storing the raw secret would give us
    /// non-functional vault entries, so we run the key-pattern catalog over
    /// the secret and persist only the extracted key. If no pattern matches,
    /// the outcome is `.failure(noKeyPatternInSecret)` and nothing is added.
    public func importFromKeychain(
        _ hits: [KeychainHit],
        bucket: VaultKey.Bucket = .personal,
        scanner: KeychainScanner = KeychainScanner(),
        patterns: [KeyPattern] = KeyPattern.catalog
    ) async -> [KeychainOutcome] {
        var outcomes: [KeychainOutcome] = []
        for hit in hits {
            do {
                let raw = try scanner.readSecret(
                    hit: hit,
                    reason: "shh is importing '\(hit.account)' into its vault"
                )

                let extracted: String
                if let keyFromBlob = Self.extractKey(from: raw, provider: hit.provider, patterns: patterns) {
                    extracted = keyFromBlob
                } else if raw.count < 512 && !raw.contains("{") && !raw.contains("\"") {
                    // Short, non-JSON, non-matching — trust it as-is. Lets
                    // tier-2/3 providers with no regex still import.
                    extracted = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                } else {
                    throw MigratorError.noKeyPatternInSecret(hit.service, hit.account)
                }

                let key = try await vault.add(
                    provider: hit.provider,
                    label: hit.suggestedLabel,
                    bucket: bucket,
                    secret: extracted
                )
                outcomes.append(KeychainOutcome(hit: hit, result: .success(key)))
            } catch {
                outcomes.append(KeychainOutcome(hit: hit, result: .failure(error)))
            }
        }
        return outcomes
    }

    /// Scan a raw secret string with the pattern catalog and return the
    /// first key whose provider matches the hit. Falls back to the first
    /// match regardless of provider if the hit's provider was inferred
    /// incorrectly (e.g. an `anthropic-claude-code-credentials` blob
    /// actually containing an `sk-ant-*` key still resolves as anthropic).
    static func extractKey(
        from raw: String,
        provider: VaultKey.Provider,
        patterns: [KeyPattern]
    ) -> String? {
        let ns = raw as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        // Prefer provider-specific patterns first; fall back to the rest.
        // Two-pass avoids an O(n log n) sort on every call.
        func firstMatch(where keep: (KeyPattern) -> Bool) -> String? {
            for pattern in patterns where keep(pattern) {
                let regex = pattern.compiledRegex()
                if let match = regex.firstMatch(in: raw, options: [], range: fullRange),
                   let range = Range(match.range, in: raw) {
                    return String(raw[range])
                }
            }
            return nil
        }
        return firstMatch { $0.provider == provider }
            ?? firstMatch { $0.provider != provider }
    }
}
