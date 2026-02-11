import SwiftUI

struct SettingsView: View {
    @Environment(TimerManager.self) private var timerManager

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

            Section("How It Works") {
                Text("Grind time adds money to your ledger. Chill time subtracts money.")
                Text("Streaks are calendar-based and recalculate automatically after midnight.")
            }
        }
        .navigationTitle("Settings")
        .onChange(of: usdPerHourRaw) { _, newValue in
            usdPerHourRaw = viewModel.normalizedUSDPerHour(newValue)
        }
    }
}
