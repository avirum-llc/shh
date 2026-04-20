import ArgumentParser
import Foundation
import ShhCore

struct SpendCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "spend",
        abstract: "Show estimated LLM spend across providers."
    )

    enum Range: String, ExpressibleByArgument, CaseIterable {
        case today, week, month, all
    }

    @Option(help: "Time range: today | week | month | all")
    var range: Range = .today

    @Flag(help: "Emit JSON.")
    var json: Bool = false

    func run() async throws {
        let log = RequestLog()
        let allRecords = try await log.all()
        let now = Date()
        let cal = Calendar.current

        let since: Date
        switch range {
        case .today: since = cal.startOfDay(for: now)
        case .week:  since = cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: since = cal.date(byAdding: .day, value: -30, to: now) ?? now
        case .all:   since = Date.distantPast
        }

        let records = allRecords.filter { $0.timestamp >= since }
        let total = records.reduce(0.0) { $0 + $1.costUSDEstimated }

        var byProvider: [String: Double] = [:]
        for r in records {
            byProvider[r.provider.rawValue, default: 0] += r.costUSDEstimated
        }

        if json {
            let payload: [String: Any] = [
                "range": range.rawValue,
                "total_usd_estimated": total,
                "by_provider": byProvider,
                "request_count": records.count,
            ]
            let data = try JSONSerialization.data(
                withJSONObject: payload,
                options: [.prettyPrinted, .sortedKeys]
            )
            print(String(data: data, encoding: .utf8) ?? "{}")
            return
        }

        print("Spend (\(range.rawValue)) — estimated")
        print(String(format: "  Total:    $%.4f", total))
        print("  Requests: \(records.count)")
        for (provider, amount) in byProvider.sorted(by: { $0.value > $1.value }) {
            let padded = provider.padding(toLength: 12, withPad: " ", startingAt: 0)
            print("  \(padded)  $\(String(format: "%.4f", amount))")
        }
    }
}
