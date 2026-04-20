import ArgumentParser
import Foundation
import ShhCore

struct ProxyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "proxy",
        abstract: "Manage the local HTTP proxy.",
        subcommands: [ProxyStatus.self, ProxyStart.self, ProxyStop.self],
        defaultSubcommand: ProxyStatus.self
    )
}

struct ProxyStart: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "start",
        abstract: "Run the proxy in the foreground (useful for debugging)."
    )

    func run() async throws {
        let server = ProxyServer(vault: Vault())
        try await server.start()
        print("shh proxy listening on http://127.0.0.1:\(server.port)")
        print("Press Ctrl-C to stop.")
        try await Task.sleep(nanoseconds: .max)
    }
}

struct ProxyStop: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "stop",
        abstract: "Stop the proxy (v0.1: quit the menubar app instead)."
    )
    func run() async throws {
        print("In v0.1 the proxy runs inside the shh menubar app. Quit the app to stop it.")
    }
}

struct ProxyStatus: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Ping the local proxy to see if it's running."
    )

    @Flag(help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        var reachable = false
        let url = URL(string: "http://127.0.0.1:\(ProxyServer.defaultPort)/__shh_ping__")!
        var req = URLRequest(url: url)
        req.timeoutInterval = 1
        if let (_, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse,
           http.statusCode == 200 {
            reachable = true
        }

        if json {
            print(#"{"proxy":"\#(reachable ? "running" : "down")","port":\#(ProxyServer.defaultPort)}"#)
        } else {
            if reachable {
                print("Proxy: running on 127.0.0.1:\(ProxyServer.defaultPort)")
            } else {
                print("Proxy: not reachable. Open the shh menubar app.")
            }
        }
    }
}
