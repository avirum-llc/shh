import Foundation

/// Token counting for cost estimation. v0.1 uses a byte-length heuristic
/// — the UI labels numbers as "estimated" accordingly. Upgrade path per
/// `docs/research.md` §5: TiktokenSwift (narner/TiktokenSwift) for OpenAI,
/// Anthropic `/v1/messages/count_tokens` for Claude, Gemini streaming
/// `usageMetadata` for Gemini.
public enum TokenCounter {
    /// Rough heuristic: ~4 bytes per token for English + code average.
    /// Correct within 15–25% for most payloads; acceptable for v0.1 since
    /// we surface the estimate as such.
    public static func estimate(bytes: Int) -> Int {
        max(1, (bytes + 3) / 4)
    }

    /// Peek at the first 8 KB of a JSON request body and extract the
    /// `model` field, if present. Returns nil for non-JSON or body that
    /// lacks the field.
    public static func parseModel(from body: Data) -> String? {
        let slice = body.prefix(8192)
        guard let json = try? JSONSerialization.jsonObject(with: slice, options: [.fragmentsAllowed]),
              let dict = json as? [String: Any] else {
            return nil
        }
        return dict["model"] as? String
    }

    /// Extract the model name using provider-specific conventions.
    /// Anthropic and OpenAI put `model` in the JSON body. Gemini's REST
    /// API encodes it in the URL path (`/v1beta/models/<model>:...`).
    /// Returns nil if no convention matched.
    public static func parseModel(
        provider: VaultKey.Provider,
        path: String,
        body: Data
    ) -> String? {
        if provider == .gemini, let extracted = extractGeminiModel(fromPath: path) {
            return extracted
        }
        return parseModel(from: body)
    }

    /// Pulls `<model>` out of paths like
    /// `/v1beta/models/gemini-2.5-flash:generateContent`. Tolerates a
    /// trailing query string and alternative action separators.
    static func extractGeminiModel(fromPath path: String) -> String? {
        let noQuery = path.split(separator: "?", maxSplits: 1).first.map(String.init) ?? path
        guard let range = noQuery.range(of: "/models/") else { return nil }
        let afterMarker = noQuery[range.upperBound...]
        // Model name runs until `:` (action like `:generateContent`) or `/`.
        let stopIdx = afterMarker.firstIndex(where: { $0 == ":" || $0 == "/" }) ?? afterMarker.endIndex
        let model = String(afterMarker[..<stopIdx])
        return model.isEmpty ? nil : model
    }
}
