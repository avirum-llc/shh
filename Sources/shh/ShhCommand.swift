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

        if json {
            let payload: [String: Any] = [
                "version": Shh.version,
                "proxy": "not-implemented",
                "vault": [
                    "keys": keyCount,
                ],
            ]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("shh \(Shh.version)")
            print("  proxy: not implemented")
            print("  vault: \(keyCount) key\(keyCount == 1 ? "" : "s")")
        }
    }
}
