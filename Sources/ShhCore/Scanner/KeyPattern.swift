import Foundation

/// A single scanner rule: a provider identifier, a regex to extract
/// candidate keys, and a set of env-var / config-key names that — when
/// seen on the same or a nearby line — raise confidence that the match
/// really is a key of this provider (two-signal classifier).
public struct KeyPattern: Sendable, Hashable {
    public let provider: VaultKey.Provider
    public let regex: String
    public let envHints: [String]
    public let tier: Int   // 1 = LLM provider (proxied), 2 = paid service, 3 = broader secret

    public init(
        provider: VaultKey.Provider,
        regex: String,
        envHints: [String],
        tier: Int
    ) {
        self.provider = provider
        self.regex = regex
        self.envHints = envHints
        self.tier = tier
    }

    /// Canonical catalog. Sourced from `docs/research.md` §2.
    ///
    /// Patterns are ordered by prefix specificity — the scanner returns
    /// the first match per line, so more specific patterns (e.g.
    /// `sk-ant-`, `sk-proj-`) should precede looser ones.
    public static let catalog: [KeyPattern] = [
        // Tier 1 — LLM providers
        KeyPattern(
            provider: .anthropic,
            regex: #"sk-ant-(?:api|admin)\d{2}-[A-Za-z0-9_\-]{80,180}"#,
            envHints: ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_"],
            tier: 1
        ),
        KeyPattern(
            provider: .openai,
            regex: #"sk-(?:proj|svcacct|admin)-[A-Za-z0-9_\-]{20,200}"#,
            envHints: ["OPENAI_API_KEY", "OPENAI_"],
            tier: 1
        ),
        // OpenAI legacy form `sk-<48 chars>` — set lower priority because
        // it can collide with other `sk-` prefixed tokens.
        KeyPattern(
            provider: .openai,
            regex: #"\bsk-[A-Za-z0-9]{48}\b"#,
            envHints: ["OPENAI_API_KEY", "OPENAI_"],
            tier: 1
        ),
        KeyPattern(
            provider: .gemini,
            regex: #"\bAIza[0-9A-Za-z_\-]{35}\b"#,
            envHints: ["GEMINI_API_KEY", "GOOGLE_API_KEY", "GOOGLE_GEMINI_"],
            tier: 1
        ),
        KeyPattern(
            provider: .groq,
            regex: #"\bgsk_[A-Za-z0-9]{52}\b"#,
            envHints: ["GROQ_API_KEY"],
            tier: 1
        ),
        KeyPattern(
            provider: .replicate,
            regex: #"\br8_[A-Za-z0-9]{37,40}\b"#,
            envHints: ["REPLICATE_API_TOKEN"],
            tier: 1
        ),
        KeyPattern(
            provider: .huggingface,
            regex: #"\bhf_[A-Za-z0-9]{34,40}\b"#,
            envHints: ["HF_TOKEN", "HUGGINGFACE_"],
            tier: 1
        ),
        KeyPattern(
            provider: .perplexity,
            regex: #"\bpplx-[A-Za-z0-9]{48,56}\b"#,
            envHints: ["PERPLEXITY_API_KEY"],
            tier: 1
        ),
        KeyPattern(
            provider: .xai,
            regex: #"\bxai-[A-Za-z0-9]{80}\b"#,
            envHints: ["XAI_API_KEY"],
            tier: 1
        ),

        // Tier 2 — paid services (stored only, no proxy)
        KeyPattern(
            provider: "stripe",
            regex: #"\bsk_(?:live|test)_[A-Za-z0-9]{99,}\b"#,
            envHints: ["STRIPE_SECRET_KEY", "STRIPE_"],
            tier: 2
        ),
        KeyPattern(
            provider: "clerk",
            regex: #"\bsk_(?:live|test)_[A-Za-z0-9]{40,98}\b"#,
            envHints: ["CLERK_SECRET_KEY", "CLERK_"],
            tier: 2
        ),
        KeyPattern(
            provider: "resend",
            regex: #"\bre_[A-Za-z0-9_]{20,40}\b"#,
            envHints: ["RESEND_API_KEY"],
            tier: 2
        ),
        KeyPattern(
            provider: "posthog",
            regex: #"\bphx_[A-Za-z0-9]{40,50}\b"#,
            envHints: ["POSTHOG_PERSONAL_API_KEY", "POSTHOG_"],
            tier: 2
        ),

        // Tier 3 — broader secrets
        KeyPattern(
            provider: "github",
            regex: #"\bgh[pousr]_[A-Za-z0-9]{36}\b"#,
            envHints: ["GITHUB_TOKEN", "GH_TOKEN"],
            tier: 3
        ),
        KeyPattern(
            provider: "github",
            regex: #"\bgithub_pat_[A-Za-z0-9_]{82}\b"#,
            envHints: ["GITHUB_TOKEN", "GH_TOKEN"],
            tier: 3
        ),
        KeyPattern(
            provider: "aws",
            regex: #"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"#,
            envHints: ["AWS_ACCESS_KEY_ID", "AWS_"],
            tier: 3
        ),
        KeyPattern(
            provider: "npm",
            regex: #"\bnpm_[A-Za-z0-9]{36}\b"#,
            envHints: ["NPM_TOKEN"],
            tier: 3
        ),
    ]

    /// Compile the regex once; force-unwrap is safe because the catalog is
    /// static and any failure would be a programmer error caught in tests.
    public func compiledRegex() -> NSRegularExpression {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: regex, options: [])
    }
}
