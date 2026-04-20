import ArgumentParser
import Foundation
import ShhCore

struct Connect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "connect",
        abstract: "Route an AI CLI through the local proxy.",
        subcommands: [ConnectList.self, ConnectTool.self, ConnectDisconnect.self],
        defaultSubcommand: ConnectList.self
    )
}

struct ConnectList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List supported CLIs and their current state.",
        aliases: ["ls"]
    )

    @Flag(help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        var rows: [(Connector, String, String)] = []
        for connector in Connectors.all {
            let installed = connector.isInstalled() ? "installed" : "not detected"
            let connected = (try? connector.isConnected()) ?? false ? "connected" : "not connected"
            rows.append((connector, installed, connected))
        }

        if json {
            let payload = rows.map { (c, i, conn) -> [String: String] in
                [
                    "id": c.id,
                    "name": c.displayName,
                    "binary": c.binaryName,
                    "install_state": i,
                    "connect_state": conn,
                ]
            }
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        print("Supported CLIs:")
        for (c, install, connect) in rows {
            print("  \(c.id.padding(toLength: 14, withPad: " ", startingAt: 0))  \(c.displayName.padding(toLength: 16, withPad: " ", startingAt: 0))  \(install)  ·  \(connect)")
        }
        print("")
        print("Connect one with:")
        print("  shh connect <id> --project <name> --label <key-label>")
    }
}

struct ConnectTool: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tool",
        abstract: "Connect a specific CLI.",
        discussion: """
        Writes the proxy URL and a dummy bearer token into the CLI's config
        or shell rc, depending on the CLI. Your real key stays in the
        vault; the CLI only ever sees the dummy token.
        """
    )

    @Argument(help: "Connector id (claude-code, gemini-cli, …).")
    var id: String

    @Option(help: "Project slug — becomes part of the dummy token and the log tag.")
    var project: String = "default"

    @Option(help: "Vault key label to route this CLI to (the label you gave when adding the key).")
    var label: String = "personal"

    @Flag(help: "Print what would be written without modifying anything.")
    var dryRun: Bool = false

    func run() async throws {
        guard let connector = Connectors.byID(id) else {
            throw ValidationError("Unknown connector '\(id)'. Run `shh connect list` to see supported CLIs.")
        }
        let token = DummyToken(
            provider: connector.defaultProvider,
            project: project,
            keyLabel: label
        )
        let proxyURL = URL(string: "http://127.0.0.1:\(ProxyServer.defaultPort)")!

        if dryRun {
            print(connector.previewConnect(token: token, proxyURL: proxyURL))
            return
        }

        try connector.connect(token: token, proxyURL: proxyURL)
        print("Connected \(connector.displayName).")
        print("Dummy token: \(token.token)")
        print("Make sure the shh menubar app is running so the proxy is listening on \(proxyURL.absoluteString).")
    }
}

struct ConnectDisconnect: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "disconnect",
        abstract: "Undo a previous `shh connect`."
    )

    @Argument(help: "Connector id (claude-code, gemini-cli, …).")
    var id: String

    func run() async throws {
        guard let connector = Connectors.byID(id) else {
            throw ValidationError("Unknown connector '\(id)'.")
        }
        try connector.disconnect()
        print("Disconnected \(connector.displayName).")
    }
}
