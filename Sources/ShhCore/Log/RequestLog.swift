import Foundation

/// Newline-delimited JSON log of proxy requests. Each record is one line
/// in `~/Library/Application Support/shh/requests.ndjson`. Append-only
/// writes (one `open → seekToEnd → write → close` per request), lightweight
/// reads (parse the whole file into memory — fine for v0.1 volumes).
/// Upgrade to GRDB/SQLite when retention or query complexity justifies it.
public actor RequestLog {
    public static let defaultPath: URL = {
        let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return support
            .appendingPathComponent("shh", isDirectory: true)
            .appendingPathComponent("requests.ndjson")
    }()

    public let path: URL

    public init(path: URL = RequestLog.defaultPath) {
        self.path = path
    }

    public func append(_ record: RequestRecord) throws {
        try FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(record)
        data.append(0x0A)  // \n

        if FileManager.default.fileExists(atPath: path.path) {
            let handle = try FileHandle(forWritingTo: path)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: path, options: .atomic)
        }
    }

    public func all() throws -> [RequestRecord] {
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let data = try Data(contentsOf: path)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var records: [RequestRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let lineData = String(line).data(using: .utf8),
                  let record = try? decoder.decode(RequestRecord.self, from: lineData) else {
                continue
            }
            records.append(record)
        }
        return records
    }

    public func since(_ date: Date) throws -> [RequestRecord] {
        try all().filter { $0.timestamp >= date }
    }
}
