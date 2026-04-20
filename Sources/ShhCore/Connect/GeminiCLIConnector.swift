import Foundation

/// Connects the Google Gemini CLI by appending a marked block of env
/// exports to the user's shell rc. Gemini CLI's SDK explicitly whitelists
/// `localhost` / `127.0.0.1` in its HTTPS check, so plain HTTP on the
/// loopback works cleanly. See `docs/research.md` §1.
public struct GeminiCLIConnector: Connector {
    public let id = "gemini-cli"
    public let displayName = "Gemini CLI"
    public let binaryName = "gemini"
    public let defaultProvider: VaultKey.Provider = .gemini

    public init() {}

    private var writer: ShellBlockWriter { ShellBlockWriter(connectorID: id) }

    public func isConnected() throws -> Bool {
        try writer.isWritten()
    }

    public func connect(token: DummyToken, proxyURL: URL) throws {
        try writer.write(envVars: [
            ("GOOGLE_GEMINI_BASE_URL", proxyURL.absoluteString),
            ("GEMINI_API_KEY", token.token),
        ])
    }

    public func disconnect() throws {
        try writer.remove()
    }

    public func previewConnect(token: DummyToken, proxyURL: URL) -> String {
        """
        Appends to \(writer.rcFile.path):

        \(writer.previewText(envVars: [
            ("GOOGLE_GEMINI_BASE_URL", proxyURL.absoluteString),
            ("GEMINI_API_KEY", token.token),
        ]))

        Open a new terminal after connecting so the env vars take effect.
        """
    }
}
