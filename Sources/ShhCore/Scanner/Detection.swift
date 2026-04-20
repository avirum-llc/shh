import Foundation

/// A single key found by the scanner. The `key` is the extracted secret
/// (never logged or serialised to disk as-is — migration moves it to the
/// vault and rewrites the source).
public struct Detection: Sendable, Hashable, Identifiable {
    public var id: String { "\(sourcePath):\(lineNumber):\(range.lowerBound)" }
    public let sourcePath: URL
    public let lineNumber: Int
    public let line: String
    public let range: Range<Int>
    public let key: String
    public let provider: VaultKey.Provider
    public let tier: Int
    public let envHintMatched: String?
    public let confidence: Confidence

    public enum Confidence: String, Sendable, Codable, Hashable {
        case high      // prefix-distinct regex match (Anthropic, Groq, etc.)
        case mediumHint  // generic regex + env-hint context matched
        case low       // regex matched but no env-hint context
    }

    /// Last 4 characters, for UI display without leaking the full secret.
    public var fingerprint: String { String(key.suffix(4)) }

    /// Proposed label for the vault entry, based on the file we found it in.
    /// E.g. `~/.zshrc` -> `zshrc`, `~/Documents/proj/.env` -> `proj`.
    public var suggestedLabel: String {
        let filename = sourcePath.lastPathComponent
        if filename.hasPrefix(".") {
            // .env -> folder name
            return sourcePath.deletingLastPathComponent().lastPathComponent.slugified
        }
        return filename.replacingOccurrences(of: ".", with: "_").slugified
    }
}
