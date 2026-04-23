import SwiftUI
import ShhCore

/// Modal sheet that walks the entire home directory and the login
/// Keychain for API keys. Presented from `ScannerWindow` when the user
/// clicks "Deep scan…".
struct DeepScanSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .intro
    @State private var fileDetections: [Detection] = []
    @State private var keychainHits: [KeychainHit] = []
    @State private var selectedFiles: Set<Detection.ID> = []
    @State private var selectedKeychain: Set<KeychainHit.ID> = []
    @State private var progress: FileScanner.Progress?
    @State private var keychainScanFailed: String?
    @State private var errorMessage: String?
    @State private var migrationStatus: String?
    @State private var bucket: VaultKey.Bucket = .personal
    @State private var scanTask: Task<Void, Never>?
    @State private var migrating = false

    enum Phase {
        case intro
        case scanning
        case results
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 14)

            Divider()

            Group {
                switch phase {
                case .intro:    introBody
                case .scanning: scanningBody
                case .results:  resultsBody
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 680, height: 560)
        .background(Tokens.surfaceBase)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Deep scan")
                .font(Tokens.fontSectionTitle)
            Text("Walks your entire home directory and the login Keychain for anything that looks like an API key. Takes 30 seconds to a couple of minutes.")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Intro phase

    private var introBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            introRow(icon: "folder",
                     title: "Home directory",
                     detail: "Walks ~/ and every subfolder (skips node_modules, DerivedData, Library/Caches, etc.). Looks inside .env, shell rc files, YAML/JSON/TOML configs under 2 MB.")

            introRow(icon: "key",
                     title: "macOS Keychain",
                     detail: "Lists login-Keychain entries whose service or account name matches a provider. Only metadata — no secret is read and no Touch ID prompts until you migrate a specific entry.")

            introRow(icon: "shield.lefthalf.filled",
                     title: "What happens next",
                     detail: "Review findings, pick which to migrate. Originals in the Keychain are left untouched; matching lines in files are rewritten to point at the shh vault.")
        }
        .padding(24)
    }

    private func introRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Tokens.accent)
                .frame(width: 22, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Scanning phase

    private var scanningBody: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
            Text(progressLine)
                .font(.system(size: 13, weight: .medium))
            if let path = progress?.currentPath, !path.isEmpty {
                Text(shortPath(path))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 560)
            }
            if let err = keychainScanFailed {
                Text("Keychain scan: \(err)")
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.stateWarn)
            }
        }
        .padding(40)
    }

    private var progressLine: String {
        let files = progress?.filesScanned ?? 0
        let fileHits = progress?.hits ?? 0
        let kc = keychainHits.count
        return "Scanned \(files) files · \(fileHits) file hits · \(kc) Keychain hits"
    }

    // MARK: - Results phase

    private var resultsBody: some View {
        Group {
            if fileDetections.isEmpty && keychainHits.isEmpty {
                VStack(spacing: 8) {
                    Text("No keys found")
                        .font(.system(size: 14, weight: .medium))
                    Text("Nothing matched across your home directory or login Keychain.")
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.inkMuted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(40)
            } else {
                List {
                    if !fileDetections.isEmpty {
                        Section("Files (\(fileDetections.count))") {
                            ForEach(fileDetections) { d in
                                DeepScanFileRow(
                                    detection: d,
                                    checked: selectedFiles.contains(d.id)
                                ) { checked in
                                    if checked { selectedFiles.insert(d.id) }
                                    else       { selectedFiles.remove(d.id) }
                                }
                            }
                        }
                    }
                    if !keychainHits.isEmpty {
                        Section("macOS Keychain (\(keychainHits.count))") {
                            ForEach(keychainHits) { h in
                                DeepScanKeychainRow(
                                    hit: h,
                                    checked: selectedKeychain.contains(h.id)
                                ) { checked in
                                    if checked { selectedKeychain.insert(h.id) }
                                    else       { selectedKeychain.remove(h.id) }
                                }
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.stateError)
            }
            if let migrationStatus {
                Text(migrationStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.stateActive)
            }

            HStack {
                Button(cancelTitle) {
                    if phase == .scanning {
                        scanTask?.cancel()
                    } else {
                        dismiss()
                    }
                }
                .disabled(migrating)

                Spacer()

                switch phase {
                case .intro:
                    Button("Start scan") { startScan() }
                        .buttonStyle(.borderedProminent)
                        .tint(Tokens.accent)
                        .keyboardShortcut(.defaultAction)
                case .scanning:
                    EmptyView()
                case .results:
                    Picker("Bucket", selection: $bucket) {
                        ForEach(VaultKey.Bucket.allCases, id: \.self) { b in
                            Text(b.rawValue.capitalized).tag(b)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160)

                    Button(migrateTitle) {
                        Task { await migrate() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.accent)
                    .disabled(migrateDisabled)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private var cancelTitle: String {
        switch phase {
        case .scanning: return "Cancel scan"
        default:        return "Close"
        }
    }

    private var migrateTitle: String {
        let total = selectedFiles.count + selectedKeychain.count
        return total == 0 ? "Migrate selected" : "Migrate \(total) to vault"
    }

    private var migrateDisabled: Bool {
        (selectedFiles.isEmpty && selectedKeychain.isEmpty) || migrating
    }

    // MARK: - Actions

    private func startScan() {
        phase = .scanning
        errorMessage = nil
        migrationStatus = nil
        keychainScanFailed = nil
        fileDetections = []
        keychainHits = []
        selectedFiles = []
        selectedKeychain = []
        progress = nil

        // Detached so the filesystem walk doesn't block the main actor.
        scanTask = Task.detached(priority: .userInitiated) {
            // Keychain first (fast, no prompts).
            do {
                let hits = try KeychainScanner().scan()
                await MainActor.run { self.keychainHits = hits }
            } catch {
                await MainActor.run {
                    self.keychainScanFailed = error.localizedDescription
                }
            }

            do {
                let results = try await FileScanner.scanFullHome { prog in
                    Task { @MainActor in
                        self.progress = prog
                    }
                }
                if Task.isCancelled { return }
                let filtered = results.filter { $0.confidence == .high || $0.confidence == .mediumHint }
                await MainActor.run {
                    self.fileDetections = filtered
                    self.phase = .results
                }
            } catch is CancellationError {
                await MainActor.run {
                    self.phase = .intro
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.phase = .intro
                }
            }
        }
    }

    private func migrate() async {
        migrating = true
        errorMessage = nil
        migrationStatus = nil

        let filesToMigrate = fileDetections.filter { selectedFiles.contains($0.id) }
        let hitsToImport = keychainHits.filter { selectedKeychain.contains($0.id) }

        let migrator = Migrator(vault: Vault())
        var fileSucceeded = 0
        var fileFailed = 0
        if !filesToMigrate.isEmpty {
            let outcomes = await migrator.migrate(filesToMigrate, bucket: bucket)
            fileSucceeded = outcomes.filter { if case .success = $0.result { return true }; return false }.count
            fileFailed = outcomes.count - fileSucceeded
        }

        var kcSucceeded = 0
        var kcFailed = 0
        if !hitsToImport.isEmpty {
            let outcomes = await migrator.importFromKeychain(hitsToImport, bucket: bucket)
            kcSucceeded = outcomes.filter { if case .success = $0.result { return true }; return false }.count
            kcFailed = outcomes.count - kcSucceeded
        }

        fileDetections.removeAll { selectedFiles.contains($0.id) }
        keychainHits.removeAll { selectedKeychain.contains($0.id) }
        selectedFiles = []
        selectedKeychain = []

        let succeeded = fileSucceeded + kcSucceeded
        let failed = fileFailed + kcFailed
        migrationStatus = "Migrated \(succeeded) key\(succeeded == 1 ? "" : "s")" +
            (failed > 0 ? " · \(failed) failed" : "")
        migrating = false
    }

    private func shortPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.replacingOccurrences(of: home, with: "~")
    }
}

// MARK: - Row views

private struct DeepScanFileRow: View {
    let detection: Detection
    let checked: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { checked }, set: onToggle))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(detection.provider.rawValue)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text("···\(detection.fingerprint)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Tokens.inkMuted)
                    ConfidencePill(confidence: detection.confidence)
                    Spacer()
                }
                Text("\(shortPath(detection.sourcePath)):\(detection.lineNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.inkFaint)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle(!checked) }
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}

private struct DeepScanKeychainRow: View {
    let hit: KeychainHit
    let checked: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { checked }, set: onToggle))
                .labelsHidden()
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(hit.provider.rawValue)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    ConfidencePill(confidence: hit.confidence)
                    Spacer()
                }
                Text(hit.service.isEmpty ? hit.account : "\(hit.service) · \(hit.account)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.inkFaint)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onToggle(!checked) }
    }
}

private struct ConfidencePill: View {
    let confidence: Detection.Confidence
    var body: some View {
        Text(confidence.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.1)))
    }
    private var color: Color {
        switch confidence {
        case .high:       return Tokens.stateActive
        case .mediumHint: return Tokens.stateWarn
        case .low:        return Tokens.inkFaint
        }
    }
}
