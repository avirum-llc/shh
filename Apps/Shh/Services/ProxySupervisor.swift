import Foundation
import ShhCore

/// SwiftUI-facing wrapper around `ProxyServer`. Owns the actor, exposes
/// observable state, and starts the proxy at app launch.
@MainActor
@Observable
final class ProxySupervisor {
    enum State: Equatable {
        case stopped
        case starting
        case running(port: UInt16)
        case failed(message: String)
    }

    private(set) var state: State = .stopped
    private(set) var todayCostEstimated: Double = 0
    private(set) var requestCountToday: Int = 0

    private let vault: Vault
    private let log = RequestLog()
    private var server: ProxyServer?
    private var refreshTask: Task<Void, Never>?

    init(vault: Vault) {
        self.vault = vault
    }

    func start() async {
        guard case .stopped = state else { return }
        state = .starting
        let server = ProxyServer(vault: vault, log: log)
        do {
            try await server.start()
            self.server = server
            state = .running(port: server.port)
            startRefreshLoop()
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    func stop() async {
        refreshTask?.cancel()
        refreshTask = nil
        await server?.stop()
        server = nil
        state = .stopped
    }

    /// Poll the log every few seconds so the menubar hero number stays
    /// fresh. Cheap — NDJSON read + sum over today's records.
    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshSpend()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    func refreshSpend() async {
        let records = (try? await log.since(Calendar.current.startOfDay(for: Date()))) ?? []
        todayCostEstimated = records.reduce(0) { $0 + $1.costUSDEstimated }
        requestCountToday = records.count
    }
}
