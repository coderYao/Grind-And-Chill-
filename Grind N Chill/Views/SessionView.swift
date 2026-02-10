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
        .onChange(of: categories.map(\.id)) { _, _ in
            viewModel.ensureCategorySelection(
                from: categories,
                runningCategoryID: timerManager.activeCategoryID
            )
        }
        .onChange(of: timerManager.activeCategoryID) { _, _ in
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
                        Label(category.title, systemImage: category.resolvedSymbolName)
                            .tag(Optional(category.id))
                    }
                }
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
                .buttonStyle(.borderedProminent)
            } else {
                Button("Start Session") {
                    viewModel.startSession(with: timerManager)
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.selectedCategoryID == nil)
            }
        }
    }

    private var manualSection: some View {
        Section("Manual Entry") {
            @Bindable var bindableViewModel = viewModel

            Stepper(value: $bindableViewModel.manualMinutes, in: 1 ... 600) {
                Text("Duration: \(viewModel.manualMinutes) minutes")
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
