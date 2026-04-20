import Foundation

/// Connects OpenCode (`sst/opencode`) by patching its provider config.
/// OpenCode has no first-class env-var override for base URL — the right
/// path is `~/.config/opencode/opencode.json` with a `provider` block
/// (research.md §1).
public struct OpenCodeConnector: Connector {
    public let id = "opencode"
    public let displayName = "OpenCode"
    public let binaryName = "opencode"
    public let defaultProvider: VaultKey.Provider = .anthropic

    public init() {}

    public var configPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("opencode", isDirectory: true)
            .appendingPathComponent("opencode.json")
    }

    public func isConnected() throws -> Bool {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return false }
        let data = try Data(contentsOf: configPath)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let providers = root["provider"] as? [String: Any] else {
            return false
        }
        for (_, value) in providers {
            if let dict = value as? [String: Any],
               let url = dict["baseURL"] as? String,
               url.contains("127.0.0.1") || url.contains("localhost") {
                return true
            }
        }
        return false
    }

    public func connect(token: DummyToken, proxyURL: URL) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: configPath.path) {
            let data = try Data(contentsOf: configPath)
            root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        var providers = (root["provider"] as? [String: Any]) ?? [:]
        providers[token.provider.rawValue] = [
            "baseURL": proxyURL.absoluteString,
            "apiKey": token.token,
        ] as [String: Any]
        root["provider"] = providers

        try FileManager.default.createDirectory(
            at: configPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: configPath, options: [.atomic])
    }

    public func disconnect() throws {
        guard FileManager.default.fileExists(atPath: configPath.path) else { return }
        let data = try Data(contentsOf: configPath)
        guard var root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        if var providers = root["provider"] as? [String: Any] {
            // Remove only provider entries that point at the local proxy.
            for (name, value) in providers {
                if let dict = value as? [String: Any],
                   let url = dict["baseURL"] as? String,
                   url.contains("127.0.0.1") || url.contains("localhost") {
                    providers.removeValue(forKey: name)
                }
            }
            if providers.isEmpty {
                root.removeValue(forKey: "provider")
            } else {
                root["provider"] = providers
            }
        }
        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updated.write(to: configPath, options: [.atomic])
    }

    public func previewConnect(token: DummyToken, proxyURL: URL) -> String {
        """
        Merges into \(configPath.path):

          provider:
            \(token.provider.rawValue):
              baseURL: \(proxyURL.absoluteString)
              apiKey:  \(token.token)
        """
    }
}
