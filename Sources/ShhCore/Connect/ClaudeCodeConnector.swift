import Foundation

/// Connects Claude Code to the local proxy by writing `env` entries into
/// `~/.claude/settings.json`. Uses a dict-merge strategy so existing
/// settings are preserved. See `docs/research.md` §1 for the specifics:
/// `ANTHROPIC_AUTH_TOKEN` (Bearer) is the right env var when using a
/// custom base URL (not `ANTHROPIC_API_KEY`, which is `x-api-key`).
public struct ClaudeCodeConnector: Connector {
    public let id = "claude-code"
    public let displayName = "Claude Code"
    public let binaryName = "claude"
    public let defaultProvider: VaultKey.Provider = .anthropic

    public init() {}

    public var settingsPath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    public func isConnected() throws -> Bool {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else { return false }
        let data = try Data(contentsOf: settingsPath)
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = root["env"] as? [String: Any],
              let baseURL = env["ANTHROPIC_BASE_URL"] as? String else {
            return false
        }
        return baseURL.contains("127.0.0.1") || baseURL.contains("localhost")
    }

    public func connect(token: DummyToken, proxyURL: URL) throws {
        var root: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsPath.path) {
            let data = try Data(contentsOf: settingsPath)
            root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        }
        var env = (root["env"] as? [String: Any]) ?? [:]
        env["ANTHROPIC_BASE_URL"] = proxyURL.absoluteString
        env["ANTHROPIC_AUTH_TOKEN"] = token.token
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["DISABLE_TELEMETRY"] = "1"
        env["DISABLE_ERROR_REPORTING"] = "1"
        root["env"] = env

        try FileManager.default.createDirectory(
            at: settingsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsPath, options: [.atomic])
    }

    public func disconnect() throws {
        guard FileManager.default.fileExists(atPath: settingsPath.path) else { return }
        let data = try Data(contentsOf: settingsPath)
        guard var root = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) else {
            return
        }
        if var env = root["env"] as? [String: Any] {
            env.removeValue(forKey: "ANTHROPIC_BASE_URL")
            env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
            env.removeValue(forKey: "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC")
            env.removeValue(forKey: "DISABLE_TELEMETRY")
            env.removeValue(forKey: "DISABLE_ERROR_REPORTING")
            if env.isEmpty {
                root.removeValue(forKey: "env")
            } else {
                root["env"] = env
            }
        }
        let updated = try JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
        try updated.write(to: settingsPath, options: [.atomic])
    }

    public func previewConnect(token: DummyToken, proxyURL: URL) -> String {
        """
        Writes to \(settingsPath.path):

          env:
            ANTHROPIC_BASE_URL: \(proxyURL.absoluteString)
            ANTHROPIC_AUTH_TOKEN: \(token.token)
            CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1"
            DISABLE_TELEMETRY: "1"
            DISABLE_ERROR_REPORTING: "1"

        Note: DISABLE_NONESSENTIAL_TRAFFIC also disables the 1M-context
        gate, /remote-control, and Statsig A/B tests. Unset if you need
        any of those features back.
        """
    }
}
