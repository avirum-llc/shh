import Foundation

/// Provider → upstream URL + auth header mapping.
public enum UpstreamRouter {
    /// Map (provider, path) to the upstream URL. Returns nil for
    /// unsupported providers.
    public static func upstream(for provider: VaultKey.Provider, path: String) -> URL? {
        let base: String?
        switch provider.rawValue {
        case "anthropic":  base = "https://api.anthropic.com"
        case "openai":     base = "https://api.openai.com"
        case "gemini":     base = "https://generativelanguage.googleapis.com"
        case "groq":       base = "https://api.groq.com"
        case "mistral":    base = "https://api.mistral.ai"
        case "cohere":     base = "https://api.cohere.com"
        case "together":   base = "https://api.together.xyz"
        case "perplexity": base = "https://api.perplexity.ai"
        case "xai":        base = "https://api.x.ai"
        default:           base = nil
        }
        guard let base else { return nil }
        return URL(string: base + path)
    }

    /// Attach upstream credentials to a URLRequest in the format the
    /// provider expects. Anthropic uses `x-api-key`; Gemini uses a `key`
    /// query parameter; everyone else uses `Authorization: Bearer`.
    public static func applyCredentials(
        to request: inout URLRequest,
        provider: VaultKey.Provider,
        realKey: String
    ) {
        request.setValue(nil, forHTTPHeaderField: "Authorization")
        request.setValue(nil, forHTTPHeaderField: "x-api-key")

        switch provider.rawValue {
        case "anthropic":
            request.setValue(realKey, forHTTPHeaderField: "x-api-key")
        case "gemini":
            if let url = request.url,
               var components = URLComponents(url: url, resolvingAgainstBaseURL: true) {
                var items = components.queryItems ?? []
                items.removeAll { $0.name == "key" }
                items.append(URLQueryItem(name: "key", value: realKey))
                components.queryItems = items
                request.url = components.url
            }
        default:
            request.setValue("Bearer \(realKey)", forHTTPHeaderField: "Authorization")
        }
    }
}
