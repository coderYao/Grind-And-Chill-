import SwiftUI
import SwiftData

struct CategoryListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(TimerManager.self) private var timerManager

    @Query(sort: \Category.title) private var categories: [Category]

    @State private var viewModel = CategoriesViewModel()

    var body: some View {
        List {
            if let status = viewModel.latestStatus {
                Section {
                    Text(status)
                        .foregroundStyle(.green)
                }
            }

            if let error = viewModel.latestError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                }
            }

            if viewModel.canUndoLastDeletion {
                Section {
                    Button {
                        viewModel.undoLastDeletedCategories(in: modelContext)
                    } label: {
                        Label("Undo Last Delete", systemImage: "arrow.uturn.backward")
                    }
                    .accessibilityIdentifier("categories.undoDelete")
                }
            }

            Section("Your Categories") {
                if categories.isEmpty {
                    Text("No categories yet.")
                        .foregroundStyle(.secondary)
                }

                ForEach(categories) { category in
                    Button {
                        viewModel.beginEditing(category)
                    } label: {
                        HStack(spacing: 12) {
                            CategoryIconView(
                                iconName: category.resolvedSymbolName,
                                color: category.resolvedIconColor.swiftUIColor
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                    .font(.headline)
                                Text("\(viewModel.conversionSummary(for: category)) • \(viewModel.goalSummary(for: category))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(category.resolvedType.displayTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { offsets in
                    viewModel.deleteCategories(
                        at: offsets,
                        from: categories,
                        modelContext: modelContext,
                        activeCategoryID: timerManager.activeCategoryID
                    )
                }
            }
        }
        .navigationTitle("Categories")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.beginCreating()
                } label: {
                    Label("Add", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $viewModel.isPresentingEditorSheet) {
            CategoryEditorSheet(
                viewModel: viewModel,
                existingCategories: categories,
                sheetTitle: viewModel.editorSheetTitle
            )
            .presentationDetents([.medium, .large])
        }
    }
}

private struct CategoryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var viewModel: CategoriesViewModel
    let existingCategories: [Category]
    let sheetTitle: String

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $viewModel.title)
                        .accessibilityIdentifier("categoryEditor.title")

                    Picker("Type", selection: $viewModel.type) {
                        ForEach(CategoryType.allCases) { type in
                            Label(type.displayTitle, systemImage: type.symbolName)
                                .tag(type)
                        }
                    }
                    .accessibilityIdentifier("categoryEditor.type")

                    Picker("Unit", selection: $viewModel.unit) {
                        ForEach(CategoryUnit.allCases) { unit in
                            Text(unit.displayTitle)
                                .tag(unit)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("categoryEditor.unit")
                }

                Section("Icon") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                        spacing: 10
                    ) {
                        ForEach(viewModel.symbolOptions(), id: \.self) { symbol in
                            Button {
                                viewModel.symbolName = symbol
                            } label: {
                                CategoryIconView(
                                    iconName: symbol,
                                    color: viewModel.iconColor.swiftUIColor,
                                    font: .title3
                                )
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(
                                                viewModel.symbolName == symbol ? viewModel.iconColor.swiftUIColor : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(symbol)
                        }
                    }
                    .accessibilityIdentifier("categoryEditor.iconGrid")
                }

                Section("Icon Color") {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                        spacing: 10
                    ) {
                        ForEach(CategoryIconColor.allCases) { color in
                            Button {
                                viewModel.iconColor = color
                            } label: {
                                Circle()
                                    .fill(color.swiftUIColor)
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .stroke(Color(.systemBackground), lineWidth: 2)
                                    )
                                    .overlay(
                                        Circle()
                                            .stroke(
                                                viewModel.iconColor == color ? Color.primary : Color.clear,
                                                lineWidth: 2
                                            )
                                            .padding(-3)
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 36)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.rawValue.capitalized)
                        }
                    }
                    .accessibilityIdentifier("categoryEditor.iconColorGrid")
                }

                Section("Ledger Conversion") {
                    switch viewModel.unit {
                    case .time:
                        Picker("Time Conversion", selection: $viewModel.timeConversionMode) {
                            ForEach(TimeConversionMode.allCases) { mode in
                                Text(mode.displayTitle)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("categoryEditor.timeConversion")

                        switch viewModel.timeConversionMode {
                        case .multiplier:
                            HStack {
                                Text("Multiplier")
                                Spacer()
                                TextField(
                                    "Multiplier",
                                    value: $viewModel.multiplier,
                                    format: .number.precision(.fractionLength(2))
                                )
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 90)
                                .accessibilityIdentifier("categoryEditor.multiplier")
                            }
                        case .hourlyRate:
                            HStack {
                                Text("Rate per Hour")
                                Spacer()
                                TextField(
                                    "USD/hour",
                                    value: $viewModel.hourlyRateUSD,
                                    format: .number.precision(.fractionLength(2))
                                )
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.decimalPad)
                                .frame(width: 110)
                                .accessibilityIdentifier("categoryEditor.rate")
                            }
                        }
                    case .count:
                        HStack {
                            Text("Value per Count")
                            Spacer()
                            TextField(
                                "USD/count",
                                value: $viewModel.usdPerCount,
                                format: .number.precision(.fractionLength(2))
                            )
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.decimalPad)
                            .frame(width: 110)
                            .accessibilityIdentifier("categoryEditor.usdPerCount")
                        }
                    case .money:
                        Text("Money categories log direct USD entries.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Goal") {
                    Stepper(value: $viewModel.dailyGoalMinutes, in: viewModel.dailyGoalRange()) {
                        Text(viewModel.dailyGoalLabel())
                    }
                    .disabled(viewModel.streakEnabled == false)
                }

                Section("Streak & Badges") {
                    Toggle("Track Streak", isOn: $viewModel.streakEnabled)
                        .accessibilityIdentifier("categoryEditor.streakEnabled")

                    if viewModel.streakEnabled {
                        Picker("Cadence", selection: $viewModel.streakCadence) {
                            ForEach(StreakCadence.allCases) { cadence in
                                Text(cadence.displayTitle)
                                    .tag(cadence)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("categoryEditor.streakCadence")

                        Toggle("Award Badges", isOn: $viewModel.badgeEnabled)
                            .accessibilityIdentifier("categoryEditor.badgeEnabled")

                        Toggle("Give Streak Bonus", isOn: $viewModel.streakBonusEnabled)
                            .accessibilityIdentifier("categoryEditor.streakBonusEnabled")

                        if viewModel.streakBonusEnabled {
                            let milestones = viewModel.rewardMilestonesPreview()

                            if milestones.isEmpty {
                                Text("Set milestones to configure streak bonus amounts.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            ForEach(milestones, id: \.self) { milestone in
                                HStack {
                                    Text(viewModel.streakBonusLabel(for: milestone))
                                    Spacer()
                                    TextField(
                                        "USD",
                                        value: Binding(
                                            get: { viewModel.streakBonusAmount(for: milestone) },
                                            set: { viewModel.setStreakBonusAmount($0, for: milestone) }
                                        ),
                                        format: .number.precision(.fractionLength(2))
                                    )
                                    .multilineTextAlignment(.trailing)
                                    .keyboardType(.decimalPad)
                                    .frame(width: 90)
                                    .accessibilityIdentifier("categoryEditor.streakBonusAmount.\(milestone)")
                                }
                            }
                        }

                        if viewModel.badgeEnabled || viewModel.streakBonusEnabled {
                            TextField(viewModel.streakMilestonesFieldLabel(), text: $viewModel.badgeMilestonesInput)
                                .keyboardType(.numbersAndPunctuation)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .accessibilityIdentifier("categoryEditor.badgeMilestones")

                            Text(viewModel.streakMilestonesHelperText())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Streak tracking is disabled for this category.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = viewModel.latestError {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(sheetTitle)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        viewModel.cancelCategoryEditing()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        if viewModel.saveCategory(in: modelContext, existingCategories: existingCategories) {
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
