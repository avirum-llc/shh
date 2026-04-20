import ArgumentParser
import Foundation
import ShhCore

@main
struct ShhCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "shh",
        abstract: "Your AI keys never speak above a whisper.",
        version: Shh.version,
        subcommands: [
            Status.self,
            Keys.self,
            Scan.self,
            Connect.self,
            Run.self,
            ProxyCommand.self,
            SpendCommand.self,
        ],
        defaultSubcommand: Status.self
    )
}

struct Status: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show proxy and vault status."
    )

    @Flag(help: "Emit JSON instead of human-readable text.")
    var json: Bool = false

    func run() async throws {
        let vault = Vault()
        let keyCount = (try? await vault.list().count) ?? 0

        var proxyRunning = false
        let pingURL = URL(string: "http://127.0.0.1:\(ProxyServer.defaultPort)/__shh_ping__")!
        var req = URLRequest(url: pingURL)
        req.timeoutInterval = 1
        if let (_, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse, http.statusCode == 200 {
            proxyRunning = true
        }

        let log = RequestLog()
        let todayRecords = (try? await log.since(Calendar.current.startOfDay(for: Date()))) ?? []
        let todayCost = todayRecords.reduce(0.0) { $0 + $1.costUSDEstimated }

        if json {
            let payload: [String: Any] = [
                "version": Shh.version,
                "proxy": [
                    "running": proxyRunning,
                    "port": ProxyServer.defaultPort,
                ],
                "vault": [
                    "keys": keyCount,
                ],
                "spend": [
                    "today_usd_estimated": todayCost,
                    "request_count_today": todayRecords.count,
                ],
            ]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("shh \(Shh.version)")
            print("  proxy: \(proxyRunning ? "running on 127.0.0.1:\(ProxyServer.defaultPort)" : "not reachable")")
            print("  vault: \(keyCount) key\(keyCount == 1 ? "" : "s")")
            print(String(format: "  today: $%.4f estimated · %d request%@", todayCost, todayRecords.count, todayRecords.count == 1 ? "" : "s"))
        }
    }
}
