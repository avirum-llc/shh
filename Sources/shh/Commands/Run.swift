import ArgumentParser
import Foundation
import ShhCore

struct Run: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run a command with env vars that route it through the shh proxy.",
        discussion: """
        Injects ANTHROPIC_BASE_URL / OPENAI_BASE_URL / etc. and matching
        dummy bearer tokens into the child process's environment. Useful
        for one-off commands without touching your shell rc or CLI config.

        Example: shh run --provider anthropic --project demo --label personal -- claude "hello"
        """
    )

    @Option(help: "Provider the child will talk to.")
    var provider: String = "anthropic"

    @Option(help: "Project slug for the dummy token + log tag.")
    var project: String = "default"

    @Option(help: "Vault key label.")
    var label: String = "personal"

    @Argument(parsing: .postTerminator, help: "Command and args after `--`.")
    var command: [String] = []

    func run() async throws {
        guard !command.isEmpty else {
            throw ValidationError("Pass a command after `--`. E.g. shh run -- claude 'hello'")
        }
        let token = DummyToken(
            provider: VaultKey.Provider(rawValue: provider),
            project: project,
            keyLabel: label
        )
        let proxyURL = "http://127.0.0.1:\(ProxyServer.defaultPort)"

        var env = ProcessInfo.processInfo.environment
        let envAdditions = envVars(for: token.provider, proxyURL: proxyURL, token: token.token)
        for (k, v) in envAdditions { env[k] = v }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = command
        process.environment = env
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ExitCode(process.terminationStatus)
        }
    }

    private func envVars(
        for provider: VaultKey.Provider,
        proxyURL: String,
        token: String
    ) -> [(String, String)] {
        switch provider.rawValue {
        case "anthropic":
            return [
                ("ANTHROPIC_BASE_URL", proxyURL),
                ("ANTHROPIC_AUTH_TOKEN", token),
                ("CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC", "1"),
                ("DISABLE_TELEMETRY", "1"),
            ]
        case "gemini":
            return [
                ("GOOGLE_GEMINI_BASE_URL", proxyURL),
                ("GEMINI_API_KEY", token),
            ]
        default:
            return [
                ("OPENAI_BASE_URL", proxyURL),
                ("OPENAI_API_KEY", token),
                ("OPENAI_API_BASE", proxyURL),  // Aider
                ("ANTHROPIC_API_BASE", proxyURL),
            ]
        }
    }
}
