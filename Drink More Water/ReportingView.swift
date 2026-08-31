import SwiftUI
import SwiftData
import Charts

/// Spec: "Reporting screen" — chart ⇄ list toggle, one at a time,
/// drink/ignore/missed per day/week/month, person name as display label.
struct ReportingView: View {
    enum ReportMode: String, CaseIterable, Identifiable {
        case chart, list
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    let modelContainer: ModelContainer
    @Query private var events: [ReminderEvent]
    @Query private var settings: [AppSettings]

    @State private var mode: ReportMode = .chart
    @State private var granularity: StatsAggregator.Granularity = .day

    private var buckets: [StatsBucket] {
        StatsAggregator.buckets(
            for: events,
            granularity: granularity,
            bucketCount: count(for: granularity)
        )
    }

    var body: some View {
        VStack(spacing: 16) {
            Picker("View", selection: $mode) {
                ForEach(ReportMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Picker("Range", selection: $granularity) {
                ForEach(StatsAggregator.Granularity.allCases) { g in
                    Text(g.label).tag(g)
                }
            }
            .pickerStyle(.segmented)

            Text("\(settings.first?.personName ?? "You") — \(granularity.label.lowercased()) totals")
                .font(.headline)

            if buckets.allSatisfy({ $0.drink == 0 && $0.ignore == 0 && $0.missed == 0 }) {
                ContentUnavailableView(
                    "No data yet",
                    systemImage: "chart.bar",
                    description: Text("Answer a few reminders and your stats will appear here.")
                )
            } else if mode == .chart {
                StatsChartView(buckets: buckets)
            } else {
                StatsListView(buckets: buckets)
            }
        }
        .padding()
        .navigationTitle("Stats")
    }

    private func count(for granularity: StatsAggregator.Granularity) -> Int {
        switch granularity {
        case .day: 7
        case .week: 4
        case .month: 6
        }
    }
}

// MARK: - Chart

private struct StatsChartView: View {
    let buckets: [StatsBucket]

    private struct StatPoint: Identifiable {
        let id = UUID()
        let period: String
        let response: String
        let count: Int
    }

    private var points: [StatPoint] {
        buckets.flatMap { bucket in
            [
                StatPoint(period: bucket.label, response: "Drank", count: bucket.drink),
                StatPoint(period: bucket.label, response: "Ignored", count: bucket.ignore),
                StatPoint(period: bucket.label, response: "Missed", count: bucket.missed),
            ]
        }
    }

    var body: some View {
        Chart(points) { point in
            BarMark(
                x: .value("Period", point.period),
                y: .value("Count", point.count)
            )
            .foregroundStyle(by: .value("Response", point.response))
        }
        .chartForegroundStyleScale([
            "Drank": Color.green,
            "Ignored": Color.orange,
            "Missed": Color.red,
        ])
        .frame(maxHeight: 320)
    }
}

// MARK: - List

private struct StatsListView: View {
    let buckets: [StatsBucket]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Period").frame(maxWidth: .infinity, alignment: .leading)
                columns
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 6)
            Divider()

            ForEach(buckets.reversed()) { bucket in
                HStack {
                    Text(bucket.label).frame(maxWidth: .infinity, alignment: .leading)
                    columns(counts: bucket)
                }
                .padding(.vertical, 4)
            }
        }
        .frame(maxHeight: 320)
    }

    @ViewBuilder
    private var columns: some View {
        countColumn("Drank", tint: .green)
        countColumn("Ignored", tint: .orange)
        countColumn("Missed", tint: .red)
    }

    @ViewBuilder
    private func columns(counts: StatsBucket) -> some View {
        countText(counts.drink, tint: .green)
        countText(counts.ignore, tint: .orange)
        countText(counts.missed, tint: .red)
    }

    private func countColumn(_ title: String, tint: Color) -> some View {
        Text(title)
            .frame(width: 72, alignment: .trailing)
    }

    private func countText(_ count: Int, tint: Color) -> some View {
        Text("\(count)")
            .monospacedDigit()
            .foregroundStyle(tint)
            .frame(width: 72, alignment: .trailing)
    }
}
