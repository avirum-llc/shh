import ArgumentParser
import Darwin
import Foundation
import ShhCore

struct Keys: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "keys",
        abstract: "Manage API keys in the vault.",
        subcommands: [KeysList.self, KeysAdd.self, KeysRemove.self],
        defaultSubcommand: KeysList.self
    )
}

// MARK: - list

struct KeysList: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List keys in the vault (last-4 only, never secrets).",
        aliases: ["ls"]
    )

    @Flag(help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        let vault = Vault()
        let keys = try await vault.list()

        if json {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(keys)
            print(String(data: data, encoding: .utf8) ?? "[]")
            return
        }

        guard !keys.isEmpty else {
            print("No keys in vault. Add one with `shh keys add --provider <name> --label <name>`.")
            return
        }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .abbreviated

        for key in keys {
            let used = key.lastUsedAt.map { "used \(relative.localizedString(for: $0, relativeTo: Date()))" } ?? "unused"
            let provider = key.provider.rawValue.padding(toLength: 14, withPad: " ", startingAt: 0)
            let label = key.label.padding(toLength: 14, withPad: " ", startingAt: 0)
            print("  \(provider)\(label)[\(key.bucket.rawValue)]  ···\(key.fingerprint)  \(used)")
        }
    }
}

// MARK: - add

struct KeysAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a key to the vault. Touch ID will be required to read it back."
    )

    @Option(name: .shortAndLong, help: "Provider name (anthropic, openai, gemini, groq, or any string).")
    var provider: String

    @Option(name: .shortAndLong, help: "Human-readable label (personal, work, project-x, …).")
    var label: String

    @Option(name: .shortAndLong, help: "Accounting bucket (personal or work).")
    var bucket: String = "personal"

    @Flag(help: "Read the secret from stdin instead of prompting.")
    var stdin: Bool = false

    func run() async throws {
        guard let bucketValue = VaultKey.Bucket(rawValue: bucket.lowercased()) else {
            throw ValidationError("Bucket must be 'personal' or 'work'.")
        }
        let providerValue = VaultKey.Provider(rawValue: provider)

        let secret: String
        if stdin {
            guard let line = readLine(strippingNewline: true), !line.isEmpty else {
                throw ValidationError("No secret provided on stdin.")
            }
            secret = line
        } else {
            guard let ptr = getpass("Paste API key (hidden, press Enter when done): ") else {
                throw ValidationError("Failed to read secret from terminal.")
            }
            let typed = String(cString: ptr)
            guard !typed.isEmpty else {
                throw ValidationError("Empty secret — aborting.")
            }
            secret = typed
        }

        let vault = Vault()
        let key = try await vault.add(
            provider: providerValue,
            label: label,
            bucket: bucketValue,
            secret: secret
        )

        print("Added \(key.provider.rawValue)/\(key.label) [\(key.bucket.rawValue)] ···\(key.fingerprint)")
        print("Touch ID will be required for future reads.")
    }
}

// MARK: - remove

struct KeysRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a key from the vault.",
        aliases: ["rm"]
    )

    @Argument(help: "Key id, e.g. anthropic-personal. See `shh keys list`.")
    var id: String

    func run() async throws {
        let vault = Vault()
        try await vault.remove(id: id)
        print("Removed \(id)")
    }
}
