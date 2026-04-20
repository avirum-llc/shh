import SwiftUI
import ShhCore

/// Sheet presented from the menubar dropdown to add a new API key.
/// Mirrors the `shh keys add` CLI but through a native form. Matches
/// `shh-plan.md` §4 "Add key sheet" design.
struct AddKeySheet: View {
    let vault: Vault
    let onDismiss: () -> Void

    @State private var providerText: String = "anthropic"
    @State private var label: String = "personal"
    @State private var secret: String = ""
    @State private var bucket: VaultKey.Bucket = .personal
    @State private var errorMessage: String?
    @State private var isSaving = false

    private static let knownProviders: [VaultKey.Provider] = [
        .anthropic, .openai, .gemini,
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add API key")
                .font(Tokens.fontSectionTitle)

            VStack(alignment: .leading, spacing: 14) {
                providerField
                labelField
                secretField
                bucketField
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(Tokens.fontLabel)
                    .foregroundStyle(Tokens.stateError)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            HStack {
                Button("Cancel", action: onDismiss)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save to vault", action: save)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.accent)
                    .disabled(isSaving || secret.isEmpty || label.isEmpty || providerText.isEmpty)
            }
        }
        .padding(22)
        .frame(width: 360)
    }

    private var providerField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("Provider")
            Picker("Provider", selection: $providerText) {
                ForEach(Self.knownProviders, id: \.rawValue) { p in
                    Text(p.rawValue).tag(p.rawValue)
                }
                Divider()
                Text("Custom…").tag("__custom__")
            }
            .labelsHidden()
            .pickerStyle(.menu)
            if providerText == "__custom__" {
                TextField("Custom provider name", text: $providerText)
                    .textFieldStyle(.roundedBorder)
                    .onAppear { providerText = "" }
            }
        }
    }

    private var labelField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("Label")
            TextField("personal, work, …", text: $label)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var secretField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("API key")
            SecureField("sk-…", text: $secret)
                .textFieldStyle(.roundedBorder)
            Text("Clipboard will be cleared on save.")
                .font(Tokens.fontLabel)
                .foregroundStyle(.tertiary)
        }
    }

    private var bucketField: some View {
        VStack(alignment: .leading, spacing: 5) {
            fieldLabel("Accounting bucket")
            Picker("Bucket", selection: $bucket) {
                ForEach(VaultKey.Bucket.allCases, id: \.self) { b in
                    Text(b.rawValue.capitalized).tag(b)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Tokens.fontLabel)
            .foregroundStyle(.secondary)
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let provider = VaultKey.Provider(rawValue: providerText)
        let labelCapture = label
        let secretCapture = secret
        let bucketCapture = bucket

        Task {
            do {
                _ = try await vault.add(
                    provider: provider,
                    label: labelCapture,
                    bucket: bucketCapture,
                    secret: secretCapture
                )
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    onDismiss()
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }
}
