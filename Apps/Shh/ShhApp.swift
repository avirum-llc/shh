import SwiftUI
import ShhCore

@main
struct ShhApp: App {
    @State private var keys: [VaultKey] = []
    private static let vault = Vault()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                keys: keys,
                onRefresh: refresh,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Window("Add API key", id: WindowID.addKey) {
            AddKeyWindowRoot(
                vault: Self.vault,
                onSaved: { Task { await refresh() } }
            )
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @Sendable
    private func refresh() async {
        keys = (try? await Self.vault.list()) ?? []
    }
}

/// Identifiers for programmatically-opened windows.
enum WindowID {
    static let addKey = "shh.window.addKey"
}

/// Menubar dropdown body. Lives inside a View so we can pull
/// `@Environment(\.openWindow)` — which is how a sheet-like flow is
/// presented without fighting MenuBarExtra's focus behaviour. Opening a
/// proper Window scene survives the dropdown closing and takes its own
/// keyboard focus.
private struct MenuBarContent: View {
    let keys: [VaultKey]
    let onRefresh: @Sendable () async -> Void
    let onQuit: () -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        MenuBarDropdown(
            keys: keys,
            onAddKey: openAddKey,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
        .task { await onRefresh() }
    }

    private func openAddKey() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.addKey)
    }
}

/// Thin wrapper that gives the Add Key form a real Window lifecycle plus
/// an `onAppear` activation so the window comes to front even though this
/// is an `LSUIElement` accessory app.
private struct AddKeyWindowRoot: View {
    let vault: Vault
    let onSaved: () -> Void

    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        AddKeySheet(
            vault: vault,
            onDismiss: {
                onSaved()
                dismissWindow(id: WindowID.addKey)
            }
        )
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
