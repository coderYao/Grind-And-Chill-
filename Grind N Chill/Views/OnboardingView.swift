import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: OnboardingViewModel
    let onComplete: (Double) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Grind N Chill")
                        .font(.largeTitle.bold())
                    Text("Turn your focused time into a ledger. Keep chill spending intentional.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Form {
                    Section("Ledger Rate") {
                        HStack {
                            Text("USD per Hour")
                            Spacer()
                            TextField(
                                "USD per Hour",
                                value: $viewModel.desiredUSDPerHour,
                                format: .number.precision(.fractionLength(2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 110)
                        }

                        Text("Used for every entry: (minutes/60) × rate × category multiplier")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Starter Setup") {
                        Toggle("Create starter categories", isOn: $viewModel.includeStarterCategories)
                        Text("Includes Deep Work, Reading, and Gaming Relapse.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let error = viewModel.latestError {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Button("Get Started") {
                    if viewModel.complete(modelContext: modelContext) {
                        onComplete(viewModel.desiredUSDPerHour)
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding()
            .navigationBarBackButtonHidden(true)
            .interactiveDismissDisabled()
        }
    }
}
