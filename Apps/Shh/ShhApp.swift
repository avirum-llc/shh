import SwiftUI
import ShhCore

@main
struct ShhApp: App {
    @State private var keys: [VaultKey] = []
    @State private var showingAddKey = false

    private static let vault = Vault()

    var body: some Scene {
        MenuBarExtra {
            MenuBarDropdown(
                keys: keys,
                onAddKey: { showingAddKey = true },
                onRefresh: refresh,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .task { await refresh() }
            .sheet(isPresented: $showingAddKey) {
                AddKeySheet(
                    vault: Self.vault,
                    onDismiss: {
                        showingAddKey = false
                        Task { await refresh() }
                    }
                )
            }
        } label: {
            MenuBarLabel(keyCount: keys.count)
        }
        .menuBarExtraStyle(.window)
    }

    @Sendable
    private func refresh() async {
        keys = (try? await Self.vault.list()) ?? []
    }
}
