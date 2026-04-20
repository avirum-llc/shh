import Foundation

/// A key stored in the vault. Metadata only — the secret lives in Keychain
/// and is returned only by an explicit `Vault.read(id:)`, which triggers
/// Touch ID.
public struct VaultKey: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let provider: Provider
    public let label: String
    public let bucket: Bucket
    public let fingerprint: String
    public let createdAt: Date
    public var lastUsedAt: Date?

    public init(
        id: String,
        provider: Provider,
        label: String,
        bucket: Bucket,
        fingerprint: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.provider = provider
        self.label = label
        self.bucket = bucket
        self.fingerprint = fingerprint
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    public enum Bucket: String, Codable, Sendable, CaseIterable {
        case personal
        case work
    }

    /// Provider identifier. Tier-1 LLM providers have named constants; any
    /// other string is accepted verbatim (Tier-2/3 keys — Clerk, Stripe,
    /// GitHub, etc.).
    public struct Provider: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue.lowercased()
        }

        public init(stringLiteral value: String) {
            self.init(rawValue: value)
        }

        public static let anthropic   = Provider(rawValue: "anthropic")
        public static let openai      = Provider(rawValue: "openai")
        public static let gemini      = Provider(rawValue: "gemini")
        public static let groq        = Provider(rawValue: "groq")
        public static let mistral     = Provider(rawValue: "mistral")
        public static let cohere      = Provider(rawValue: "cohere")
        public static let together    = Provider(rawValue: "together")
        public static let perplexity  = Provider(rawValue: "perplexity")
        public static let xai         = Provider(rawValue: "xai")
        public static let replicate   = Provider(rawValue: "replicate")
        public static let huggingface = Provider(rawValue: "huggingface")

        /// Providers whose traffic shh will proxy + meter. Others are
        /// stored in the vault but not routed through the local proxy.
        public static let metered: Set<Provider> = [.anthropic, .openai, .gemini]
    }

    /// Build the canonical vault id from a provider + label.
    public static func makeID(provider: Provider, label: String) -> String {
        "\(provider.rawValue)-\(label.slugified)"
    }
}

extension String {
    /// Lowercase + space-to-dash + keep only alphanumerics, `-`, `_`.
    var slugified: String {
        let lowered = lowercased().replacingOccurrences(of: " ", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(lowered.unicodeScalars.filter { allowed.contains($0) }.map(Character.init))
    }
}
