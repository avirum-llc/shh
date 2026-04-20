import Foundation
import Network

public enum ProxyError: Error, LocalizedError, Equatable {
    case incompleteRequest
    case requestTooLarge
    case badRequest(String)
    case missingAuth
    case malformedDummyToken(String)
    case unsupportedProvider(String)

    public var errorDescription: String? {
        switch self {
        case .incompleteRequest:           return "Connection closed before the request finished"
        case .requestTooLarge:             return "Request exceeded 20 MB"
        case .badRequest(let m):           return "Malformed HTTP request: \(m)"
        case .missingAuth:                 return "Missing Authorization header"
        case .malformedDummyToken(let t):  return "Malformed shh token: \(t)"
        case .unsupportedProvider(let p):  return "No upstream configured for provider '\(p)'"
        }
    }
}

/// Local HTTP proxy on 127.0.0.1. Listens, parses HTTP/1.1 requests,
/// swaps the dummy bearer token for the real Keychain key, forwards to
/// the upstream provider via URLSession, and logs a `RequestRecord` to
/// the newline-delimited JSON request log. v0.1 buffers the response
/// (does not stream); that polish is noted in BUILD_LOG for a v0.2 pass.
public actor ProxyServer {
    public static let defaultPort: UInt16 = 18888

    public nonisolated let port: UInt16
    public private(set) var isRunning = false

    private let vault: Vault
    private let log: RequestLog
    private let priceTable: PriceTable
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.avirumapps.shh.proxy")
    private let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        return URLSession(configuration: config)
    }()

    public init(
        vault: Vault,
        log: RequestLog = RequestLog(),
        priceTable: PriceTable = .bundled,
        port: UInt16 = ProxyServer.defaultPort
    ) {
        self.vault = vault
        self.log = log
        self.priceTable = priceTable
        self.port = port
    }

    public func start() throws {
        guard !isRunning else { return }
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(
            using: params,
            on: NWEndpoint.Port(rawValue: port)!
        )
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            Task { await self.accept(connection) }
        }
        listener.start(queue: queue)
        self.listener = listener
        self.isRunning = true
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    // MARK: - Per-connection

    private func accept(_ connection: NWConnection) async {
        connection.start(queue: queue)
        defer { connection.cancel() }

        let started = Date()
        do {
            let request = try await readRequest(from: connection)

            // Handle a health-check ping without a real forward, so the
            // CLI and GUI can detect liveness without needing a key.
            if request.path.hasPrefix("/__shh_ping__") {
                try await respondPing(on: connection)
                return
            }

            let (record, response) = try await fulfill(request: request, startedAt: started)
            try await respond(response, on: connection)
            try await log.append(record)
        } catch {
            try? await respondError(error, on: connection)
        }
    }

    // MARK: - Request parsing

    private func readRequest(from connection: NWConnection) async throws -> HTTPRequest {
        var buffer = Data()
        var method = ""
        var path = ""
        var headers: [String: String] = [:]
        var haveHeaders = false
        var contentLength = 0

        while true {
            let chunk = try await connection.receiveAsync(min: 1, max: 65536)
            if chunk.isEmpty {
                if haveHeaders, buffer.count >= contentLength {
                    return HTTPRequest(method: method, path: path, headers: headers, body: buffer.prefix(contentLength))
                }
                throw ProxyError.incompleteRequest
            }
            buffer.append(chunk)

            if !haveHeaders, let boundary = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: 0..<boundary.lowerBound)
                (method, path, headers) = try parseHead(headerData)
                contentLength = Int(headers["content-length"] ?? "0") ?? 0
                buffer = buffer.subdata(in: boundary.upperBound..<buffer.count)
                haveHeaders = true
            }

            if haveHeaders, buffer.count >= contentLength {
                return HTTPRequest(method: method, path: path, headers: headers, body: buffer.prefix(contentLength))
            }

            if buffer.count > 20_000_000 {
                throw ProxyError.requestTooLarge
            }
        }
    }

    private func parseHead(_ data: Data) throws -> (String, String, [String: String]) {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProxyError.badRequest("headers not UTF-8")
        }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw ProxyError.badRequest("empty request")
        }
        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            throw ProxyError.badRequest("malformed request line")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
                let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                headers[name] = value
            }
        }
        return (String(parts[0]), String(parts[1]), headers)
    }

    // MARK: - Forward

    private func fulfill(request: HTTPRequest, startedAt: Date) async throws -> (RequestRecord, HTTPResponse) {
        guard let token = request.authToken else { throw ProxyError.missingAuth }
        let dummy = try DummyToken.parse(token)

        let keyID = VaultKey.makeID(provider: dummy.provider, label: dummy.keyLabel)
        let realKey = try await vault.read(
            id: keyID,
            reason: "Claude Code / \(dummy.project) wants to use your \(dummy.provider.rawValue) key"
        )

        guard let upstreamURL = UpstreamRouter.upstream(for: dummy.provider, path: request.path) else {
            throw ProxyError.unsupportedProvider(dummy.provider.rawValue)
        }

        var upstreamRequest = URLRequest(url: upstreamURL)
        upstreamRequest.httpMethod = request.method
        upstreamRequest.httpBody = request.body.isEmpty ? nil : request.body
        let skipHeaders: Set<String> = [
            "host", "authorization", "x-api-key",
            "content-length", "connection", "accept-encoding",
        ]
        for (name, value) in request.headers where !skipHeaders.contains(name) {
            upstreamRequest.setValue(value, forHTTPHeaderField: name)
        }
        UpstreamRouter.applyCredentials(to: &upstreamRequest, provider: dummy.provider, realKey: realKey)

        let (bodyData, urlResponse) = try await session.data(for: upstreamRequest)
        guard let http = urlResponse as? HTTPURLResponse else {
            throw ProxyError.badRequest("upstream response had no status")
        }

        var responseHeaders: [String: String] = [:]
        for (k, v) in http.allHeaderFields {
            if let ks = k as? String, let vs = v as? String {
                responseHeaders[ks.lowercased()] = vs
            }
        }
        let response = HTTPResponse(status: http.statusCode, headers: responseHeaders, body: bodyData)

        let inputBytes = request.body.count
        let outputBytes = bodyData.count
        let inputTokens = TokenCounter.estimate(bytes: inputBytes)
        let outputTokens = TokenCounter.estimate(bytes: outputBytes)
        let model = TokenCounter.parseModel(from: request.body)
        let costUSD = model.map {
            priceTable.cost(
                provider: dummy.provider,
                model: $0,
                inputTokens: inputTokens,
                outputTokens: outputTokens
            )
        } ?? 0
        let duration = Int(Date().timeIntervalSince(startedAt) * 1000)

        let record = RequestRecord(
            timestamp: startedAt,
            provider: dummy.provider,
            keyID: keyID,
            projectTag: dummy.project,
            model: model,
            inputBytes: inputBytes,
            outputBytes: outputBytes,
            inputTokensEstimated: inputTokens,
            outputTokensEstimated: outputTokens,
            costUSDEstimated: costUSD,
            durationMs: duration,
            status: http.statusCode
        )
        return (record, response)
    }

    // MARK: - Respond

    private func respond(_ response: HTTPResponse, on connection: NWConnection) async throws {
        var headers = response.headers
        headers["content-length"] = "\(response.body.count)"
        headers["connection"] = "close"
        headers.removeValue(forKey: "transfer-encoding")  // we buffered the full body

        var head = "HTTP/1.1 \(response.status) \(statusText(for: response.status))\r\n"
        for (k, v) in headers.sorted(by: { $0.key < $1.key }) {
            head += "\(k): \(v)\r\n"
        }
        head += "\r\n"

        try await connection.sendAsync(Data(head.utf8))
        try await connection.sendAsync(response.body, isComplete: true)
    }

    private func respondPing(on connection: NWConnection) async throws {
        let body = Data(#"{"shh":"alive"}"#.utf8)
        let head = "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\ncontent-length: \(body.count)\r\nconnection: close\r\n\r\n"
        try await connection.sendAsync(Data(head.utf8))
        try await connection.sendAsync(body, isComplete: true)
    }

    private func respondError(_ error: Error, on connection: NWConnection) async throws {
        let message = error.localizedDescription
            .replacingOccurrences(of: "\"", with: "\\\"")
        let body = Data(#"{"error":"\#(message)"}"#.utf8)
        let head = "HTTP/1.1 502 Bad Gateway\r\ncontent-type: application/json\r\ncontent-length: \(body.count)\r\nconnection: close\r\n\r\n"
        try await connection.sendAsync(Data(head.utf8))
        try await connection.sendAsync(body, isComplete: true)
    }

    private func statusText(for code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 429: return "Too Many Requests"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        default:  return "Status"
        }
    }
}
