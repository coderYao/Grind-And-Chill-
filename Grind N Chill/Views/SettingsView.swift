import SwiftUI

struct SettingsView: View {
    @Environment(TimerManager.self) private var timerManager
    @Environment(SyncMonitor.self) private var syncMonitor

    @AppStorage(AppStorageKeys.usdPerHour) private var usdPerHourRaw: Double = 18

    @State private var viewModel = SettingsViewModel()

    var body: some View {
        Form {
            Section("Ledger Rate") {
                HStack {
                    Text("USD per Hour")
                    Spacer()
                    TextField(
                        "USD per Hour",
                        value: $usdPerHourRaw,
                        format: .number.precision(.fractionLength(2))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                }

                Text("Current rate: \(viewModel.asDecimal(usdPerHourRaw).formatted(.currency(code: "USD")))/hour")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Session Recovery") {
                if timerManager.isRunning {
                    Text("A timer is active and will continue from the saved start time.")
                } else {
                    Text("No active session is running.")
                        .foregroundStyle(.secondary)
                }

                Button("Clear Active Session") {
                    timerManager.clearSession()
                }
                .foregroundStyle(.red)
                .disabled(timerManager.isRunning == false)
            }

            Section("Sync") {
                HStack(spacing: 8) {
                    Image(systemName: syncMonitor.statusSymbol)
                        .foregroundStyle(syncMonitor.isStatusWarning ? .orange : .secondary)
                    Text(syncMonitor.statusTitle)
                        .foregroundStyle(.secondary)
                }

                NavigationLink("Sync Details") {
                    SyncDetailsView()
                }
            }

            Section("How It Works") {
                Text("Grind time adds money to your ledger. Chill time subtracts money.")
                Text("Streaks are calendar-based and recalculate automatically after midnight.")
            }
        }
        .navigationTitle("Settings")
        .onChange(of: usdPerHourRaw, initial: false) { _, newValue in
            usdPerHourRaw = viewModel.normalizedUSDPerHour(newValue)
        }
    }
}

private struct SyncDetailsView: View {
    @Environment(SyncMonitor.self) private var syncMonitor

    var body: some View {
        Form {
            Section("Status") {
                HStack(spacing: 10) {
                    if syncMonitor.status == .syncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: syncMonitor.statusSymbol)
                            .foregroundStyle(syncMonitor.isStatusWarning ? .orange : .secondary)
                    }
                    Text(syncMonitor.statusTitle)
                }

                if let banner = syncMonitor.bannerMessage {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: syncMonitor.isStatusWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                            .foregroundStyle(syncMonitor.isStatusWarning ? .orange : .green)
                        Text(banner)
                            .font(.footnote)
                    }
                }
            }

            Section("Last Successful Transfers") {
                transferTimestampRow(
                    title: "Last Import",
                    date: syncMonitor.lastImportDate,
                    symbol: "tray.and.arrow.down"
                )
                transferTimestampRow(
                    title: "Last Export",
                    date: syncMonitor.lastExportDate,
                    symbol: "tray.and.arrow.up"
                )
            }

            Section("Recent Sync Events") {
                if syncMonitor.recentEvents.isEmpty {
                    Text("No sync events captured yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(syncMonitor.recentEvents.prefix(20))) { record in
                        eventRow(record)
                    }
                }
            }
        }
        .navigationTitle("Sync Details")
    }

    private func transferTimestampRow(title: String, date: Date?, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if let date {
                Text(date, format: .dateTime.month().day().hour().minute().second())
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            } else {
                Text("Never")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func eventRow(_ record: SyncMonitor.EventRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Label(record.kind.rawValue, systemImage: symbol(for: record.kind))
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(outcomeLabel(for: record.outcome))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(outcomeColor(for: record.outcome))
            }

            Text(record.startedAt, format: .dateTime.month().day().hour().minute().second())
                .font(.caption)
                .foregroundStyle(.secondary)

            if let endedAt = record.endedAt {
                Text("Completed: \(endedAt.formatted(.dateTime.hour().minute().second()))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let detail = record.detail, detail.isEmpty == false {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func symbol(for kind: SyncMonitor.EventRecord.EventKind) -> String {
        switch kind {
        case .setup:
            return "gearshape.2"
        case .importData:
            return "tray.and.arrow.down"
        case .exportData:
            return "tray.and.arrow.up"
        case .unknown:
            return "icloud"
        }
    }

    private func outcomeLabel(for outcome: SyncMonitor.EventRecord.Outcome) -> String {
        switch outcome {
        case .inProgress:
            return "In progress"
        case .success:
            return "Success"
        case .failure:
            return "Failed"
        }
    }

    private func outcomeColor(for outcome: SyncMonitor.EventRecord.Outcome) -> Color {
        switch outcome {
        case .inProgress:
            return .orange
        case .success:
            return .green
        case .failure:
            return .red
        }
    }
}
