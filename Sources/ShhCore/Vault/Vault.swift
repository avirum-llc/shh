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
        try loadMetadata()
    }

    public func get(id: String) throws -> VaultKey? {
        try loadMetadata().first { $0.id == id }
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

        var all = (try? loadMetadata()) ?? []
        all.removeAll { $0.id == id }
        all.append(key)
        try saveMetadata(all)

        return key
    }

    public func remove(id: String) throws {
        try store.remove(id: id)
        var all = (try? loadMetadata()) ?? []
        all.removeAll { $0.id == id }
        try saveMetadata(all)
    }

    /// Read a secret. Triggers Touch ID if the LAContext reuse window is
    /// expired.
    public func read(id: String, reason: String) throws -> String {
        let secret = try store.read(id: id, reason: reason)

        if var all = try? loadMetadata(),
           let idx = all.firstIndex(where: { $0.id == id }) {
            all[idx].lastUsedAt = Date()
            try? saveMetadata(all)
        }

        return secret
    }

    // MARK: - Private

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
