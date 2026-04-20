import SwiftUI
import ShhCore

struct ScannerWindow: View {
    @State private var detections: [Detection] = []
    @State private var selected: Set<Detection.ID> = []
    @State private var scanning = false
    @State private var migrating = false
    @State private var bucket: VaultKey.Bucket = .personal
    @State private var errorMessage: String?
    @State private var migrationStatus: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 14)

            Divider()

            if scanning {
                ProgressView("Scanning your home directory…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if detections.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detectionList
            }

            Divider()
            footer
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
        }
        .frame(width: 660, height: 540)
        .background(Tokens.surfaceBase)
        .task { await scan() }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Scan for leaked keys")
                .font(Tokens.fontSectionTitle)
            Text("shh walks your shell configs, CLI config files, and common project directories for anything that looks like an API key.")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No keys found")
                .font(.system(size: 14, weight: .medium))
            Text("Either you're already using shh for everything, or your keys are in a location we haven't scanned.")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.inkMuted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
    }

    private var detectionList: some View {
        List(detections, selection: $selected) { detection in
            DetectionRow(detection: detection, checked: selected.contains(detection.id)) { checked in
                if checked { selected.insert(detection.id) }
                else       { selected.remove(detection.id) }
            }
        }
        .listStyle(.plain)
    }

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
                Button("Rescan") {
                    Task { await scan() }
                }
                .disabled(scanning || migrating)

                Spacer()

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
                .disabled(selected.isEmpty || migrating)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var migrateTitle: String {
        let n = selected.count
        return n == 0 ? "Migrate selected" : "Migrate \(n) to vault"
    }

    // MARK: - Actions

    private func scan() async {
        scanning = true
        errorMessage = nil
        migrationStatus = nil
        selected = []
        let scanner = FileScanner()
        let results = scanner.scan()
        // Filter to high + mediumHint by default — low-confidence matches
        // are noise in the UI
        detections = results.filter { $0.confidence == .high || $0.confidence == .mediumHint }
        scanning = false
    }

    private func migrate() async {
        guard !selected.isEmpty else { return }
        migrating = true
        errorMessage = nil
        let toMigrate = detections.filter { selected.contains($0.id) }
        let migrator = Migrator(vault: Vault())
        let outcomes = await migrator.migrate(toMigrate, bucket: bucket)
        let succeeded = outcomes.filter { if case .success = $0.result { return true }; return false }.count
        let failed = outcomes.count - succeeded
        migrationStatus = "Migrated \(succeeded) key\(succeeded == 1 ? "" : "s")\(failed > 0 ? " · \(failed) failed" : "") · rescan to see updated state"
        migrating = false
        // Remove migrated ones from the visible list
        detections.removeAll { selected.contains($0.id) }
        selected = []
    }
}

private struct DetectionRow: View {
    let detection: Detection
    let checked: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { checked },
                set: onToggle
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(detection.provider.rawValue)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                    Text("···\(detection.fingerprint)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Tokens.inkMuted)
                    confidencePill
                    Spacer()
                }
                Text("\(shortPath(detection.sourcePath)):\(detection.lineNumber)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Tokens.inkFaint)
                if let hint = detection.envHintMatched {
                    Text("env: \(hint)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Tokens.inkFaint)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture { onToggle(!checked) }
    }

    private var confidencePill: some View {
        Text(detection.confidence.rawValue)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(confidenceColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4).fill(confidenceColor.opacity(0.1)))
    }

    private var confidenceColor: Color {
        switch detection.confidence {
        case .high:       return Tokens.stateActive
        case .mediumHint: return Tokens.stateWarn
        case .low:        return Tokens.inkFaint
        }
    }

    private func shortPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.replacingOccurrences(of: home, with: "~")
    }
}
