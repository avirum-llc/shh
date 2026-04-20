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
        ],
        defaultSubcommand: Status.self
    )
}

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Show proxy and vault status."
    )

    @Flag(help: "Emit JSON instead of human-readable text.")
    var json: Bool = false

    func run() throws {
        if json {
            let payload: [String: Any] = [
                "version": Shh.version,
                "proxy": "not-implemented",
                "vault": "not-implemented",
            ]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            print("shh \(Shh.version)")
            print("  proxy: not implemented")
            print("  vault: not implemented")
        }
    }
}
