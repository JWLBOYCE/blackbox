import SwiftUI
import UniformTypeIdentifiers
import OpenPilotLogbookCore

struct ImportView: View {
    @ObservedObject var store: LogbookStore
    @State private var showImporter = false
    @State private var showLogTenImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import")
                        .pageTitleStyle()
                    Text("Review extracted flights from PDF, screenshot, CSV, or text before saving.")
                        .foregroundStyle(OpenPilotTheme.muted)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        showLogTenImporter = true
                    } label: {
                        Label("Import LogTen Pro", systemImage: "tray.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("import.chooseLogTen")

                    Button {
                        showImporter = true
                    } label: {
                        Label("Choose Files", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("import.chooseDocuments")
                }
            }

            Panel("LogTen Pro Database", systemImage: "externaldrive.badge.plus") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose LogTenCoreDataStore.sql to create a read-only preview. Selecting a file never changes Blackbox.")
                        .font(.callout)
                    Text("The preview shows additions, changes, unchanged rows, duplicate identifiers, conflicts, and records absent from the source. Applying it preserves Blackbox-only records and creates a verified recovery backup.")
                        .font(.caption)
                        .foregroundStyle(OpenPilotTheme.muted)
                }
            }

            if let plan = store.pendingImportPlan { importPreview(plan) }

            Panel("Review Queue", systemImage: "doc.viewfinder") {
                HStack(spacing: 10) {
                    Button("Import Selected", action: store.acceptSelectedImports)
                        .buttonStyle(.borderedProminent)
                        .disabled(store.selectedImportIDs.isEmpty)
                        .accessibilityIdentifier("import.reviewSelected")
                    Button("Select All") {
                        store.selectedImportIDs = Set(store.importCandidates.map(\.id))
                    }
                    .buttonStyle(.bordered)
                    Button("Clear") {
                        store.importCandidates.removeAll()
                        store.selectedImportIDs.removeAll()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Text("\(store.importCandidates.count) candidates")
                        .font(.caption)
                        .foregroundStyle(OpenPilotTheme.muted)
                }

                Table(store.importCandidates, selection: $store.selectedImportIDs) {
                    TableColumn("Date") { item in Text(LogbookFormatters.dateFormatter.string(from: item.flight.date)) }
                    TableColumn("Route") { item in Text(item.flight.routeDisplay) }
                    TableColumn("Aircraft") { item in Text(item.flight.aircraftID) }
                    TableColumn("Total") { item in Text(LogbookFormatters.hours(item.flight.totalMinutes)).monospacedDigit() }
                    TableColumn("SIC Day") { item in Text(LogbookFormatters.hours(item.flight.copilotDayMinutes)).monospacedDigit() }
                    TableColumn("SIC Night") { item in Text(LogbookFormatters.hours(item.flight.copilotNightMinutes)).monospacedDigit() }
                    TableColumn("PAX") { item in Text("\(item.flight.passengerCount)").monospacedDigit() }
                    TableColumn("Confidence") { item in Text(String(format: "%.0f%%", item.confidence * 100)).monospacedDigit() }
                    TableColumn("Raw Text") { item in Text(item.rawText).lineLimit(1) }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("import.candidates")
            }
            }
            .padding(24)
        }
        .accessibilityIdentifier("import.scroll")
        .navigationTitle("Import")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.screen")
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .image, .plainText, .commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                store.importDocuments(urls: urls)
            case .failure(let error):
                store.statusMessage = "File selection failed: \(error)"
            }
        }
        .fileImporter(
            isPresented: $showLogTenImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else {
                    store.statusMessage = "No LogTen Pro database selected."
                    return
                }
                store.importLogTenDatabase(url: url)
            case .failure(let error):
                store.statusMessage = "LogTen Pro selection failed: \(error)"
            }
        }
    }

    private func importSelectionBinding(_ id: String) -> Binding<Bool> {
        Binding(get: {
            store.pendingImportPlan?.fieldSelections.first(where: { $0.id == id })?.decision == .include
        }, set: { included in
            guard let index = store.pendingImportPlan?.fieldSelections.firstIndex(where: { $0.id == id }) else { return }
            store.pendingImportPlan?.fieldSelections[index].decision = included ? .include : .exclude
        })
    }

    private func importPreview(_ plan: ImportPlan) -> some View {
        Panel(plan.sourceKind == .logTen ? "LogTen Import Preview" : "Document Import Preview", systemImage: "doc.text.magnifyingglass") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 10)], spacing: 10) {
                MetricTile(title: "Additions", value: plan.additions.count.formatted(), systemImage: "plus", tint: OpenPilotTheme.green)
                MetricTile(title: "Changes", value: plan.changes.count.formatted(), systemImage: "pencil", tint: OpenPilotTheme.amber)
                MetricTile(title: "Duplicates", value: plan.duplicateSourceIDs.count.formatted(), systemImage: "doc.on.doc", tint: OpenPilotTheme.amber)
                MetricTile(title: "Conflicts", value: plan.conflicts.count.formatted(), systemImage: "exclamationmark.octagon", tint: plan.conflicts.isEmpty ? OpenPilotTheme.green : OpenPilotTheme.red)
                MetricTile(title: "Unchanged", value: plan.unchangedCount.formatted(), systemImage: "equal", tint: OpenPilotTheme.cyan)
                    .accessibilityIdentifier("import.metric.unchanged")
                MetricTile(title: "Source-only omissions", value: plan.missingFromSourceCount.formatted(), systemImage: "minus", tint: OpenPilotTheme.blue)
            }

            Label("Blackbox-only records are preserved. Finalised matches can only produce amendment drafts; originals remain immutable.", systemImage: "lock.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            additionsSection(plan)
            changesSection(plan)
            duplicatesSection(plan)
            conflictsSection(plan)
            unchangedSection(plan)
            sourceOnlyOmissionsSection(plan)

            HStack {
                Button("Cancel Preview", action: store.cancelPendingImport)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("import.cancel")
                Button("Back Up & Apply Import", action: store.applyPendingImport)
                    .buttonStyle(.borderedProminent)
                    .disabled(!plan.isApplicable || hasBlockingConflicts(in: plan) || !store.planHasSelectedChanges(plan))
                    .accessibilityIdentifier("import.apply")
                Spacer()
                Text(previewReadiness(plan))
                    .font(.caption)
                    .foregroundStyle(plan.isApplicable && !hasBlockingConflicts(in: plan) && store.planHasSelectedChanges(plan) ? .secondary : OpenPilotTheme.red)
            }
            Button("View Operation History") { store.showHistory() }
                .buttonStyle(.link)
                .accessibilityIdentifier("import.viewHistory")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.preview")
    }

    @ViewBuilder
    private func additionsSection(_ plan: ImportPlan) -> some View {
        if !plan.additions.isEmpty {
            DisclosureGroup("Additions (\(plan.additions.count))") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(plan.additions.enumerated()), id: \.offset) { _, flight in
                        let sourcePK = flight.sourcePK
                        let requiresResolution = sourcePK.map {
                            plan.duplicateSourceIDs.contains($0) || plan.conflictSourceIDs.contains($0)
                        } ?? false
                        DisclosureGroup {
                            if let sourcePK {
                                HStack {
                                    Text("Choose every field that will be written to the new draft.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Select All") { setFieldDecisions(sourcePK: sourcePK, decision: .include) }
                                        .buttonStyle(.link)
                                    Button("Select None") { setFieldDecisions(sourcePK: sourcePK, decision: .exclude) }
                                        .buttonStyle(.link)
                                }
                                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                                    GridRow {
                                        Text("Include")
                                        Text("Field")
                                        Text("Source value")
                                    }
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    ForEach(plan.fieldSelections.filter { $0.sourcePK == sourcePK }) { selection in
                                        GridRow {
                                            Toggle("Include \(selection.field)", isOn: importSelectionBinding(selection.id))
                                                .labelsHidden()
                                                .toggleStyle(.checkbox)
                                                .accessibilityLabel("Include \(selection.field)")
                                                .accessibilityIdentifier("import.field.\(sourcePK).\(selection.field.accessibilityIdentifierComponent)")
                                            Text(selection.field)
                                            Text(selection.sourceValue.isEmpty ? "—" : selection.sourceValue)
                                        }
                                        .font(.caption)
                                    }
                                }
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("import.addition.fields.\(sourcePK)")
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Toggle("Include", isOn: resultingActionBinding(sourcePK: sourcePK, includedAction: .createDraft))
                                    .toggleStyle(.checkbox)
                                    .disabled(sourcePK == nil || requiresResolution)
                                Text(sourcePK.map { "Source \($0)" } ?? "Unidentified source")
                                    .monospacedDigit()
                                Text(flight.routeDisplay.isEmpty ? "No route" : flight.routeDisplay)
                                Spacer()
                                if requiresResolution, sourcePK.flatMap({ plan.resolutionActions[$0] }) == nil {
                                    Label("Decision required", systemImage: "questionmark.diamond")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(OpenPilotTheme.amber)
                                } else {
                                    ImportActionLabel(action: action(for: sourcePK, in: plan))
                                }
                            }
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier(sourcePK.map { "import.addition.\($0)" } ?? "import.addition.unknown")
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func changesSection(_ plan: ImportPlan) -> some View {
        if !plan.changes.isEmpty {
            DisclosureGroup("Matched changes (\(plan.changes.count))") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.changes) { change in
                        let recommended = recommendedAction(for: change.existing.recordState)
                        let requiresResolution = plan.duplicateSourceIDs.contains(change.sourcePK) || plan.conflictSourceIDs.contains(change.sourcePK)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 10) {
                                Toggle("Include record", isOn: resultingActionBinding(sourcePK: change.sourcePK, includedAction: recommended))
                                    .toggleStyle(.checkbox)
                                    .disabled(requiresResolution)
                                Text("Source \(change.sourcePK)").monospacedDigit()
                                Text(change.existing.routeDisplay.isEmpty ? "No route" : change.existing.routeDisplay)
                                Spacer()
                                if requiresResolution, plan.resolutionActions[change.sourcePK] == nil {
                                    Label("Decision required", systemImage: "questionmark.diamond")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(OpenPilotTheme.amber)
                                } else {
                                    ImportActionLabel(action: action(for: change.sourcePK, in: plan))
                                }
                            }
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 7) {
                                GridRow {
                                    Text("Field")
                                    Text("Blackbox")
                                    Text("Source")
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                                ForEach(plan.fieldSelections.filter { $0.sourcePK == change.sourcePK }) { selection in
                                    GridRow {
                                        Toggle(selection.field, isOn: importSelectionBinding(selection.id))
                                            .toggleStyle(.checkbox)
                                            .accessibilityIdentifier("import.field.\(change.sourcePK).\(selection.field.accessibilityIdentifierComponent)")
                                        Text(selection.blackboxValue.isEmpty ? "—" : selection.blackboxValue)
                                            .foregroundStyle(.secondary)
                                        Text(selection.sourceValue.isEmpty ? "—" : selection.sourceValue)
                                    }
                                    .font(.caption)
                                }
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("import.change.\(change.sourcePK)")
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func duplicatesSection(_ plan: ImportPlan) -> some View {
        if !plan.duplicateSourceIDs.isEmpty {
            DisclosureGroup("Duplicates requiring a decision (\(plan.duplicateSourceIDs.count))") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose the exact result for each duplicate. Nothing is inferred from an identifier or matching row.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(plan.duplicateSourceIDs, id: \.self) { sourcePK in
                        HStack {
                            Text("Source \(sourcePK)").monospacedDigit()
                            Spacer()
                            Picker("Duplicate decision", selection: resolutionActionBinding(sourcePK)) {
                                Text("Decision required").tag(ImportResultingAction?.none)
                                ForEach(validResolutionActions(sourcePK: sourcePK, plan: plan), id: \.rawValue) { action in
                                    Text(ImportActionLabel.title(for: action)).tag(ImportResultingAction?.some(action))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 250)
                            .accessibilityIdentifier("import.duplicate.\(sourcePK)")
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func conflictsSection(_ plan: ImportPlan) -> some View {
        if !plan.conflicts.isEmpty {
            DisclosureGroup("Conflicts requiring review (\(plan.conflicts.count))") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(plan.conflicts, id: \.self) { conflict in
                        Label(conflict, systemImage: "exclamationmark.octagon")
                            .foregroundStyle(OpenPilotTheme.red)
                    }

                    ForEach(plan.conflictSourceIDs.filter { !plan.duplicateSourceIDs.contains($0) }, id: \.self) { sourcePK in
                        HStack {
                            Text("Source \(sourcePK)").monospacedDigit()
                            Spacer()
                            Picker("Conflict decision", selection: resolutionActionBinding(sourcePK)) {
                                Text("Decision required").tag(ImportResultingAction?.none)
                                ForEach(validResolutionActions(sourcePK: sourcePK, plan: plan), id: \.rawValue) { action in
                                    Text(ImportActionLabel.title(for: action)).tag(ImportResultingAction?.some(action))
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: 250)
                            .accessibilityIdentifier("import.conflict.\(sourcePK)")
                        }
                    }

                    Text(hasBlockingConflicts(in: plan)
                         ? "At least one conflict cannot be tied to a source record. Choose a corrected source copy and create a new preview."
                         : "Choose the exact result for every source above. Blackbox will apply only those explicit decisions and selected fields.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            }
        }
    }

    private func unchangedSection(_ plan: ImportPlan) -> some View {
        DisclosureGroup("Unchanged records (\(plan.unchangedCount))") {
            VStack(alignment: .leading, spacing: 8) {
                if plan.unchangedCount == 0 {
                    Label("No source records match Blackbox field for field.", systemImage: "equal.circle")
                } else {
                    Label(
                        "\(plan.unchangedCount) source \(plan.unchangedCount == 1 ? "record already matches" : "records already match") Blackbox.",
                        systemImage: "equal.circle.fill"
                    )
                    Text("Unchanged records are linked and skipped. They will not be rewritten or added again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.unchanged")
    }

    private func sourceOnlyOmissionsSection(_ plan: ImportPlan) -> some View {
        DisclosureGroup("Source-only omissions (\(plan.missingFromSourceCount))") {
            VStack(alignment: .leading, spacing: 8) {
                if plan.missingFromSourceCount == 0 {
                    Label("No existing source-linked Blackbox records are absent from this source.", systemImage: "checkmark.circle")
                } else {
                    Label(
                        "\(plan.missingFromSourceCount) Blackbox record\(plan.missingFromSourceCount == 1 ? " is" : "s are") absent from this source.",
                        systemImage: "minus.circle"
                    )
                    Text("These Blackbox-only records are preserved exactly. This import never removes a record because it is absent from the source.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("import.sourceOnlyOmissions")
    }

    private func action(for sourcePK: Int64?, in plan: ImportPlan) -> ImportResultingAction {
        guard let sourcePK else { return .ignore }
        return store.pendingImportPlan?.resolutionActions[sourcePK]
            ?? store.pendingImportPlan?.resultingActions[sourcePK]
            ?? plan.resolutionActions[sourcePK]
            ?? plan.resultingActions[sourcePK]
            ?? .ignore
    }

    private func resultingActionBinding(sourcePK: Int64?, includedAction: ImportResultingAction) -> Binding<Bool> {
        Binding(get: {
            guard let sourcePK else { return false }
            return store.pendingImportPlan?.resultingActions[sourcePK].map { $0 != .ignore } ?? false
        }, set: { included in
            guard let sourcePK else { return }
            store.pendingImportPlan?.resultingActions[sourcePK] = included ? includedAction : .ignore
        })
    }

    private func resolutionActionBinding(_ sourcePK: Int64) -> Binding<ImportResultingAction?> {
        Binding(get: {
            store.pendingImportPlan?.resolutionActions[sourcePK]
        }, set: { action in
            store.pendingImportPlan?.duplicateDecisions.removeValue(forKey: sourcePK)
            if let action {
                store.pendingImportPlan?.resolutionActions[sourcePK] = action
            } else {
                store.pendingImportPlan?.resolutionActions.removeValue(forKey: sourcePK)
            }
        })
    }

    private func validResolutionActions(sourcePK: Int64, plan: ImportPlan) -> [ImportResultingAction] {
        if let change = plan.changes.first(where: { $0.sourcePK == sourcePK }) {
            switch change.existing.recordState {
            case .draft:
                return [.linkAndSkip, .importSeparateDraft, .updateDraft]
            case .finalised:
                return [.linkAndSkip, .importSeparateDraft, .createAmendment]
            case .superseded, .trashed:
                return [.linkAndSkip, .importSeparateDraft]
            }
        }
        return [.linkAndSkip, .importSeparateDraft]
    }

    private func recommendedAction(for state: FlightRecordState) -> ImportResultingAction {
        switch state {
        case .draft: return .updateDraft
        case .finalised: return .createAmendment
        case .superseded, .trashed: return .importSeparateDraft
        }
    }

    private func setFieldDecisions(sourcePK: Int64, decision: ImportDecision) {
        guard var plan = store.pendingImportPlan else { return }
        for index in plan.fieldSelections.indices where plan.fieldSelections[index].sourcePK == sourcePK {
            plan.fieldSelections[index].decision = decision
        }
        store.pendingImportPlan = plan
    }

    private func hasBlockingConflicts(in plan: ImportPlan) -> Bool {
        plan.conflicts.contains { conflict in
            !plan.conflictSourceIDs.contains { sourcePK in
                conflict.hasPrefix("Source \(sourcePK) ")
            }
        }
    }

    private func previewReadiness(_ plan: ImportPlan) -> String {
        if hasBlockingConflicts(in: plan) { return "A source conflict cannot be resolved safely in this preview" }
        if !plan.isApplicable { return "Resolve every duplicate and attributed conflict before applying" }
        if !store.planHasSelectedChanges(plan) { return "Choose at least one addition or changed field to apply" }
        return "Ready for verified staged application"
    }
}

private struct ImportActionLabel: View {
    var action: ImportResultingAction

    var body: some View {
        Label(Self.title(for: action), systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(action == .ignore || action == .linkAndSkip ? .secondary : OpenPilotTheme.cyan)
            .accessibilityLabel("Resulting action: \(Self.title(for: action))")
    }

    static func title(for action: ImportResultingAction) -> String {
        switch action {
        case .createDraft: return "Create draft"
        case .linkAndSkip: return "Link and skip"
        case .importSeparateDraft: return "Import as separate draft"
        case .updateDraft: return "Update draft"
        case .createAmendment: return "Create amendment"
        case .ignore: return "Skip"
        }
    }

    private var systemImage: String {
        switch action {
        case .createDraft: return "plus.rectangle"
        case .linkAndSkip: return "link"
        case .importSeparateDraft: return "rectangle.stack.badge.plus"
        case .updateDraft: return "pencil"
        case .createAmendment: return "doc.badge.plus"
        case .ignore: return "forward.end"
        }
    }
}

private extension String {
    var accessibilityIdentifierComponent: String {
        lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
