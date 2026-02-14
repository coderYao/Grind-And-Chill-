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

    private var activeSessionCategory: Category? {
        categories.first(where: { $0.id == timerManager.activeCategoryID })
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
                            CategoryIconView(
                                iconName: category.resolvedSymbolName,
                                color: category.resolvedIconColor.swiftUIColor
                            )
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
                timerDisplayView

                @Bindable var bindableViewModel = viewModel
                TextField("Session note", text: $bindableViewModel.sessionNote, axis: .vertical)

                HStack {
                    if timerManager.isPaused {
                        Button("Resume") {
                            viewModel.resumeSession(with: timerManager)
                        }
                        .accessibilityIdentifier("session.resume")
                        .buttonStyle(.bordered)
                    } else {
                        Button("Pause") {
                            viewModel.pauseSession(with: timerManager)
                        }
                        .accessibilityIdentifier("session.pause")
                        .buttonStyle(.bordered)
                    }

                    Spacer()

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
                }
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

    @ViewBuilder
    private var timerDisplayView: some View {
        if timerManager.isPaused {
            let elapsedSeconds = timerManager.elapsedSeconds()
            let liveAmount = viewModel.liveAmountUSD(
                for: activeSessionCategory,
                elapsedSeconds: elapsedSeconds,
                usdPerHour: settingsViewModel.asDecimal(usdPerHourRaw)
            ) ?? .zeroValue

            VStack(spacing: 6) {
                Text("Paused")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(formattedDuration(elapsedSeconds))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(liveAmount, format: .currency(code: "USD"))
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(liveAmount < .zeroValue ? .red : .green)
                    .accessibilityIdentifier("session.liveAmount")
            }
        } else {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let elapsedSeconds = timerManager.elapsedSeconds(at: context.date)
                let liveAmount = viewModel.liveAmountUSD(
                    for: activeSessionCategory,
                    elapsedSeconds: elapsedSeconds,
                    usdPerHour: settingsViewModel.asDecimal(usdPerHourRaw)
                ) ?? .zeroValue

                VStack(spacing: 6) {
                    Text(formattedDuration(elapsedSeconds))
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text(liveAmount, format: .currency(code: "USD"))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(liveAmount < .zeroValue ? .red : .green)
                        .accessibilityIdentifier("session.liveAmount")
                }
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

                    quickActionRow(title: "Quick add") {
                        Button("+1") {
                            viewModel.incrementManualCount(by: 1)
                        }
                        .accessibilityIdentifier("session.quickCount.1")

                        Button("+5") {
                            viewModel.incrementManualCount(by: 5)
                        }
                        .accessibilityIdentifier("session.quickCount.5")

                        Button("+10") {
                            viewModel.incrementManualCount(by: 10)
                        }
                        .accessibilityIdentifier("session.quickCount.10")
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

                    quickActionRow(title: "Quick add") {
                        Button("+$1") {
                            viewModel.incrementManualAmount(by: Decimal(1))
                        }
                        .accessibilityIdentifier("session.quickAmount.1")

                        Button("+$5") {
                            viewModel.incrementManualAmount(by: Decimal(5))
                        }
                        .accessibilityIdentifier("session.quickAmount.5")

                        Button("+$10") {
                            viewModel.incrementManualAmount(by: Decimal(10))
                        }
                        .accessibilityIdentifier("session.quickAmount.10")
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

    private func quickActionRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            content()
                .buttonStyle(.bordered)
                .font(.caption.weight(.semibold))
        }
    }
}
