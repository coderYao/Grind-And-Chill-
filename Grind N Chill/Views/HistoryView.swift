import SwiftUI
import SwiftData

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

            if filtered.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Entries",
                        systemImage: "tray",
                        description: Text("Start a timer or add a manual entry to populate history.")
                    )
                }
            } else {
                Section("Recent") {
                    ForEach(filtered) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label(entry.category.title, systemImage: entry.category.resolvedSymbolName)
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
                    .onDelete { offsets in
                        viewModel.deleteEntries(at: offsets, from: filtered, modelContext: modelContext)
                    }
                }
            }
        }
        .navigationTitle("History")
    }
}
