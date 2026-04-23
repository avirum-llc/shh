import Foundation

/// Parsed HTTP/1.1 request.
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]  // keys lowercased
    public let body: Data

    /// Return the shh dummy token from wherever the client put it.
    /// Providers auth differently:
    ///   - Anthropic: `x-api-key: <key>`
    ///   - Google Gemini: `?key=<key>` query or `x-goog-api-key: <key>`
    ///   - Everyone else: `Authorization: Bearer <key>`
    /// The proxy accepts any of these as long as the value starts with
    /// `shh.` (our dummy prefix). Real upstream keys never start with
    /// `shh.` so this is unambiguous.
    public var authToken: String? {
        if let value = headers["authorization"], value.hasPrefix("Bearer ") {
            let token = String(value.dropFirst("Bearer ".count))
            if token.hasPrefix("shh.") { return token }
        }
        if let value = headers["x-api-key"], value.hasPrefix("shh.") {
            return value
        }
        if let value = headers["x-goog-api-key"], value.hasPrefix("shh.") {
            return value
        }
        // Query-string `?key=shh.xxx` — Gemini REST default.
        if let queryStart = path.firstIndex(of: "?") {
            let query = path[path.index(after: queryStart)...]
            for pair in query.split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1)
                guard kv.count == 2, kv[0] == "key" else { continue }
                // Fail-closed: if percent-decoding fails, skip rather than
                // falling back to the raw encoded value (which would silently
                // fail the shh. prefix check and confuse the reader).
                guard let value = String(kv[1]).removingPercentEncoding else { continue }
                if value.hasPrefix("shh.") { return value }
            }
        }
        return nil
    }
}

/// HTTP response as the proxy buffers it from upstream before returning
/// to the caller. v0.1 buffers fully; a future pass will stream.
public struct HTTPResponse: Sendable {
    public let status: Int
    public let headers: [String: String]  // keys lowercased
    public let body: Data
}

/// Format: `shh.<provider>.<project>.<key-label>`. Uses `.` rather than
/// `-` to avoid collisions with hyphens inside provider names or slugs.
/// The full dummy token is what the CLI sees in its `*_BASE_URL` /
/// `*_AUTH_TOKEN` environment — useless outside the proxy.
public struct DummyToken: Sendable, Hashable {
    public let provider: VaultKey.Provider
    public let project: String
    public let keyLabel: String

    public init(provider: VaultKey.Provider, project: String, keyLabel: String) {
        self.provider = provider
        self.project = project
        self.keyLabel = keyLabel
    }

    public var token: String {
        "shh.\(provider.rawValue).\(project).\(keyLabel)"
    }

    public static func parse(_ raw: String) throws -> DummyToken {
        guard raw.hasPrefix("shh.") else { throw ProxyError.malformedDummyToken(raw) }
        let rest = raw.dropFirst("shh.".count)
        let parts = rest.split(separator: ".", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty }) else {
            throw ProxyError.malformedDummyToken(raw)
        }
        return DummyToken(
            provider: VaultKey.Provider(rawValue: parts[0]),
            project: parts[1],
            keyLabel: parts[2]
        )
    }
}
