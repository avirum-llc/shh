import SwiftUI
import ShhCore

struct MenuBarDropdown: View {
    let keys: [VaultKey]
    let proxyState: ProxySupervisor.State
    let todayCost: Double
    let requestCount: Int
    let onAddKey: () -> Void
    let onOpenDashboard: () -> Void
    let onOpenConnect: () -> Void
    let onOpenScanner: () -> Void
    let onInstallCLI: () -> String
    let onRefresh: @Sendable () async -> Void
    let onQuit: () -> Void

    @State private var installCLIMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 10)

            Divider()

            hero
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            Divider()

            if keys.isEmpty {
                emptyState
            } else {
                keyList
            }

            Divider()

            actions
                .padding(.vertical, 4)
        }
        .frame(width: 300)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("shh")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusPill
        }
    }

    private var subtitle: String {
        keys.isEmpty ? "No keys yet" : "\(keys.count) key\(keys.count == 1 ? "" : "s") in vault"
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        switch proxyState {
        case .stopped:  return "proxy off"
        case .starting: return "starting"
        case .running:  return "proxy on"
        case .failed:   return "proxy failed"
        }
    }

    private var statusColor: Color {
        switch proxyState {
        case .stopped, .starting: return Color.secondary
        case .running:            return Color.green
        case .failed:             return Color.red
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "$%.2f", todayCost))
                .font(.system(size: 28, weight: .ultraLight).monospacedDigit())
            Text("today · \(requestCount) request\(requestCount == 1 ? "" : "s") · estimated")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your API keys, safely stored.")
                .font(.system(size: 12))
            Text("Add one here, or run `shh scan` to migrate keys you already have.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var keyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keys) { key in
                keyRow(key)
            }
        }
        .padding(.vertical, 4)
    }

    private func keyRow(_ key: VaultKey) -> some View {
        HStack(spacing: 10) {
            providerAvatar(key.provider)
            VStack(alignment: .leading, spacing: 1) {
                Text(key.label)
                    .font(.system(size: 12, weight: .medium))
                Text(key.provider.rawValue)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("···\(key.fingerprint)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private func providerAvatar(_ provider: VaultKey.Provider) -> some View {
        let letter = String(provider.rawValue.prefix(1)).uppercased()
        return Circle()
            .fill(Color.accentColor.opacity(0.14))
            .frame(width: 24, height: 24)
            .overlay {
                Text(letter)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
            }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow("Dashboard", shortcut: "⌘D", primary: false, action: onOpenDashboard)
            actionRow("Add key", shortcut: "⌘N", primary: true, action: onAddKey)
            actionRow("Scan for API keys…", shortcut: "⌘S", primary: false, action: onOpenScanner)
            actionRow("Connect a tool…", shortcut: "⌘T", primary: false, action: onOpenConnect)
            actionRow("Install CLI", shortcut: "", primary: false) {
                installCLIMessage = onInstallCLI()
            }
            if let installCLIMessage {
                Text(installCLIMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 6)
            }
            actionRow("Quit shh", shortcut: "⌘Q", primary: false, action: onQuit)
        }
    }

    private func actionRow(
        _ title: String,
        shortcut: String,
        primary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: primary ? .medium : .regular))
                    .foregroundStyle(primary ? .primary : .secondary)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}
