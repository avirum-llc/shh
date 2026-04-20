import Foundation

/// Walks a set of filesystem locations and yields `Detection`s for any
/// API keys it finds. Uses a two-signal classifier: regex match + env-var
/// name context from the same line. Regex-only matches are reported with
/// low confidence for undocumented formats (like OpenAI legacy `sk-`) and
/// are worth showing the user but may need manual verification.
public struct FileScanner: Sendable {
    public let patterns: [KeyPattern]
    public let roots: [URL]
    public let fileManager: FileManager

    public init(
        patterns: [KeyPattern] = KeyPattern.catalog,
        roots: [URL]? = nil,
        fileManager: FileManager = .default
    ) {
        self.patterns = patterns
        self.roots = roots ?? FileScanner.defaultRoots(fileManager: fileManager)
        self.fileManager = fileManager
    }

    public static func defaultRoots(fileManager: FileManager = .default) -> [URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        let shellConfigs: [String] = [
            ".zshrc", ".zprofile", ".bash_profile", ".bashrc", ".profile",
            ".config/fish/config.fish", ".env",
        ]
        let configDirs: [String] = [
            ".claude", ".codex", ".aider.conf.yml", ".config/opencode", ".gemini",
        ]
        let documentsRoots = [
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("code"),
            home.appendingPathComponent("Projects"),
        ].filter { fileManager.fileExists(atPath: $0.path) }
        return shellConfigs.map { home.appendingPathComponent($0) }
            + configDirs.map { home.appendingPathComponent($0) }
            + documentsRoots
    }

    /// Scan all roots and return detections. Low-confidence matches for
    /// undocumented formats are included — the caller decides whether to
    /// show them.
    public func scan() -> [Detection] {
        var results: [Detection] = []
        for root in roots {
            guard fileManager.fileExists(atPath: root.path) else { continue }
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                scanDirectory(root, into: &results)
            } else {
                scanFile(root, into: &results)
            }
        }
        return results
    }

    // MARK: - Private

    private func scanDirectory(_ dir: URL, into out: inout [Detection]) {
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return }

        for case let url as URL in enumerator {
            // Skip huge files and non-regular files.
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]) {
                guard values.isRegularFile == true else { continue }
                if let size = values.fileSize, size > 2_000_000 { continue }
            }
            // Only scan likely-textual files.
            let name = url.lastPathComponent
            let suffix = url.pathExtension.lowercased()
            let interesting = name.hasPrefix(".env")
                || name == ".env"
                || suffix == "yml" || suffix == "yaml"
                || suffix == "json" || suffix == "toml"
                || suffix == "txt" || suffix == "md"
                || name == "config" || name == "settings.json"
                || name.hasSuffix("rc") || name.hasSuffix("profile")
            guard interesting else { continue }
            scanFile(url, into: &out)
        }
    }

    private func scanFile(_ url: URL, into out: inout [Detection]) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return }

        let lines = text.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            for pattern in patterns {
                let ns = line as NSString
                let regex = pattern.compiledRegex()
                let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: ns.length))
                for m in matches {
                    guard m.range.location != NSNotFound,
                          let range = Range(m.range, in: line) else { continue }
                    let key = String(line[range])

                    // Two-signal classification
                    let hintMatched = pattern.envHints.first { hint in
                        line.range(of: hint, options: .caseInsensitive) != nil
                    }
                    let confidence: Detection.Confidence = {
                        // Prefix-specific patterns are inherently high-confidence.
                        if key.hasPrefix("sk-ant-") || key.hasPrefix("sk-proj-")
                            || key.hasPrefix("sk-svcacct-") || key.hasPrefix("sk-admin-")
                            || key.hasPrefix("AIza") || key.hasPrefix("gsk_")
                            || key.hasPrefix("r8_") || key.hasPrefix("hf_")
                            || key.hasPrefix("pplx-") || key.hasPrefix("xai-")
                            || key.hasPrefix("re_") || key.hasPrefix("phx_")
                            || key.hasPrefix("ghp_") || key.hasPrefix("github_pat_")
                            || key.hasPrefix("AKIA") || key.hasPrefix("ASIA")
                            || key.hasPrefix("npm_") {
                            return .high
                        }
                        return hintMatched != nil ? .mediumHint : .low
                    }()

                    // Convert NSRange.location to a Swift Int range in the line.
                    let intRange = m.range.location..<(m.range.location + m.range.length)

                    out.append(Detection(
                        sourcePath: url,
                        lineNumber: idx + 1,
                        line: line,
                        range: intRange,
                        key: key,
                        provider: pattern.provider,
                        tier: pattern.tier,
                        envHintMatched: hintMatched,
                        confidence: confidence
                    ))
                }
            }
        }
    }
}
