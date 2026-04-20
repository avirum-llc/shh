import Foundation

/// Parsed HTTP/1.1 request.
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]  // keys lowercased
    public let body: Data

    /// Return the bearer token from the Authorization header, if present.
    public var authToken: String? {
        guard let value = headers["authorization"] else { return nil }
        if value.hasPrefix("Bearer ") { return String(value.dropFirst("Bearer ".count)) }
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
