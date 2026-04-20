import Foundation

/// Connects OpenAI Codex (`@openai/codex`) to the proxy via shell-rc env.
/// Uses `OPENAI_BASE_URL` + `OPENAI_API_KEY` against the built-in
/// `openai` provider — the safest path per research.md §1 (custom-
/// provider env-only config has known issues — OpenAI issue #652).
public struct OpenAICodexConnector: Connector {
    public let id = "codex"
    public let displayName = "OpenAI Codex"
    public let binaryName = "codex"
    public let defaultProvider: VaultKey.Provider = .openai

    public init() {}

    private var writer: ShellBlockWriter { ShellBlockWriter(connectorID: id) }

    public func isConnected() throws -> Bool {
        try writer.isWritten()
    }

    public func connect(token: DummyToken, proxyURL: URL) throws {
        try writer.write(envVars: [
            ("OPENAI_BASE_URL", proxyURL.absoluteString),
            ("OPENAI_API_KEY", token.token),
        ])
    }

    public func disconnect() throws {
        try writer.remove()
    }

    public func previewConnect(token: DummyToken, proxyURL: URL) -> String {
        """
        Appends to \(writer.rcFile.path):

        \(writer.previewText(envVars: [
            ("OPENAI_BASE_URL", proxyURL.absoluteString),
            ("OPENAI_API_KEY", token.token),
        ]))

        Open a new terminal after connecting so the env vars take effect.
        """
    }
}
