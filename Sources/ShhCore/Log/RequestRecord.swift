import Foundation

/// One row of the request log — recorded after the proxy forwards a
/// request to the upstream provider. Everything is persisted to
/// `requests.ndjson`; the dashboard reads from the same file.
public struct RequestRecord: Codable, Sendable, Identifiable, Hashable {
    public let id: UUID
    public let timestamp: Date
    public let provider: VaultKey.Provider
    public let keyID: String
    public let projectTag: String
    public let model: String?
    public let inputBytes: Int
    public let outputBytes: Int
    public let inputTokensEstimated: Int
    public let outputTokensEstimated: Int
    public let costUSDEstimated: Double
    public let durationMs: Int
    public let status: Int

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        provider: VaultKey.Provider,
        keyID: String,
        projectTag: String,
        model: String?,
        inputBytes: Int,
        outputBytes: Int,
        inputTokensEstimated: Int,
        outputTokensEstimated: Int,
        costUSDEstimated: Double,
        durationMs: Int,
        status: Int
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.keyID = keyID
        self.projectTag = projectTag
        self.model = model
        self.inputBytes = inputBytes
        self.outputBytes = outputBytes
        self.inputTokensEstimated = inputTokensEstimated
        self.outputTokensEstimated = outputTokensEstimated
        self.costUSDEstimated = costUSDEstimated
        self.durationMs = durationMs
        self.status = status
    }
}
