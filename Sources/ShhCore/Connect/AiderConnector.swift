import Foundation

/// Connects Aider to the proxy via shell-rc env. Aider routes everything
/// through LiteLLM internally, which reads `OPENAI_API_BASE` /
/// `ANTHROPIC_API_BASE` and accepts HTTP loopback without warnings. This
/// connector writes the OpenAI side; switch the default provider if
/// you primarily drive Aider with Anthropic.
public struct AiderConnector: Connector {
    public let id = "aider"
    public let displayName = "Aider"
    public let binaryName = "aider"
    public let defaultProvider: VaultKey.Provider = .openai

    public init() {}

    private var writer: ShellBlockWriter { ShellBlockWriter(connectorID: id) }

    public func isConnected() throws -> Bool {
        try writer.isWritten()
    }

    public func connect(token: DummyToken, proxyURL: URL) throws {
        let envVars: [(String, String)]
        switch token.provider.rawValue {
        case "anthropic":
            envVars = [
                ("ANTHROPIC_API_BASE", proxyURL.absoluteString),
                ("ANTHROPIC_API_KEY", token.token),
            ]
        default:
            envVars = [
                ("OPENAI_API_BASE", proxyURL.absoluteString),
                ("OPENAI_API_KEY", token.token),
            ]
        }
        try writer.write(envVars: envVars)
    }

    public func disconnect() throws {
        try writer.remove()
    }

    public func previewConnect(token: DummyToken, proxyURL: URL) -> String {
        let envVars: [(String, String)]
        switch token.provider.rawValue {
        case "anthropic":
            envVars = [
                ("ANTHROPIC_API_BASE", proxyURL.absoluteString),
                ("ANTHROPIC_API_KEY", token.token),
            ]
        default:
            envVars = [
                ("OPENAI_API_BASE", proxyURL.absoluteString),
                ("OPENAI_API_KEY", token.token),
            ]
        }
        return """
        Appends to \(writer.rcFile.path):

        \(writer.previewText(envVars: envVars))

        Open a new terminal after connecting so the env vars take effect.
        """
    }
}
