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

            Divider()

            if keys.isEmpty {
                emptyState
            } else {
                keyList
            }

            Divider()

            actions
        }
        .frame(width: Tokens.dropdownWidth)
        .padding(.vertical, 8)
    }

    private var header: some View {
        HStack {
            Text("shh")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(keys.count) key\(keys.count == 1 ? "" : "s")")
                .font(Tokens.fontLabel)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("No keys yet")
                .font(Tokens.fontBody)
                .foregroundStyle(.secondary)
            Text("Add one from here, or run `shh keys add` in a terminal.")
                .font(Tokens.fontLabel)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
    }

    private var keyList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(keys) { key in
                HStack(spacing: 8) {
                    Text(key.provider.rawValue)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 88, alignment: .leading)
                    Text(key.label)
                        .font(Tokens.fontBody)
                    Spacer()
                    Text("···\(key.fingerprint)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            action(title: "Add key", shortcut: "⌘N", action: onAddKey)
            action(title: "Quit shh",   shortcut: "⌘Q", action: onQuit)
        }
        .padding(.top, 4)
    }

    private func action(title: String, shortcut: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(Tokens.fontBody)
                Spacer()
                Text(shortcut)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
