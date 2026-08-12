import SwiftUI
import OpenPilotLogbookCore

struct ReportsView: View {
    @ObservedObject var store: LogbookStore
    @State private var showRestoreImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Reports")
                        .pageTitleStyle()
                    Text("Generate CAA-format pages, encrypted backups, and internal maintenance checks.")
                        .foregroundStyle(OpenPilotTheme.muted)
                }

                HStack(spacing: 10) {
                    MetricTile(title: "Flights", value: "\(store.summary.flightCount)", systemImage: "airplane", tint: OpenPilotTheme.blue)
                    MetricTile(title: "Total", value: LogbookFormatters.hours(store.summary.totalMinutes), systemImage: "clock", tint: OpenPilotTheme.cyan)
                    MetricTile(title: "Duplicates", value: "\(store.duplicateGroups.count)", systemImage: "doc.on.doc", tint: store.duplicateGroups.isEmpty ? OpenPilotTheme.green : OpenPilotTheme.amber)
                }

                Text("CAA-format export currently includes exactly \(store.exportPreviewFlights.count) finalised active record\(store.exportPreviewFlights.count == 1 ? "" : "s"). Drafts, superseded entries, and Trash are excluded.")
                    .font(.callout).foregroundStyle(.secondary)
                FlightFilterBar(query: exportQuery, resultCount: store.exportPreviewFlights.count, reset: store.resetFlightFilters)
                FlightQueryEditor(query: store.flightQuery, aircraftIDs: store.availableAircraftIDs, aircraftTypes: store.availableAircraftTypes, pilotFunctions: store.availablePilotFunctions, operations: store.availableOperations, entryKinds: store.availableEntryKinds, apply: { store.applyFlightQuery($0) })

                exportPanel
                encryptedBackupPanel
                duplicatePanel
                airportOverridePanel
            }
            .padding(24)
        }
        .fileImporter(isPresented: $showRestoreImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            guard case let .success(urls) = result, let url = urls.first else { return }
            store.restoreEncryptedBackup(url: url)
        }
        .navigationTitle("Reports")
        .accessibilityIdentifier("reports.screen")
    }

    private var exportPanel: some View {
        Panel("Export Pack", systemImage: "doc.text") {
            HStack(spacing: 12) {
                Button {
                    store.exportToRememberedFolder()
                } label: {
                    Label("Export CAA-format Report", systemImage: "square.and.arrow.up")
                        .frame(minWidth: 210)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("reports.export")

                Button {
                    store.chooseAndExportReports()
                } label: {
                    Label("Choose Export Folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.chooseExportFolder")

                Button {
                    if let file = store.lastExport?.csv { store.platformServices.reveal([file]) }
                } label: {
                    Label("Reveal Last Export", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("reports.revealLastExport")
                Spacer()
            }
            Button("View Operation History") { store.showHistory() }
                .buttonStyle(.link)
                .accessibilityIdentifier("reports.viewExportHistory")
            if let lastExport = store.lastExport {
                Divider().opacity(0.35)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Export")
                        .font(.headline)
                    Label(lastExport.csv.lastPathComponent, systemImage: "tablecells")
                    Label(lastExport.html.lastPathComponent, systemImage: "doc.richtext")
                }
                .font(.callout)
                .foregroundStyle(OpenPilotTheme.muted)
            }
        }
    }

    private var encryptedBackupPanel: some View {
        Panel("Encrypted Local Backup", systemImage: "lock.shield") {
            VStack(alignment: .leading, spacing: 12) {
                SecureField("Backup passphrase", text: $store.backupPassphrase)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 420)
                HStack(spacing: 12) {
                    Button {
                        store.createEncryptedBackup()
                    } label: {
                        Label("Create Encrypted Backup", systemImage: "lock.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.backupPassphrase.isEmpty)
                    .accessibilityIdentifier("reports.createBackup")

                    Button {
                        store.chooseAndCreateEncryptedBackup()
                    } label: {
                        Label("Choose Backup Folder", systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.backupPassphrase.isEmpty)

                    Button {
                        showRestoreImporter = true
                    } label: {
                        Label("Restore Encrypted Backup", systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.backupPassphrase.isEmpty)
                    .accessibilityIdentifier("reports.restoreBackup")
                    Spacer()
                }
                if let lastBackup = store.lastBackup {
                    Divider().opacity(0.35)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Last Backup")
                            .font(.headline)
                        Label(lastBackup.encryptedBackup.lastPathComponent, systemImage: "lock.doc")
                        Label(lastBackup.manifest.lastPathComponent, systemImage: "doc.plaintext")
                        if let verification = store.lastBackupVerification {
                            Label(verification.passed ? "Last verified backup passed" : "Last backup verification failed", systemImage: verification.passed ? "checkmark.shield" : "exclamationmark.shield")
                            Text("Verified \(verification.verifiedAt.formatted()) · schema \(verification.schemaVersion) · \(verification.actualFlightCount) records")
                                .font(.caption)
                        }
                        HStack {
                            Button("Reveal in Finder") { store.platformServices.reveal([lastBackup.encryptedBackup]) }
                            Button("Rehearse Restore", action: store.rehearseLastVerifiedRestore)
                                .disabled(store.backupPassphrase.isEmpty)
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(OpenPilotTheme.muted)
                }
                if let plan = store.pendingRestorePlan {
                    Divider().opacity(0.35)
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Verified Restore Preview").font(.headline)
                        Text("SQLite integrity: \(plan.integrityMessage). Schema \(plan.schemaVersion).")
                        LabeledContent("Flights", value: "\(plan.currentFlightCount) → \(plan.restoredFlightCount)")
                        LabeledContent("Flying time", value: "\(LogbookFormatters.hours(plan.currentTotalMinutes)) → \(LogbookFormatters.hours(plan.restoredTotalMinutes))")
                        Text("Applying this preview creates and verifies a recovery point, atomically replaces the database, and rolls back on failure.")
                            .font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button("Cancel Preview") { store.pendingRestorePlan = nil }.buttonStyle(.bordered)
                            Button("Restore Verified Backup", action: store.applyPendingRestore).buttonStyle(.borderedProminent)
                        }
                        Button("View Operation History") { store.showHistory() }
                            .buttonStyle(.link)
                            .accessibilityIdentifier("reports.viewRestoreHistory")
                    }
                }
            }
        }
    }

    private var duplicatePanel: some View {
        Panel("Duplicate Detection", systemImage: "doc.on.doc") {
            if store.duplicateGroups.isEmpty {
                Label("No likely duplicate flights found.", systemImage: "checkmark.seal")
                    .foregroundStyle(OpenPilotTheme.green)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.duplicateGroups.prefix(8)) { group in
                        let first = group.flights.first
                        HStack {
                            Text(first.map { LogbookFormatters.dateFormatter.string(from: $0.date) } ?? "Unknown date")
                                .frame(width: 110, alignment: .leading)
                            Text(first?.routeDisplay ?? "No route")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(group.flights.count) entries")
                                .foregroundStyle(OpenPilotTheme.amber)
                        }
                        .font(.callout)
                        Divider().opacity(0.22)
                    }
                }
            }
        }
    }

    private var airportOverridePanel: some View {
        Panel("Airport Coordinate Overrides", systemImage: "mappin.and.ellipse") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("ICAO or IATA", text: $store.airportOverride.identifier)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    TextField("Name", text: $store.airportOverride.name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Latitude", value: $store.airportOverride.latitude, formatter: NumberFormatter.decimal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    TextField("Longitude", value: $store.airportOverride.longitude, formatter: NumberFormatter.decimal)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                    Button {
                        store.saveAirportOverride()
                    } label: {
                        Label("Save", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                }
                if store.airportOverrides.isEmpty {
                    Text("No manual overrides saved.")
                        .font(.callout)
                        .foregroundStyle(OpenPilotTheme.muted)
                } else {
                    ForEach(store.airportOverrides.prefix(10)) { override in
                        HStack {
                            Text(override.identifier).font(.callout.monospaced().weight(.medium)).frame(width: 70, alignment: .leading)
                            Text(override.name.isEmpty ? "Manual airport" : override.name).frame(maxWidth: .infinity, alignment: .leading)
                            Text(String(format: "%.5f, %.5f", override.latitude, override.longitude))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(OpenPilotTheme.muted)
                        }
                    }
                }
            }
        }
    }

    private var exportQuery: FlightQuery {
        var query = store.flightQuery
        query.recordStates = [.finalised]
        return query
    }
}

private extension NumberFormatter {
    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 6
        return formatter
    }()
}
