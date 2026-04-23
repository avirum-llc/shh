import Foundation

/// High-level vault API.
///
/// Metadata (non-secret) is persisted to
/// `~/.config/shh/vault-metadata.json`; secrets live in Keychain. Mutations
/// touch Keychain first, then metadata, so a failed Keychain write never
/// leaves dangling metadata.
public actor Vault {
    public static let defaultMetadataPath: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("shh", isDirectory: true)
            .appendingPathComponent("vault-metadata.json")
    }()

    private let store: KeychainStore
    private let metadataPath: URL

    public init(
        store: KeychainStore = KeychainStore(),
        metadataPath: URL = Vault.defaultMetadataPath
    ) {
        self.store = store
        self.metadataPath = metadataPath
    }

    public func list() throws -> [VaultKey] {
        try withFileLock { try loadMetadata() }
    }

    public func get(id: String) throws -> VaultKey? {
        try withFileLock { try loadMetadata().first { $0.id == id } }
    }

    @discardableResult
    public func add(
        provider: VaultKey.Provider,
        label: String,
        bucket: VaultKey.Bucket,
        secret: String
    ) throws -> VaultKey {
        let id = VaultKey.makeID(provider: provider, label: label)
        let fingerprint = String(secret.suffix(4))
        let key = VaultKey(
            id: id,
            provider: provider,
            label: label,
            bucket: bucket,
            fingerprint: fingerprint
        )

        try store.add(id: id, secret: secret)

        try withFileLock {
            // Re-read inside the lock so we don't overwrite a concurrent
            // cross-process write. This prevents the lost-update bug where
            // the GUI app and CLI both add keys in quick succession and
            // one write silently drops the other's entry from metadata.
            var all = (try? loadMetadata()) ?? []
            all.removeAll { $0.id == id }
            all.append(key)
            try saveMetadata(all)
        }

        return key
    }

    public func remove(id: String) throws {
        try store.remove(id: id)
        try withFileLock {
            var all = (try? loadMetadata()) ?? []
            all.removeAll { $0.id == id }
            try saveMetadata(all)
        }
    }

    /// Read a secret. Triggers Touch ID if the LAContext reuse window is
    /// expired.
    public func read(id: String, reason: String) throws -> String {
        let secret = try store.read(id: id, reason: reason)

        // Best-effort lastUsedAt update inside the lock so it doesn't
        // race with an add/remove from another process.
        try? withFileLock {
            if var all = try? loadMetadata(),
               let idx = all.firstIndex(where: { $0.id == id }) {
                all[idx].lastUsedAt = Date()
                try saveMetadata(all)
            }
        }

        return secret
    }

    // MARK: - Private

    /// Serialize metadata read-modify-write sequences across processes using
    /// an advisory file lock (`flock(LOCK_EX)`) on a sibling `.lock` file.
    /// The lock file is created once per vault directory and persists; the
    /// lock itself is released when the fd is closed (end of closure).
    ///
    /// Without this, two processes (GUI + CLI, or two CLI instances)
    /// racing on `vault.add` / `vault.remove` can lose updates because
    /// each does `load -> modify -> atomic write` with stale data.
    private func withFileLock<T>(_ body: () throws -> T) throws -> T {
        let lockDir = metadataPath.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: lockDir,
            withIntermediateDirectories: true
        )
        let lockURL = lockDir.appendingPathComponent(".\(metadataPath.lastPathComponent).lock")

        let fd = open(lockURL.path, O_RDWR | O_CREAT, 0o644)
        guard fd >= 0 else {
            throw VaultError.lockFailed(errno: errno)
        }
        defer { close(fd) }

        guard flock(fd, LOCK_EX) == 0 else {
            throw VaultError.lockFailed(errno: errno)
        }
        defer { _ = flock(fd, LOCK_UN) }

        return try body()
    }

    private func loadMetadata() throws -> [VaultKey] {
        guard FileManager.default.fileExists(atPath: metadataPath.path) else {
            return []
        }
        let data = try Data(contentsOf: metadataPath)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([VaultKey].self, from: data)
    }

    private func saveMetadata(_ keys: [VaultKey]) throws {
        try FileManager.default.createDirectory(
            at: metadataPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(keys)
        try data.write(to: metadataPath, options: [.atomic])
    }
}

public enum VaultError: Error, LocalizedError {
    case lockFailed(errno: Int32)

    public var errorDescription: String? {
        switch self {
        case .lockFailed(let e):
            return "Could not lock vault metadata (errno \(e))"
        }
    }
}
