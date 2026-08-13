import SwiftUI
import OpenPilotLogbookCore

struct HistoryView: View {
    @ObservedObject var store: LogbookStore
    @State private var selection = HistoryDestination.trash
    @State private var selectedTrashIDs = Set<Int64>()
    @State private var searchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("History").pageTitleStyle()
                    Text("Recover drafts and inspect every recorded change or reliability operation.").foregroundStyle(.secondary)
                }
                Spacer()
                Picker("History section", selection: $selection) {
                    ForEach(HistoryDestination.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(maxWidth: 360)
            }
            TextField("Search history", text: $searchText).textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search history")
                .accessibilityIdentifier("history.search")
            if let flightID = store.historyQuery.flightID {
                HStack {
                    Label(contextLabel(flightID), systemImage: "link")
                    Spacer()
                    Button("Show All History", action: store.clearHistoryContext)
                        .accessibilityIdentifier("history.context.clear")
                }
                .font(.callout)
                .padding(10)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("history.context")
            }
            Group {
                switch selection {
                case .trash: trashView
                case .operations: operationsView
                case .revisions: revisionsView
                }
            }
        }
        .padding(24)
        .navigationTitle("History")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("history.screen")
        .onAppear {
            if let requested = store.requestedHistoryDestination { selection = requested }
            store.refreshHistory()
        }
        .onChange(of: store.requestedHistoryDestination) { _, requested in
            if let requested { selection = requested }
        }
    }

    private var trashView: some View {
        Panel("Recoverable Drafts", systemImage: "trash") {
            HStack {
                Text("Permanent deletion is not available. Only drafts can enter Trash.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Selected") { store.restoreTrash(ids: selectedTrashIDs); selectedTrashIDs.removeAll() }
                    .disabled(selectedTrashIDs.isEmpty)
                    .accessibilityIdentifier("history.trash.restoreSelected")
            }
            Table(filteredTrash, selection: $selectedTrashIDs) {
                TableColumn("Date") { Text(LogbookFormatters.dateFormatter.string(from: $0.flight.date)) }
                TableColumn("Route") { item in
                    Button(item.flight.routeDisplay.isEmpty ? "No route" : item.flight.routeDisplay) {
                        store.showFlight(item.flight)
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier("history.trash.open.\(item.id)")
                }
                TableColumn("Aircraft") { Text($0.flight.aircraftID) }
                TableColumn("Trashed") { Text($0.trashedAt.map(LogbookFormatters.dateFormatter.string) ?? "Unknown") }
                TableColumn("Origin") { Text($0.origin) }
                TableColumn("Action") { item in
                    Button("Restore") { store.restoreTrash(ids: [item.id]) }
                        .accessibilityIdentifier("history.trash.restore.\(item.id)")
                }
            }.frame(minHeight: 360)
                .accessibilityIdentifier("history.trash.table")
        }
    }

    private var operationsView: some View {
        Panel("Operation Batches", systemImage: "clock.arrow.circlepath") {
            if filteredOperations.isEmpty { ContentUnavailableView("No operations", systemImage: "clock", description: Text("Imports, restores, migrations, exports, and backups appear here.")) }
            ForEach(filteredOperations) { operation in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(operation.kind.replacingOccurrences(of: "_", with: " ").capitalized, systemImage: operation.status == "completed" ? "checkmark.circle" : "exclamationmark.triangle")
                        Spacer()
                        Text(operation.status.capitalized).font(.caption.weight(.semibold))
                    }
                    Text(operation.summary).font(.callout)
                    if !operation.source.isEmpty { LabeledContent("Source", value: operation.source) }
                    LabeledContent("Affected", value: operation.affectedCount.formatted())
                    LabeledContent("Totals", value: "\(LogbookFormatters.hours(operation.beforeTotalMinutes)) → \(LogbookFormatters.hours(operation.afterTotalMinutes))")
                    if let verification = operation.verification {
                        DisclosureGroup(verification.passed ? "Verification passed" : "Verification failed") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                                verificationRow("Integrity", verification.integrityCheck, verification.integrityCheck.lowercased() == "ok" ? "ok" : "review")
                                verificationRow("Schema", "\(verification.expectedSchemaVersion ?? verification.schemaVersion)", "\(verification.schemaVersion)")
                                verificationRow("Records", "\(verification.expectedFlightCount)", "\(verification.actualFlightCount)")
                                verificationRow("Flying time", LogbookFormatters.hours(verification.expectedTotalMinutes), LogbookFormatters.hours(verification.actualTotalMinutes))
                                if let expected = verification.expectedRevisionCount, let actual = verification.actualRevisionCount {
                                    verificationRow("Revisions", "\(expected)", "\(actual)")
                                }
                                verificationRow("Revision coverage", "complete", verification.revisionCoverageComplete ? "complete" : "incomplete")
                                verificationRow("Foreign keys", "no issues", verification.foreignKeyIssues?.isEmpty == false ? "\(verification.foreignKeyIssues?.count ?? 0) issue(s)" : "no issues")
                                verificationRow("Amendment graph", "valid", verification.amendmentIssues?.isEmpty == false ? "\(verification.amendmentIssues?.count ?? 0) issue(s)" : "valid")
                                if let expected = verification.expectedFlightDigest, let actual = verification.actualFlightDigest {
                                    verificationRow("Flight digest", String(expected.prefix(12)), String(actual.prefix(12)))
                                }
                            }
                            Text("Verified \(verification.verifiedAt.formatted())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let failure = operation.failureStage { LabeledContent("Failure stage", value: failure) }
                    if let outcome = operation.recoveryOutcome { LabeledContent("Recovery", value: outcome) }
                    HStack {
                        Text(operation.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        if let path = operation.backupPath { Button("Reveal in Finder") { store.platformServices.reveal([URL(fileURLWithPath: path)]) } }
                        ForEach(operation.artifactURLs, id: \.absoluteString) { url in
                            Button(url.lastPathComponent) { store.platformServices.reveal([url]) }
                        }
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("history.operation.\(operation.id)")
            }
        }
    }

    private var revisionsView: some View {
        Panel("Flight Revisions", systemImage: "point.3.connected.trianglepath.dotted") {
            if filteredRevisions.isEmpty { ContentUnavailableView("No revisions", systemImage: "doc.text.magnifyingglass") }
            ForEach(filteredRevisions) { revision in
                DisclosureGroup {
                    let diffs = store.repository.revisionDiffs(for: revision)
                    if diffs.isEmpty { Text("No field-level difference was recorded for this action.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(diffs) { diff in
                        GridRow {
                            Text(diff.field).font(.caption.weight(.medium))
                            Text(diff.beforeValue ?? "—").font(.caption).foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").accessibilityHidden(true)
                            Text(diff.afterValue ?? "—").font(.caption)
                        }
                    }
                } label: {
                    HStack {
                        Button("Flight \(revision.flightID)") {
                            store.showFlight(id: revision.flightID)
                        }
                        .buttonStyle(.link)
                        .monospacedDigit()
                        .accessibilityIdentifier("history.revision.flight.\(revision.flightID)")
                        Text(revision.action.replacingOccurrences(of: "_", with: " ").capitalized)
                        Spacer()
                        Text(revision.origin).foregroundStyle(.secondary)
                        if let batch = revision.operationBatchID { Text("Batch \(batch.prefix(8))").foregroundStyle(.secondary) }
                        Text(revision.createdAt.formatted()).foregroundStyle(.secondary)
                    }.font(.callout)
                }
            }
        }
    }

    private var filteredTrash: [TrashItem] { store.trashItems.filter { item in
        (store.historyRelatedFlightIDs.isEmpty || store.historyRelatedFlightIDs.contains(item.id)) &&
        (searchText.isEmpty || [item.flight.routeDisplay, item.flight.aircraftID, item.flight.remarks].joined(separator: " ").localizedCaseInsensitiveContains(searchText))
    } }
    private var filteredOperations: [OperationBatch] { store.operationBatches.filter { operation in
        let relatedBatchIDs = Set(store.flightRevisions.filter { store.historyRelatedFlightIDs.contains($0.flightID) }.compactMap(\.operationBatchID))
        return (store.historyRelatedFlightIDs.isEmpty || relatedBatchIDs.contains(operation.id)) &&
        (searchText.isEmpty || [operation.kind, operation.source, operation.summary].joined(separator: " ").localizedCaseInsensitiveContains(searchText))
    } }
    private var filteredRevisions: [FlightRevision] { store.flightRevisions.filter { revision in
        (store.historyRelatedFlightIDs.isEmpty || store.historyRelatedFlightIDs.contains(revision.flightID)) &&
        (searchText.isEmpty || [revision.action, revision.origin, revision.beforeJSON ?? "", revision.afterJSON ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(searchText))
    } }

    private func contextLabel(_ flightID: Int64) -> String {
        let count = store.historyRelatedFlightIDs.count
        return count > 1
            ? "Showing amendment-chain history for flight \(flightID) (\(count) related records)"
            : "Showing history related to flight \(flightID)"
    }

    private func verificationRow(_ label: String, _ expected: String, _ actual: String) -> some View {
        GridRow {
            Text(label).font(.caption.weight(.medium))
            Text("Expected: \(expected)").font(.caption).foregroundStyle(.secondary)
            Text("Actual: \(actual)").font(.caption)
        }
    }
}
