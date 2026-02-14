import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Entry.timestamp, order: .reverse) private var entries: [Entry]
    @AppStorage(AppStorageKeys.usdPerHour) private var usdPerHourRaw: Double = 18

    @State private var viewModel = HistoryViewModel()
    @State private var exportDocument: HistoryExportDocument?
    @State private var exportFilename = "grind-n-chill-history.csv"
    @State private var exportContentType: UTType = .commaSeparatedText
    @State private var isPresentingExporter = false
    @State private var isPresentingImporter = false
    @State private var isShowingImportPreview = false
    @State private var isShowingUndoConfirmation = false
    @State private var pendingImportData: Data?
    @State private var pendingImportPreview: HistoryImportService.PreviewReport?
    @State private var editingDraft: HistoryViewModel.ManualEntryDraft?

    var body: some View {
        let filtered = viewModel.filteredEntries(from: entries)
        let dailySummaries = viewModel.dailySummaries(from: filtered)
        let chartPoints = viewModel.chartPoints(from: dailySummaries)

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

            Section {
                Toggle("Manual entries only", isOn: $viewModel.showManualOnly)

                Picker("Date Range", selection: $viewModel.dateRangeFilter) {
                    ForEach(HistoryViewModel.DateRangeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.showsCustomDateRange {
                    DatePicker(
                        "From",
                        selection: $viewModel.customStartDate,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "To",
                        selection: $viewModel.customEndDate,
                        displayedComponents: .date
                    )
                }
            }

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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Export Daily CSV") {
                        exportDailyCSV(dailySummaries)
                    }

                    Button("Export Full JSON") {
                        exportJSON(dailySummaries)
                    }

                    Button("Import JSON") {
                        isPresentingImporter = true
                    }

                    if viewModel.canUndoLastImport {
                        Button("Undo Last Import", role: .destructive) {
                            isShowingUndoConfirmation = true
                        }
                    }

                    if viewModel.canUndoLastDelete {
                        Button("Undo Last Delete") {
                            viewModel.undoLastDelete(modelContext: modelContext)
                        }
                    }
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            switch result {
            case .success:
                viewModel.latestError = nil
            case .failure(let error):
                viewModel.latestError = "Could not export history: \(error.localizedDescription)"
            }
        }
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.json, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else {
                    viewModel.latestStatus = nil
                    viewModel.latestError = "No file was selected."
                    return
                }
                prepareImportPreview(from: url)
            case let .failure(error):
                viewModel.latestStatus = nil
                viewModel.latestError = "Could not open import file: \(error.localizedDescription)"
            }
        }
        .alert(
            "Import Preview",
            isPresented: $isShowingImportPreview,
            presenting: pendingImportPreview
        ) { preview in
            Button("Cancel", role: .cancel) {
                clearPendingImportPreview()
            }

            if preview.entriesToUpdate > 0 {
                Button("Replace Existing") {
                    runImport(using: .replaceExisting)
                }
                Button("Keep Existing") {
                    runImport(using: .keepExisting)
                }
            } else {
                Button("Import") {
                    runImport(using: .replaceExisting)
                }
            }
        } message: { preview in
            Text(importPreviewMessage(preview))
        }
        .alert("Undo Last Import?", isPresented: $isShowingUndoConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Undo", role: .destructive) {
                viewModel.undoLastImport(modelContext: modelContext)
            }
        } message: {
            Text("This will revert the most recent imported changes.")
        }
        .sheet(item: $editingDraft) { draft in
            HistoryManualEntryEditorSheet(
                draft: draft,
                onCancel: {
                    editingDraft = nil
                },
                onSave: { updatedDraft in
                    let rate = Decimal(string: String(usdPerHourRaw)) ?? Decimal(usdPerHourRaw)
                    let saved = viewModel.saveManualEdit(
                        updatedDraft,
                        entries: entries,
                        modelContext: modelContext,
                        usdPerHour: rate
                    )
                    if saved {
                        editingDraft = nil
                    }
                }
            )
        }
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
        let symbolName = entry.category?.resolvedSymbolName ?? "tray"
        let iconColor = entry.category?.resolvedIconColor.swiftUIColor ?? Color.secondary
        let title = entry.category?.title ?? "Unknown Category"

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 6) {
                    CategoryIconView(iconName: symbolName, color: iconColor)
                    Text(title)
                }
                .font(.headline)
                Spacer()
                Text(entry.amountUSD, format: .currency(code: "USD"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(entry.amountUSD < .zeroValue ? .red : .green)
            }

            if entry.isManual, let draft = viewModel.manualDraft(for: entry) {
                HStack {
                    Spacer()
                    Button("Edit Manual Entry") {
                        editingDraft = draft
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("history.editManual")
                }
            }

            Text(viewModel.subtitle(for: entry))
                .font(.subheadline)

            Text(entry.timestamp, format: .dateTime.month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func exportDailyCSV(_ summaries: [HistoryViewModel.DailySummary]) {
        let csv = viewModel.dailySummaryCSV(from: summaries)
        exportDocument = HistoryExportDocument(text: csv)
        exportFilename = viewModel.exportFilename(extension: "csv")
        exportContentType = .commaSeparatedText
        isPresentingExporter = true
    }

    private func exportJSON(_ summaries: [HistoryViewModel.DailySummary]) {
        do {
            let json = try viewModel.exportJSON(
                from: summaries,
                manualOnlyFilter: viewModel.showManualOnly,
                dateRangeFilter: viewModel.dateRangeFilter
            )
            exportDocument = HistoryExportDocument(text: json)
            exportFilename = viewModel.exportFilename(extension: "json")
            exportContentType = .json
            isPresentingExporter = true
            viewModel.latestStatus = nil
            viewModel.latestError = nil
        } catch {
            viewModel.latestStatus = nil
            viewModel.latestError = "Could not encode history export: \(error.localizedDescription)"
        }
    }

    private func prepareImportPreview(from url: URL) {
        let didAccessScopedResource = url.startAccessingSecurityScopedResource()
        defer {
            if didAccessScopedResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: url)
            guard let preview = viewModel.previewImportJSONData(data, modelContext: modelContext) else {
                clearPendingImportPreview()
                return
            }

            pendingImportData = data
            pendingImportPreview = preview
            isShowingImportPreview = true
        } catch {
            clearPendingImportPreview()
            viewModel.latestStatus = nil
            viewModel.latestError = "Could not read import file: \(error.localizedDescription)"
        }
    }

    private func clearPendingImportPreview() {
        pendingImportData = nil
        pendingImportPreview = nil
    }

    private func runImport(using conflictPolicy: HistoryImportService.ConflictPolicy) {
        guard let data = pendingImportData else {
            viewModel.latestStatus = nil
            viewModel.latestError = "Import data is no longer available."
            clearPendingImportPreview()
            return
        }

        viewModel.importJSONData(
            data,
            modelContext: modelContext,
            conflictPolicy: conflictPolicy
        )
        clearPendingImportPreview()
    }

    private func importPreviewMessage(_ preview: HistoryImportService.PreviewReport) -> String {
        if preview.hasChanges == false, preview.skippedEntries == 0 {
            return "No changes detected in the selected file."
        }

        let summary = """
        Create entries: \(preview.entriesToCreate)
        Update entries: \(preview.entriesToUpdate)
        Create categories: \(preview.categoriesToCreate)
        Skipped items: \(preview.skippedEntries)
        """

        if preview.entriesToUpdate > 0 {
            return "\(summary)\nChoose how to resolve entry ID conflicts. Category creation count assumes Replace Existing."
        }

        return "\(summary)\nContinue with import?"
    }
}

private struct HistoryManualEntryEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: HistoryViewModel.ManualEntryDraft
    let onCancel: () -> Void
    let onSave: (HistoryViewModel.ManualEntryDraft) -> Void

    init(
        draft: HistoryViewModel.ManualEntryDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (HistoryViewModel.ManualEntryDraft) -> Void
    ) {
        _draft = State(initialValue: draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Text(draft.categoryTitle)
                    Text(draft.categoryType.displayTitle)
                        .foregroundStyle(.secondary)
                }

                Section("Amount") {
                    switch draft.unit {
                    case .time:
                        Stepper(value: $draft.durationMinutes, in: 1 ... 1_440) {
                            Text("Duration: \(draft.durationMinutes) minutes")
                        }
                        .accessibilityIdentifier("history.edit.duration")
                    case .count:
                        HStack {
                            Text("Count")
                            Spacer()
                            TextField(
                                "Count",
                                value: $draft.countInput,
                                format: .number.precision(.fractionLength(0 ... 2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .accessibilityIdentifier("history.edit.count")
                        }
                    case .money:
                        HStack {
                            Text("Amount (USD)")
                            Spacer()
                            TextField(
                                "Amount",
                                value: $draft.amountInput,
                                format: .number.precision(.fractionLength(0 ... 2))
                            )
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                            .accessibilityIdentifier("history.edit.amount")
                        }
                    }
                }

                Section("Note") {
                    TextField("Note", text: $draft.note, axis: .vertical)
                        .accessibilityIdentifier("history.edit.note")
                }
            }
            .navigationTitle("Edit Manual Entry")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(draft)
                    }
                }
            }
        }
    }
}

private struct HistoryExportDocument: FileDocument {
    static var readableContentTypes: [UTType] {
        [.plainText, .commaSeparatedText, .json]
    }

    let text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        if let data = configuration.file.regularFileContents,
           let value = String(data: data, encoding: .utf8) {
            text = value
        } else {
            text = ""
        }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
