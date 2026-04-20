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
                    let key = try await vault.add(
                        provider: detection.provider,
                        label: detection.suggestedLabel,
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

        try text.data(using: .utf8)!.write(to: url, options: [.atomic])
    }

    public enum MigratorError: Error, LocalizedError {
        case notUTF8(URL)

        public var errorDescription: String? {
            switch self {
            case .notUTF8(let url): return "\(url.path) is not UTF-8 encoded"
            }
        }
    }
}
