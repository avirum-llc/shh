import SwiftUI
import ShhCore

struct MenuBarDropdown: View {
    let keys: [VaultKey]
    let onAddKey: () -> Void
    let onRefresh: @Sendable () async -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 12)

            Divider()

            Group {
                if keys.isEmpty {
                    emptyState
                } else {
                    keyList
                }
            }

            Divider()

            actions
                .padding(.vertical, 4)
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("shh")
                .font(.system(size: 13, weight: .semibold))
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        keys.isEmpty ? "No keys yet" : "\(keys.count) key\(keys.count == 1 ? "" : "s") in vault"
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Your API keys, safely stored.")
                .font(.system(size: 12))
            Text("Add one here, or run `shh keys add` in a terminal.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Key list

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

    // MARK: - Actions

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            actionRow("Add key", shortcut: "⌘N", primary: true, action: onAddKey)
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
