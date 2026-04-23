import Foundation
import LocalAuthentication
import Security

/// A single generic-password entry found in the login Keychain that
/// *looks like* an API key — based on service/account heuristics. No
/// secret data has been read yet (enumeration uses `kSecReturnAttributes`
/// only, which does not trigger Touch ID or auth prompts). The secret is
/// fetched on-demand by `KeychainScanner.readSecret(hit:reason:)`.
public struct KeychainHit: Sendable, Hashable, Identifiable {
    public var id: String { "kc:\(service)|\(account)" }
    public let service: String
    public let account: String
    public let label: String?
    public let provider: VaultKey.Provider
    public let confidence: Detection.Confidence
    public let modifiedAt: Date?

    /// Suggested vault label — service-first, falling back to account.
    public var suggestedLabel: String {
        let base = service.isEmpty ? account : service
        return base.slugified
    }
}

/// Enumerates API-key-shaped entries in the macOS login Keychain.
///
/// Two separate operations:
///
/// - `scan()` — lists matching entries with *attributes only*. No secret
///   reads, no biometric / password prompts. Uses service + account name
///   heuristics (see `classify`) to filter out unrelated entries like
///   Wi-Fi, Safari forms, iCloud tokens, etc.
///
/// - `readSecret(hit:reason:)` — fetches the actual secret for one entry.
///   This triggers the standard Keychain auth prompt once per entry, and
///   the user can deny it.
public struct KeychainScanner: Sendable {
    public init() {}

    public func scan() throws -> [KeychainHit] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            return []
        default:
            throw KeychainError.unhandledStatus(status)
        }
        guard let items = result as? [[String: Any]] else { return [] }

        var hits: [KeychainHit] = []
        for item in items {
            let service = (item[kSecAttrService as String] as? String) ?? ""
            let account = (item[kSecAttrAccount as String] as? String) ?? ""
            let label = item[kSecAttrLabel as String] as? String
            let modified = item[kSecAttrModificationDate as String] as? Date

            // Skip shh's own vault entries — the user already has those.
            if service == "com.avirumapps.shh" { continue }

            guard let classified = Self.classify(service: service, account: account, label: label) else {
                continue
            }
            hits.append(KeychainHit(
                service: service,
                account: account,
                label: label,
                provider: classified.provider,
                confidence: classified.confidence,
                modifiedAt: modified
            ))
        }
        return hits
    }

    /// Fetch the actual secret for a single hit. Triggers the system auth
    /// prompt; the user can cancel. Throws `KeychainError.userCancelled`
    /// on cancel or `.itemNotFound` if the entry has since been removed.
    public func readSecret(hit: KeychainHit, reason: String = "shh is importing a key from your Keychain") throws -> String {
        let context = LAContext()
        context.localizedReason = reason
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: hit.service,
            kSecAttrAccount as String: hit.account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.dataConversionFailed
            }
            return secret
        case errSecItemNotFound:
            throw KeychainError.itemNotFound
        case errSecUserCanceled:
            throw KeychainError.userCancelled
        case errSecAuthFailed:
            throw KeychainError.authenticationFailed
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    // MARK: - Classification

    struct Classification {
        let provider: VaultKey.Provider
        let confidence: Detection.Confidence
    }

    /// Infer a provider (and confidence) for a Keychain entry, or return
    /// nil if it doesn't look like an API key we care about.
    ///
    /// - `.high` — service/account contains a distinctive provider name.
    /// - `.mediumHint` — account equals a canonical env-var name like
    ///   `ANTHROPIC_API_KEY` or `OPENAI_API_KEY`.
    /// - `.low` — service or account contains a generic `api_key` / `token`
    ///   string. Surfaced so the user can decide; easy to ignore in the UI.
    static func classify(service: String, account: String, label: String?) -> Classification? {
        let haystack = [service, account, label ?? ""]
            .joined(separator: " ")
            .lowercased()

        // System / Apple-shipped entries we never want to surface.
        let noisePrefixes = [
            "com.apple.", "apple ", "airport", "wifi", "wi-fi",
            "icloud", "safari", "imessage", "facetime",
            "accountsd", "ids:", "authkit", "cloudkit",
            "mdm", "aps", "ak-",
        ]
        if noisePrefixes.contains(where: { haystack.hasPrefix($0) || haystack.contains(" " + $0) }) {
            return nil
        }

        // Provider-distinctive strings (.high confidence).
        let highSignals: [(needle: String, provider: VaultKey.Provider)] = [
            ("anthropic", .anthropic),
            ("sk-ant", .anthropic),
            ("claude", .anthropic),
            ("openai", .openai),
            ("sk-proj", .openai),
            ("sk-svcacct", .openai),
            ("gemini", .gemini),
            ("google_genai", .gemini),
            ("generativeai", .gemini),
            ("aistudio", .gemini),
            ("groq", .groq),
            ("perplexity", .perplexity),
            ("mistral", .mistral),
            ("cohere", .cohere),
            ("together", .together),
            ("huggingface", .huggingface),
            ("replicate", .replicate),
            ("xai", .xai),
            ("stripe", "stripe"),
            ("clerk", "clerk"),
            ("resend", "resend"),
            ("posthog", "posthog"),
            ("github_pat", "github"),
            ("ghp_", "github"),
            ("npm_token", "npm"),
        ]
        for signal in highSignals where haystack.contains(signal.needle) {
            return Classification(provider: signal.provider, confidence: .high)
        }

        // Env-var shaped accounts — medium confidence.
        let envVarSignals: [(needle: String, provider: VaultKey.Provider)] = [
            ("anthropic_api_key", .anthropic),
            ("anthropic_auth_token", .anthropic),
            ("openai_api_key", .openai),
            ("gemini_api_key", .gemini),
            ("google_api_key", .gemini),
            ("groq_api_key", .groq),
            ("hf_token", .huggingface),
            ("perplexity_api_key", .perplexity),
            ("xai_api_key", .xai),
        ]
        for signal in envVarSignals where haystack.contains(signal.needle) {
            return Classification(provider: signal.provider, confidence: .mediumHint)
        }

        // Generic "API key" shape — surface as low confidence.
        let genericNeedles = ["api_key", "api-key", "apikey", "api key", "secret_key", "access_token"]
        if genericNeedles.contains(where: { haystack.contains($0) }) {
            return Classification(provider: "generic", confidence: .low)
        }

        return nil
    }
}
