import Foundation

/// Common interface for every CLI integration. One implementation per CLI.
/// The `id` is the user-facing subcommand handle (e.g. `claude-code`,
/// `gemini-cli`); `binaryName` is what we `which` for to detect install.
public protocol Connector: Sendable {
    var id: String { get }
    var displayName: String { get }
    var binaryName: String { get }
    var defaultProvider: VaultKey.Provider { get }

    func isInstalled() -> Bool
    func isConnected() throws -> Bool
    func connect(token: DummyToken, proxyURL: URL) throws
    func disconnect() throws
    func previewConnect(token: DummyToken, proxyURL: URL) -> String
}

public extension Connector {
    func isInstalled() -> Bool {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return false }
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent(binaryName)
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return true }
        }
        return false
    }
}

/// Registry of every known Connector. Used by the `shh connect` CLI and
/// the GUI Connect sheet.
public enum Connectors {
    public static let all: [Connector] = [
        ClaudeCodeConnector(),
        GeminiCLIConnector(),
    ]

    public static func byID(_ id: String) -> Connector? {
        all.first { $0.id == id }
    }
}
