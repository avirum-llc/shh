import SwiftUI
import ShhCore

struct DashboardWindow: View {
    @State private var records: [RequestRecord] = []
    @State private var range: Range = .today

    enum Range: String, CaseIterable, Identifiable {
        case today, week, month, all
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            rangePicker
            hero
            Divider()
            byProvider
            Divider()
            byProject
            Spacer()
            footer
        }
        .padding(24)
        .frame(width: Tokens.dashboardWidth, height: 520)
        .background(Tokens.surfaceBase)
        .task { await load() }
        .onChange(of: range) { _, _ in Task { await load() } }
    }

    // MARK: - Sections

    private var rangePicker: some View {
        HStack(spacing: 8) {
            ForEach(Range.allCases) { r in
                Button(action: { range = r }) {
                    Text(r.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(r == range ? Tokens.accent : Tokens.inkMuted)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(r == range ? Tokens.accent.opacity(0.08) : .clear)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(formatCurrency(total))
                .font(Tokens.fontHeroLarge)
                .foregroundStyle(Tokens.ink)
            Text("\(records.count) request\(records.count == 1 ? "" : "s") · estimated")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.inkMuted)
        }
    }

    private var byProvider: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Providers")
            if providerRows.isEmpty {
                Text("No requests in this range.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.inkFaint)
            } else {
                ForEach(providerRows, id: \.name) { row in
                    HStack {
                        Text(row.name)
                            .font(.system(size: 12, design: .monospaced))
                        Spacer()
                        Text("\(row.count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(Tokens.inkMuted)
                        Text(formatCurrency(row.amount))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var byProject: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Projects")
            if projectRows.isEmpty {
                Text("No requests in this range.")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.inkFaint)
            } else {
                ForEach(projectRows, id: \.name) { row in
                    HStack {
                        Text(row.name)
                            .font(.system(size: 12))
                        Spacer()
                        Text(formatCurrency(row.amount))
                            .font(.system(size: 12, design: .monospaced))
                            .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Text("Numbers are estimated from byte-length heuristics.")
                .font(.system(size: 10))
                .foregroundStyle(Tokens.inkFaint)
            Spacer()
        }
    }

    // MARK: - Helpers

    private var total: Double { records.reduce(0) { $0 + $1.costUSDEstimated } }

    private struct Row: Hashable {
        let name: String
        let amount: Double
        let count: Int
    }

    private var providerRows: [Row] {
        var counts: [String: (Double, Int)] = [:]
        for r in records {
            let cur = counts[r.provider.rawValue] ?? (0, 0)
            counts[r.provider.rawValue] = (cur.0 + r.costUSDEstimated, cur.1 + 1)
        }
        return counts.map { Row(name: $0.key, amount: $0.value.0, count: $0.value.1) }
            .sorted { $0.amount > $1.amount }
    }

    private var projectRows: [Row] {
        var counts: [String: Double] = [:]
        for r in records {
            counts[r.projectTag, default: 0] += r.costUSDEstimated
        }
        return counts.map { Row(name: $0.key, amount: $0.value, count: 0) }
            .sorted { $0.amount > $1.amount }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Tokens.inkFaint)
            .tracking(0.04 * 10)
    }

    private func formatCurrency(_ amount: Double) -> String {
        String(format: "$%.4f", amount)
    }

    private func load() async {
        let log = RequestLog()
        let now = Date()
        let cal = Calendar.current
        let since: Date
        switch range {
        case .today: since = cal.startOfDay(for: now)
        case .week:  since = cal.date(byAdding: .day, value: -7, to: now) ?? now
        case .month: since = cal.date(byAdding: .day, value: -30, to: now) ?? now
        case .all:   since = Date.distantPast
        }
        records = (try? await log.since(since)) ?? []
    }
}
