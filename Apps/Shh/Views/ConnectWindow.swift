import SwiftUI
import ShhCore

struct ConnectWindow: View {
    @State private var states: [ConnectorState] = []
    @State private var project: String = "default"
    @State private var label: String = "personal"
    @State private var errorMessage: String?

    struct ConnectorState: Identifiable {
        let connector: Connector
        let installed: Bool
        let connected: Bool
        var id: String { connector.id }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            tuningRow
            Divider()
            connectorList
            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(Tokens.stateError)
            }
            Spacer()
            footer
        }
        .padding(24)
        .frame(width: 520, height: 520)
        .background(Tokens.surfaceBase)
        .task { await refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connect a tool")
                .font(Tokens.fontSectionTitle)
            Text("Route your AI CLIs through the shh proxy so the real key never enters their environment.")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tuningRow: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Project")
                    .font(Tokens.fontLabel)
                    .foregroundStyle(Tokens.inkMuted)
                TextField("default", text: $project)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Key label")
                    .font(Tokens.fontLabel)
                    .foregroundStyle(Tokens.inkMuted)
                TextField("personal", text: $label)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 140)
            }
            Spacer()
        }
    }

    private var connectorList: some View {
        VStack(spacing: 8) {
            ForEach(states) { state in
                connectorRow(state)
            }
        }
    }

    private func connectorRow(_ state: ConnectorState) -> some View {
        HStack(spacing: 14) {
            monogram(state.connector)
            VStack(alignment: .leading, spacing: 1) {
                Text(state.connector.displayName)
                    .font(.system(size: 13, weight: .medium))
                Text(statusText(state))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(statusColor(state))
            }
            Spacer()
            actionButton(state)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 8).fill(Tokens.surfaceCard))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Tokens.borderHairline, lineWidth: Tokens.hairlineWidth)
        )
        .opacity(state.installed ? 1 : 0.55)
    }

    private func monogram(_ connector: Connector) -> some View {
        Circle()
            .fill(Tokens.accent.opacity(0.12))
            .frame(width: 28, height: 28)
            .overlay {
                Text(connector.id.prefix(2).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Tokens.accent)
            }
    }

    private func statusText(_ state: ConnectorState) -> String {
        if !state.installed { return "Not detected — install first" }
        return state.connected ? "Connected" : "Detected — not connected"
    }

    private func statusColor(_ state: ConnectorState) -> Color {
        if !state.installed { return Tokens.inkFaint }
        return state.connected ? Tokens.stateActive : Tokens.inkMuted
    }

    @ViewBuilder
    private func actionButton(_ state: ConnectorState) -> some View {
        if !state.installed {
            Text("Docs")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.inkFaint)
        } else if state.connected {
            Button("Disconnect") {
                Task { await disconnect(state.connector) }
            }
            .buttonStyle(.bordered)
        } else {
            Button("Connect") {
                Task { await connect(state.connector) }
            }
            .buttonStyle(.borderedProminent)
            .tint(Tokens.accent)
        }
    }

    private var footer: some View {
        Text("Connecting writes a small block into the CLI's config. shh shows you every change; disconnect restores the original.")
            .font(.system(size: 11))
            .foregroundStyle(Tokens.inkFaint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Actions

    private func refresh() async {
        states = Connectors.all.map { c in
            ConnectorState(
                connector: c,
                installed: c.isInstalled(),
                connected: (try? c.isConnected()) ?? false
            )
        }
    }

    private func connect(_ connector: Connector) async {
        errorMessage = nil
        let token = DummyToken(
            provider: connector.defaultProvider,
            project: project.isEmpty ? "default" : project,
            keyLabel: label.isEmpty ? "personal" : label
        )
        let proxyURL = URL(string: "http://127.0.0.1:\(ProxyServer.defaultPort)")!
        do {
            try connector.connect(token: token, proxyURL: proxyURL)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect(_ connector: Connector) async {
        errorMessage = nil
        do {
            try connector.disconnect()
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
