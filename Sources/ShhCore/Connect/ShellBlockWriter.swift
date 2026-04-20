import Foundation

/// Manages a marked block of export lines inside a shell rc file. The
/// block is framed with comment markers so `disconnect` can find and
/// remove it without disturbing surrounding content.
///
///     # >>> shh-connect gemini-cli >>>
///     export GOOGLE_GEMINI_BASE_URL=http://127.0.0.1:18888
///     export GEMINI_API_KEY=shh.gemini.default.personal
///     # <<< shh-connect gemini-cli <<<
public struct ShellBlockWriter: Sendable {
    public let connectorID: String
    public let rcFile: URL

    public init(connectorID: String, rcFile: URL? = nil) {
        self.connectorID = connectorID
        self.rcFile = rcFile ?? Self.defaultRCFile()
    }

    /// Pick a rc file for the current shell. Defaults to `~/.zshrc`
    /// (zsh is macOS default). Creates the file if it doesn't exist.
    public static func defaultRCFile() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let shell = (ProcessInfo.processInfo.environment["SHELL"] ?? "").lowercased()
        if shell.contains("bash") {
            return home.appendingPathComponent(".bash_profile")
        }
        return home.appendingPathComponent(".zshrc")
    }

    private var startMarker: String { "# >>> shh-connect \(connectorID) >>>" }
    private var endMarker: String { "# <<< shh-connect \(connectorID) <<<" }

    public func isWritten() throws -> Bool {
        guard FileManager.default.fileExists(atPath: rcFile.path) else { return false }
        let content = try String(contentsOf: rcFile, encoding: .utf8)
        return content.contains(startMarker) && content.contains(endMarker)
    }

    public func write(envVars: [(String, String)]) throws {
        let block = buildBlock(envVars: envVars)

        var existing = ""
        if FileManager.default.fileExists(atPath: rcFile.path) {
            existing = (try? String(contentsOf: rcFile, encoding: .utf8)) ?? ""
        }

        let updated = removeExistingBlock(from: existing) + (existing.hasSuffix("\n") || existing.isEmpty ? "" : "\n") + block + "\n"
        try updated.data(using: .utf8)!.write(to: rcFile, options: [.atomic])
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: rcFile.path) else { return }
        let existing = try String(contentsOf: rcFile, encoding: .utf8)
        let updated = removeExistingBlock(from: existing)
        try updated.data(using: .utf8)!.write(to: rcFile, options: [.atomic])
    }

    public func previewText(envVars: [(String, String)]) -> String {
        buildBlock(envVars: envVars)
    }

    // MARK: - Private

    private func buildBlock(envVars: [(String, String)]) -> String {
        var lines = [startMarker]
        for (name, value) in envVars {
            lines.append("export \(name)=\(shellEscape(value))")
        }
        lines.append(endMarker)
        return lines.joined(separator: "\n")
    }

    private func removeExistingBlock(from text: String) -> String {
        guard let startRange = text.range(of: startMarker),
              let endRange = text.range(of: endMarker, range: startRange.upperBound..<text.endIndex) else {
            return text
        }
        // Include the newline before/after the block where possible
        var lower = startRange.lowerBound
        if lower > text.startIndex, text[text.index(before: lower)] == "\n" {
            lower = text.index(before: lower)
        }
        var upper = endRange.upperBound
        if upper < text.endIndex, text[upper] == "\n" {
            upper = text.index(after: upper)
        }
        return String(text[text.startIndex..<lower]) + String(text[upper..<text.endIndex])
    }

    private func shellEscape(_ value: String) -> String {
        // Simple single-quote escaping — adequate for our dummy tokens
        // and URLs, both of which are ASCII-safe.
        let escaped = value.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
