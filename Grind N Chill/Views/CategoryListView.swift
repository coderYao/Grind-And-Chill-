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
                            Image(systemName: category.resolvedSymbolName)
                                .foregroundStyle(category.resolvedType == .goodHabit ? .green : .orange)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.title)
                                    .font(.headline)
                                Text("Multiplier \(category.multiplier, specifier: "%.2f") • Goal \(category.dailyGoalMinutes)m")
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
            .presentationDetents([.medium])
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

                    Picker("Type", selection: $viewModel.type) {
                        ForEach(CategoryType.allCases) { type in
                            Label(type.displayTitle, systemImage: type.symbolName)
                                .tag(type)
                        }
                    }

                    Picker("Icon", selection: $viewModel.symbolName) {
                        ForEach(viewModel.symbolOptions(), id: \.self) { symbol in
                            Label(symbol, systemImage: symbol)
                                .tag(symbol)
                        }
                    }

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
                    }

                    Stepper(value: $viewModel.dailyGoalMinutes, in: 0 ... 600) {
                        Text("Daily Goal: \(viewModel.dailyGoalMinutes)m")
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
