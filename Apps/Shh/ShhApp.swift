import SwiftUI
import ShhCore

@main
struct ShhApp: App {
    @State private var keys: [VaultKey] = []
    @State private var supervisor: ProxySupervisor

    private static let vault = Vault()

    init() {
        let sup = ProxySupervisor(vault: Self.vault)
        _supervisor = State(wrappedValue: sup)
        // Kick off proxy start on the main actor. Runs on the next main
        // queue tick — the supervisor is already initialised by then.
        Task { @MainActor in
            await sup.start()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                keys: keys,
                supervisor: supervisor,
                onRefresh: refresh,
                onQuit: { NSApplication.shared.terminate(nil) }
            )
            .task {
                await supervisor.start()
                await refresh()
            }
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

        Window("Spend", id: WindowID.dashboard) {
            DashboardWindow()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Connect a tool", id: WindowID.connect) {
            ConnectWindow()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Welcome to shh", id: WindowID.firstRun) {
            FirstRunWindow()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Scan for API keys", id: WindowID.scanner) {
            ScannerWindow()
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    @Sendable
    private func refresh() async {
        keys = (try? await Self.vault.list()) ?? []
        await supervisor.refreshSpend()
    }
}

enum WindowID {
    static let addKey = "shh.window.addKey"
    static let dashboard = "shh.window.dashboard"
    static let connect = "shh.window.connect"
    static let firstRun = "shh.window.firstRun"
    static let scanner = "shh.window.scanner"
}

private struct MenuBarContent: View {
    let keys: [VaultKey]
    let supervisor: ProxySupervisor
    let onRefresh: @Sendable () async -> Void
    let onQuit: () -> Void

    @Environment(\.openWindow) private var openWindow
    @AppStorage("shh.firstRunCompleted") private var firstRunCompleted = false

    var body: some View {
        MenuBarDropdown(
            keys: keys,
            proxyState: supervisor.state,
            todayCost: supervisor.todayCostEstimated,
            requestCount: supervisor.requestCountToday,
            onAddKey: { open(WindowID.addKey) },
            onOpenDashboard: { open(WindowID.dashboard) },
            onOpenConnect: { open(WindowID.connect) },
            onOpenScanner: { open(WindowID.scanner) },
            onInstallCLI: installCLI,
            onRefresh: onRefresh,
            onQuit: onQuit
        )
        .task {
            if !firstRunCompleted {
                open(WindowID.firstRun)
            }
        }
    }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }

    private func installCLI() -> String {
        do {
            let result = try CLIInstaller.install()
            switch result {
            case .installed(let url):
                return "CLI installed at \(url.path). Open a new terminal and try `shh --version`."
            case .alreadyInstalled(let url):
                return "CLI already linked at \(url.path)."
            case .needsManualInstall(let source, let suggested):
                let paths = suggested.map { $0.path }.joined(separator: " | ")
                return "Couldn't write to \(paths). Run: ln -sf '\(source.path)' /usr/local/bin/shh"
            }
        } catch {
            return error.localizedDescription
        }
    }
}

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
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }
}
