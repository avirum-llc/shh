import Foundation

/// Per-model pricing — loaded from a bundled table, sourced from
/// `docs/research.md` §5. Keys are `<provider>:<model>` strings. Cost is
/// computed by multiplying estimated token counts by the per-million
/// rate. Real-money accuracy needs provider-billing reconciliation (out
/// of scope for v0.1 personal-key users — see research §5).
public struct PriceTable: Sendable {
    public struct ModelRates: Codable, Sendable, Hashable {
        public let inputPerMillion: Double
        public let cacheCreationPerMillion: Double?
        public let cacheReadPerMillion: Double?
        public let outputPerMillion: Double

        public init(
            inputPerMillion: Double,
            cacheCreationPerMillion: Double? = nil,
            cacheReadPerMillion: Double? = nil,
            outputPerMillion: Double
        ) {
            self.inputPerMillion = inputPerMillion
            self.cacheCreationPerMillion = cacheCreationPerMillion
            self.cacheReadPerMillion = cacheReadPerMillion
            self.outputPerMillion = outputPerMillion
        }
    }

    public let rates: [String: ModelRates]

    public init(rates: [String: ModelRates]) {
        self.rates = rates
    }

    public static let bundled: PriceTable = PriceTable(rates: [
        "anthropic:claude-opus-4-7":    .init(inputPerMillion: 15,   cacheCreationPerMillion: 18.75, cacheReadPerMillion: 1.5,    outputPerMillion: 75),
        "anthropic:claude-sonnet-4-6":  .init(inputPerMillion: 3,    cacheCreationPerMillion: 3.75,  cacheReadPerMillion: 0.3,    outputPerMillion: 15),
        "anthropic:claude-haiku-4-5":   .init(inputPerMillion: 1,    cacheCreationPerMillion: 1.25,  cacheReadPerMillion: 0.1,    outputPerMillion: 5),
        "openai:gpt-5":                 .init(inputPerMillion: 1.25,                                 cacheReadPerMillion: 0.125,  outputPerMillion: 10),
        "openai:gpt-5.5":               .init(inputPerMillion: 2,                                    cacheReadPerMillion: 0.2,    outputPerMillion: 16),
        "gemini:gemini-2.5-pro":        .init(inputPerMillion: 1.25,                                 cacheReadPerMillion: 0.3125, outputPerMillion: 10),
        "gemini:gemini-2.5-flash":      .init(inputPerMillion: 0.3,                                  cacheReadPerMillion: 0.075,  outputPerMillion: 2.5),
        "gemini:gemini-2.5-flash-lite": .init(inputPerMillion: 0.1,                                  cacheReadPerMillion: 0.025,  outputPerMillion: 0.4),
        "gemini:gemini-3-pro":          .init(inputPerMillion: 2,    cacheCreationPerMillion: 0.5,                                outputPerMillion: 12),
    ])

    public func cost(
        provider: VaultKey.Provider,
        model: String,
        inputTokens: Int,
        outputTokens: Int
    ) -> Double {
        let key = "\(provider.rawValue):\(model)"
        guard let r = rates[key] else { return 0 }
        let inCost = Double(inputTokens) * r.inputPerMillion / 1_000_000
        let outCost = Double(outputTokens) * r.outputPerMillion / 1_000_000
        return inCost + outCost
    }
}
