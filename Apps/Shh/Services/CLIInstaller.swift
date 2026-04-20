import Foundation

/// Installs (symlinks) the bundled `shh` CLI into the user's `PATH` so
/// they can run it from any terminal. Prefers `/usr/local/bin/shh` —
/// writable on Homebrew setups and the conventional Mac install path.
/// Falls back to `~/.local/bin/shh` if the user hasn't made
/// `/usr/local/bin` writable.
enum CLIInstaller {
    enum Result {
        case installed(at: URL)
        case alreadyInstalled(at: URL)
        case needsManualInstall(source: URL, suggested: [URL])
    }

    /// Path to the bundled CLI inside the running .app. Nil in unusual
    /// cases (e.g. running outside a bundle during development with the
    /// SPM executable).
    static var bundledCLI: URL? {
        let bundleURL = Bundle.main.bundleURL
        let cli = bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("shh")
        return FileManager.default.fileExists(atPath: cli.path) ? cli : nil
    }

    /// Preferred symlink targets in priority order.
    static let candidateTargets: [URL] = [
        URL(fileURLWithPath: "/usr/local/bin/shh"),
        URL(fileURLWithPath: "/opt/homebrew/bin/shh"),
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("shh"),
    ]

    static func install() throws -> Result {
        guard let source = bundledCLI else {
            throw CLIInstallError.bundledCLINotFound
        }

        for target in candidateTargets {
            // If an existing symlink points at our source, consider it done.
            if let existing = try? FileManager.default.destinationOfSymbolicLink(atPath: target.path),
               existing == source.path {
                return .alreadyInstalled(at: target)
            }

            // Ensure parent dir exists (create lazily under home dir).
            let parent = target.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: parent.path) {
                if parent.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path) {
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                } else {
                    continue
                }
            }
            guard FileManager.default.isWritableFile(atPath: parent.path) else { continue }

            try? FileManager.default.removeItem(at: target)
            try FileManager.default.createSymbolicLink(at: target, withDestinationURL: source)
            return .installed(at: target)
        }

        return .needsManualInstall(source: source, suggested: candidateTargets)
    }
}

enum CLIInstallError: Error, LocalizedError {
    case bundledCLINotFound

    var errorDescription: String? {
        switch self {
        case .bundledCLINotFound:
            return "Bundled shh CLI not found inside the app. Rebuild with scripts/build-app-dev.sh."
        }
    }
}
