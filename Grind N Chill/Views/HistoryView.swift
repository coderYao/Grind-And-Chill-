import SwiftUI
import SwiftData
import Charts

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.timestamp, order: .reverse) private var entries: [Entry]

    @State private var viewModel = HistoryViewModel()

    var body: some View {
        List {
            if let error = viewModel.latestError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle("Manual entries only", isOn: $viewModel.showManualOnly)
            }

            let filtered = viewModel.filteredEntries(from: entries)
            let dailySummaries = viewModel.dailySummaries(from: filtered)
            let chartPoints = viewModel.chartPoints(from: dailySummaries)

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "tray",
                        description: Text("Start a timer or add a manual entry to populate history.")
                    )
                }
            } else {
                Section("Charts") {
                    historyChart(points: chartPoints)
                }

                ForEach(dailySummaries) { summary in
                    Section {
                        dailySummaryRow(summary)

                        ForEach(summary.entries) { entry in
                            entryRow(entry)
                        }
                        .onDelete { offsets in
                            viewModel.deleteEntries(at: offsets, from: summary.entries, modelContext: modelContext)
                        }
                    } header: {
                        Text(summary.date, format: .dateTime.month().day().year())
                    }
                }
            }
        }
        .navigationTitle("History")
    }

    private func historyChart(points: [HistoryViewModel.DailyChartPoint]) -> some View {
        Chart {
            ForEach(points) { point in
                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Amount", point.gain)
                )
                .foregroundStyle(by: .value("Series", "Gain"))

                BarMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Amount", point.spentAsNegative)
                )
                .foregroundStyle(by: .value("Series", "Spent"))

                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Amount", point.ledgerChange)
                )
                .lineStyle(StrokeStyle(lineWidth: 2))
                .foregroundStyle(by: .value("Series", "Net"))

                PointMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Amount", point.ledgerChange)
                )
                .foregroundStyle(by: .value("Series", "Net"))
            }
        }
        .chartForegroundStyleScale([
            "Gain": Color.green,
            "Spent": Color.red,
            "Net": Color.blue
        ])
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .currency(code: "USD"))
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                AxisGridLine()
                AxisTick()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        }
        .chartLegend(position: .bottom)
        .frame(height: 220)
        .padding(.vertical, 4)
    }

    private func dailySummaryRow(_ summary: HistoryViewModel.DailySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Daily Ledger Change")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(summary.ledgerChange, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(summary.ledgerChange < .zeroValue ? .red : .green)
            }

            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Text("Gain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.gain, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.green)
                }

                HStack(spacing: 4) {
                    Text("Spent")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(summary.spent, format: .currency(code: "USD"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func entryRow(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: entry.category.resolvedSymbolName)
                        .foregroundStyle(entry.category.resolvedIconColor.swiftUIColor)
                    Text(entry.category.title)
                }
                .font(.headline)
                Spacer()
                Text(entry.amountUSD, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.amountUSD < .zeroValue ? .red : .green)
            }

            Text(viewModel.subtitle(for: entry))
                .font(.subheadline)

            Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
