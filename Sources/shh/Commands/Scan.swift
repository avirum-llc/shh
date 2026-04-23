import ArgumentParser
import Foundation
import ShhCore

struct Scan: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scan",
        abstract: "Scan shell configs and project folders for API keys you can import into the vault."
    )

    @Flag(help: "Migrate all high-confidence detections into the vault, rewriting the source files.")
    var migrate: Bool = false

    @Flag(help: "Include medium and low confidence detections in the output.")
    var all: Bool = false

    @Flag(help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        let scanner = FileScanner()
        let detections = scanner.scan()

        let visible = all ? detections : detections.filter { $0.confidence == .high || $0.confidence == .mediumHint }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = visible.map { d -> [String: String] in
                [
                    "provider": d.provider.rawValue,
                    "tier": "\(d.tier)",
                    "confidence": d.confidence.rawValue,
                    "path": d.sourcePath.path,
                    "line": "\(d.lineNumber)",
                    "fingerprint": d.fingerprint,
                    "envHint": d.envHintMatched ?? "",
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        if visible.isEmpty {
            print("No API keys found in the scanned locations.")
            return
        }

        print("Found \(visible.count) key\(visible.count == 1 ? "" : "s"):")
        for d in visible {
            let path = d.sourcePath.path.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
            let hint = d.envHintMatched.map { " (\($0))" } ?? ""
            print("  [\(d.confidence.rawValue)] \(d.provider.rawValue.padding(toLength: 12, withPad: " ", startingAt: 0)) ···\(d.fingerprint)\(hint)")
            print("        \(path):\(d.lineNumber)")
        }

        if migrate {
            print("")
            print("Migrating high-confidence detections…")
            let toMigrate = detections.filter { $0.confidence == .high }
            if toMigrate.isEmpty {
                print("No high-confidence detections to migrate.")
                return
            }
            let migrator = Migrator(vault: Vault())
            let outcomes = await migrator.migrate(toMigrate)
            for outcome in outcomes {
                switch outcome.result {
                case .success(let key):
                    print("  ✓ \(key.provider.rawValue)/\(key.label) saved")
                case .failure(let error):
                    print("  ✗ \(outcome.detection.provider.rawValue): \(error.localizedDescription)")
                }
            }
        } else if !visible.isEmpty {
            print("")
            print("Run `shh scan --migrate` to move these into the vault and rewrite the source files.")
        }
    }
}
