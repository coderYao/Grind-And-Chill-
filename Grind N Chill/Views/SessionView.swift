import SwiftUI
import SwiftData

struct SessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerManager.self) private var timerManager

    @Query(sort: \Category.title) private var categories: [Category]
    @Query(sort: \Entry.timestamp, order: .reverse) private var entries: [Entry]

    @AppStorage(AppStorageKeys.usdPerHour) private var usdPerHourRaw: Double = 18

    @State private var viewModel = SessionViewModel()
    @State private var settingsViewModel = SettingsViewModel()

    private var selectedCategory: Category? {
        categories.first(where: { $0.id == viewModel.selectedCategoryID })
    }

    var body: some View {
        Form {
            categoryPickerSection
            timerSection
            manualSection
            feedbackSection
        }
        .navigationTitle("Session")
        .onAppear {
            viewModel.ensureCategorySelection(
                from: categories,
                runningCategoryID: timerManager.activeCategoryID
            )
        }
        .onChange(of: categories.map(\.id), initial: false) { _, _ in
            viewModel.ensureCategorySelection(
                from: categories,
                runningCategoryID: timerManager.activeCategoryID
            )
        }
        .onChange(of: timerManager.activeCategoryID, initial: false) { _, _ in
            viewModel.ensureCategorySelection(
                from: categories,
                runningCategoryID: timerManager.activeCategoryID
            )
        }
    }

    private var categoryPickerSection: some View {
        Section("Category") {
            if categories.isEmpty {
                Text("Create a category in the Categories tab first.")
                    .foregroundStyle(.secondary)
            } else {
                @Bindable var bindableViewModel = viewModel

                Picker("Track", selection: $bindableViewModel.selectedCategoryID) {
                    ForEach(categories) { category in
                        HStack(spacing: 8) {
                            Image(systemName: category.resolvedSymbolName)
                                .foregroundStyle(category.resolvedIconColor.swiftUIColor)
                            Text(category.title)
                        }
                            .tag(Optional(category.id))
                    }
                }
                .accessibilityIdentifier("session.track")
            }
        }
    }

    private var timerSection: some View {
        Section("Live Timer") {
            if timerManager.isRunning {
                Text(viewModel.categoryTitle(for: categories, id: timerManager.activeCategoryID))
                    .font(.headline)

                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    Text(formattedDuration(timerManager.elapsedSeconds(at: context.date)))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }

                @Bindable var bindableViewModel = viewModel
                TextField("Session note", text: $bindableViewModel.sessionNote, axis: .vertical)

                Button("Stop & Save") {
                    viewModel.stopSession(
                        with: timerManager,
                        categories: categories,
                        existingEntries: entries,
                        modelContext: modelContext,
                        usdPerHour: settingsViewModel.asDecimal(usdPerHourRaw)
                    )
                }
                .accessibilityIdentifier("session.stopSave")
                .buttonStyle(.borderedProminent)
            } else {
                if selectedCategory?.resolvedUnit != .time {
                    Text("Live timer is available for Time categories only.")
                        .foregroundStyle(.secondary)
                }

                Button("Start Session") {
                    viewModel.startSession(with: timerManager, categories: categories)
                }
                .accessibilityIdentifier("session.start")
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedCategoryID == nil || selectedCategory?.resolvedUnit != .time)
            }
        }
    }

    private var manualSection: some View {
        Section("Manual Entry") {
            @Bindable var bindableViewModel = viewModel

            if let selectedCategory {
                switch selectedCategory.resolvedUnit {
                case .time:
                    Stepper(value: $bindableViewModel.manualMinutes, in: 1 ... 600) {
                        Text("Duration: \(viewModel.manualMinutes) minutes")
                    }
                case .count:
                    Stepper(value: $bindableViewModel.manualCount, in: 1 ... 500) {
                        Text("Count: \(viewModel.manualCount)")
                    }
                case .money:
                    HStack {
                        Text("Amount (USD)")
                        Spacer()
                        TextField(
                            "Amount",
                            value: $bindableViewModel.manualAmountUSD,
                            format: .number.precision(.fractionLength(2))
                        )
                        .accessibilityIdentifier("session.manualAmount")
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 120)
                    }
                }
            } else {
                Text("Pick a category to log a manual entry.")
                    .foregroundStyle(.secondary)
            }

            TextField("Manual note", text: $bindableViewModel.manualNote, axis: .vertical)

            Button("Save Manual Entry") {
                viewModel.addManualEntry(
                    categories: categories,
                    existingEntries: entries,
                    modelContext: modelContext,
                    usdPerHour: settingsViewModel.asDecimal(usdPerHourRaw)
                )
            }
            .accessibilityIdentifier("session.saveManual")
            .disabled(viewModel.selectedCategoryID == nil)
        }
    }

    private var feedbackSection: some View {
        Section {
            if let status = viewModel.latestStatus {
                Text(status)
                    .foregroundStyle(.green)
            }

            if let error = viewModel.latestError {
                Text(error)
                    .foregroundStyle(.red)
            }
        }
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
