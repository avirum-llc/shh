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

    /// Directories skipped in `.fullHome` scope. Large, machine-generated
    /// trees that don't contain user-authored secrets.
    public static let fullHomeSkipDirs: Set<String> = [
        "node_modules", ".git", ".hg", ".svn",
        ".Trash", "Trash",
        "DerivedData", ".build", "build", "dist", ".next", ".nuxt",
        "Pods", "vendor", "target", ".cargo", ".rustup",
        ".gradle", ".m2", ".nuget",
        ".venv", "venv",
        ".npm", ".yarn", ".pnpm-store", ".bun",
        "Caches", "Containers", "Logs", "CloudStorage",
        "Mobile Documents", "Messages", "Developer",
        "Photos Library.photoslibrary", "Music Library.musiclibrary",
        "Photo Booth Library",
    ]

    public struct Progress: Sendable {
        public let currentPath: String
        public let filesScanned: Int
        public let hits: Int
    }

    /// Common text-file filter used by both the curated and deep-home scans.
    /// Mirrors the files developers typically paste secrets into.
    static func isInterestingFile(name: String, suffix: String) -> Bool {
        if name.hasPrefix(".env") { return true }
        switch suffix {
        case "yml", "yaml", "json", "toml", "txt", "md": return true
        default: break
        }
        if name == "config" || name == "settings.json" { return true }
        return name.hasSuffix("rc") || name.hasSuffix("profile")
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

    /// Cancellable deep scan of the entire home directory. Skips large
    /// machine-generated trees (see `fullHomeSkipDirs`). Fires `progress`
    /// every ~200 files scanned. Throws `CancellationError` if cancelled.
    public static func scanFullHome(
        patterns: [KeyPattern] = KeyPattern.catalog,
        fileManager: FileManager = .default,
        progress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> [Detection] {
        let home = fileManager.homeDirectoryForCurrentUser
        let scanner = FileScanner(
            patterns: patterns,
            roots: [home],
            fileManager: fileManager
        )
        var results: [Detection] = []
        var filesScanned = 0
        try scanner.scanHomeDeep(
            home,
            into: &results,
            filesScanned: &filesScanned,
            progress: progress
        )
        return results
    }

    // MARK: - Private

    /// Deep recursive walk used by `scanFullHome`. Skips any directory
    /// whose last path component is in `fullHomeSkipDirs`. Periodically
    /// honours `Task.checkCancellation()` and fires the progress callback.
    private func scanHomeDeep(
        _ root: URL,
        into out: inout [Detection],
        filesScanned: inout Int,
        progress: (@Sendable (Progress) -> Void)?
    ) throws {
        // NOTE: We intentionally do NOT pass `.skipsHiddenFiles`. `.env`,
        // `.envrc`, `.zshrc`, `.aider.conf.yml` — the literal files this
        // product scans — are all hidden by Unix convention. Hidden
        // directories (`.git`, `.Trash`, etc.) are excluded by the
        // `fullHomeSkipDirs` check inside the loop.
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return }

        for case let url as URL in enumerator {
            // Cancel check every iteration — NSEnumerator is cheap to skip.
            if filesScanned % 50 == 0 {
                try Task.checkCancellation()
            }

            // Skip known-junk directories entirely.
            let name = url.lastPathComponent
            if FileScanner.fullHomeSkipDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }

            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]) else {
                continue
            }
            // Security: skip symlinks so a link pointing outside the scan root
            // (e.g., ~/link -> /etc) can't exfiltrate or scan system directories.
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            if let size = values.fileSize, size > 2_000_000 { continue }

            guard FileScanner.isInterestingFile(
                name: url.lastPathComponent,
                suffix: url.pathExtension.lowercased()
            ) else { continue }

            scanFile(url, into: &out)
            filesScanned += 1

            if filesScanned % 200 == 0 {
                progress?(Progress(
                    currentPath: url.path,
                    filesScanned: filesScanned,
                    hits: out.count
                ))
            }
        }

        // Final progress tick so the UI sees the completed count.
        progress?(Progress(
            currentPath: "",
            filesScanned: filesScanned,
            hits: out.count
        ))
    }

    private func scanDirectory(_ dir: URL, into out: inout [Detection]) {
        // Do NOT pass `.skipsHiddenFiles`: hidden files like `.env` are the
        // primary scan target. Junk hidden dirs (`.git`, `.Trash`, etc.)
        // are skipped via `fullHomeSkipDirs` below.
        guard let enumerator = fileManager.enumerator(
            at: dir,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
            options: [.skipsPackageDescendants],
            errorHandler: nil
        ) else { return }

        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            // Junk directory pruning (keeps scan bounded even without
            // `.skipsHiddenFiles`). Covers .git, .Trash, node_modules, etc.
            if FileScanner.fullHomeSkipDirs.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]) else {
                continue
            }
            if values.isSymbolicLink == true { continue }
            guard values.isRegularFile == true else { continue }
            if let size = values.fileSize, size > 2_000_000 { continue }
            guard FileScanner.isInterestingFile(
                name: name,
                suffix: url.pathExtension.lowercased()
            ) else { continue }
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
