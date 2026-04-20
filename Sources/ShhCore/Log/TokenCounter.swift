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
}
