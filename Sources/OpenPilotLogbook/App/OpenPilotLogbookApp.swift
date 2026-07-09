import SwiftUI
import AppKit
import OpenPilotLogbookCore

@main
struct OpenPilotLogbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LogbookStore()

    var body: some Scene {
        WindowGroup("Blackbox") {
            ContentView(store: store)
                .frame(minWidth: 1240, minHeight: 740)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Flight") { store.startNewFlight() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Export CAA Files") { store.exportReports() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandMenu("Flights") {
                Button("Copy Selected Flights") { store.copySelectedFlights() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste Flights") { store.pasteFlights() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Divider()
                Button("Show Logbook Pages") { store.selectedSection = .pages }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        if AppSnapshotRunner.runIfRequested() {
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class LogbookStore: ObservableObject {
    @Published var selectedSection: AppSection? = .dashboard
    @Published var selectedFlightID: Int64?
    @Published var selectedRouteFlightIDs = Set<Int64>()
    @Published var flights: [FlightEntry] = []
    @Published var aircraft: [AircraftSummary] = []
    @Published var typeSummaries: [TypeSummary] = []
    @Published var people: [PersonSummary] = []
    @Published var places: [PlaceVisitSummary] = []
    @Published var routes: [MapRoute] = []
    @Published var suggestions = SuggestionBundle()
    @Published var importCandidates: [ImportCandidate] = []
    @Published var selectedImportIDs = Set<UUID>()
    @Published var summary = LogbookSummary()
    @Published var compliance = ComplianceSnapshot()
    @Published var logTenComparison = LogTenComparisonSnapshot()
    @Published var recency = RecencySnapshot()
    @Published var duplicateGroups: [DuplicateFlightGroup] = []
    @Published var airportOverrides: [AirportOverride] = []
    @Published var searchText = ""
    @Published var draftFlight: FlightEntry?
    @Published var statusMessage = "Loading records..."
    @Published var lastExport: (csv: URL, html: URL)?
    @Published var lastBackup: BackupResult?
    @Published var backupPassphrase = ""
    @Published var airportOverride = AirportOverride(identifier: "", name: "", latitude: 0, longitude: 0)
    @Published var lastEntryKind: String {
        didSet { UserDefaults.standard.set(lastEntryKind, forKey: "OpenPilotLogbook.lastEntryKind") }
    }
    private var autoSaveTask: Task<Void, Never>?
    private var isPersistingDraft = false

    var visibleRoutes: [MapRoute] {
        guard !selectedRouteFlightIDs.isEmpty else { return routes }
        return routes.filter { selectedRouteFlightIDs.contains($0.id) }
    }

    var highlightedFlights: [FlightEntry] {
        guard !selectedRouteFlightIDs.isEmpty else { return [] }
        return flights.filter { flight in
            flight.id.map { selectedRouteFlightIDs.contains($0) } ?? false
        }
    }

    let repository: LogbookRepository
    let paths: LogbookPaths

    init(paths: LogbookPaths = .applicationSupport) {
        self.paths = paths
        self.repository = LogbookRepository(paths: paths)
        self.lastEntryKind = UserDefaults.standard.string(forKey: "OpenPilotLogbook.lastEntryKind") ?? "Flight"
        refresh()
    }

    func refresh() {
        do {
            try repository.bootstrapIfNeeded()
            flights = try repository.flights(search: searchText)
            aircraft = try repository.aircraftSummaries()
            typeSummaries = try repository.typeSummaries()
            people = try repository.personSummaries()
            places = try repository.placeVisitSummaries()
            routes = try repository.mapRoutes(limit: 5_000)
            suggestions = try repository.suggestions()
            summary = try repository.summary()
            compliance = try repository.complianceSnapshot()
            recency = try repository.recencySnapshot()
            duplicateGroups = try repository.duplicateFlightGroups()
            airportOverrides = try repository.airportOverrides()
            if selectedFlightID == nil, let first = flights.first {
                selectedFlightID = first.id
                selectedRouteFlightIDs = []
                draftFlight = first
            } else if let id = selectedFlightID {
                draftFlight = try repository.flight(id: id)
            }
            statusMessage = "Loaded \(summary.flightCount) flights."
        } catch {
            statusMessage = "Record load failed: \(error)"
        }
    }

    func refreshLogTenComparison() {
        do {
            logTenComparison = try repository.logTenComparisonSnapshot()
            statusMessage = "Compared LogTen Pro with Blackbox."
        } catch {
            statusMessage = "Comparison failed: \(error)"
        }
    }

    func applySearch() {
        do {
            flights = try repository.flights(search: searchText)
            statusMessage = searchText.isEmpty ? "Showing all flights." : "Filtered to \(flights.count) flights."
        } catch {
            statusMessage = "Search failed: \(error)"
        }
    }

    func selectFlight(id: Int64?) {
        selectedFlightID = id
        guard let id else {
            draftFlight = nil
            selectedRouteFlightIDs = []
            return
        }
        selectedRouteFlightIDs = [id]
        do {
            draftFlight = try repository.flight(id: id)
        } catch {
            statusMessage = "Could not load flight \(id): \(error)"
        }
    }

    func updateFlightSelection(from oldSelection: Set<Int64>, to newSelection: Set<Int64>) {
        selectedRouteFlightIDs = newSelection
        guard !newSelection.isEmpty else { return }
        let id = newSelection.subtracting(oldSelection).first ?? newSelection.sorted().last
        guard let id else { return }
        selectedFlightID = id
        do {
            draftFlight = try repository.flight(id: id)
        } catch {
            statusMessage = "Could not load flight \(id): \(error)"
        }
    }

    func showFlight(_ flight: FlightEntry) {
        selectedSection = .flights
        selectFlight(id: flight.id)
    }

    func toggleRouteSelection(for flight: FlightEntry) {
        guard let id = flight.id else { return }
        if selectedRouteFlightIDs.contains(id) {
            selectedRouteFlightIDs.remove(id)
        } else {
            selectedRouteFlightIDs.insert(id)
        }
        selectedFlightID = id
        do {
            draftFlight = try repository.flight(id: id)
        } catch {
            statusMessage = "Could not load flight \(id): \(error)"
        }
    }

    func showAllRoutes() {
        selectedRouteFlightIDs = []
        statusMessage = "Showing all mapped routes."
    }

    func copySelectedFlights() {
        let selected = highlightedFlights.isEmpty ? draftFlight.map { [$0] } ?? [] : highlightedFlights
        guard !selected.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let type = NSPasteboard.PasteboardType("local.codex.Blackbox.flightEntries")
        if let data = try? JSONEncoder().encode(selected) {
            pasteboard.setData(data, forType: type)
        }
        let lines = selected.map { flight in
            [
                LogbookFormatters.isoFormatter.string(from: flight.date),
                flight.flightNumber,
                flight.departure,
                flight.arrival,
                flight.aircraftID,
                flight.pilotFunction,
                LogbookFormatters.hours(flight.totalMinutes)
            ].joined(separator: "\t")
        }
        pasteboard.setString(lines.joined(separator: "\n"), forType: .string)
        statusMessage = "Copied \(selected.count) flight\(selected.count == 1 ? "" : "s")."
    }

    func pasteFlights() {
        let type = NSPasteboard.PasteboardType("local.codex.Blackbox.flightEntries")
        guard let data = NSPasteboard.general.data(forType: type),
              let copied = try? JSONDecoder().decode([FlightEntry].self, from: data),
              !copied.isEmpty
        else {
            statusMessage = "No Blackbox flights are available to paste."
            return
        }
        do {
            var ids = Set<Int64>()
            for var flight in copied {
                flight.id = nil
                flight.sourcePK = nil
                flight.locked = false
                flight.remarks = flight.remarks.replacingOccurrences(
                    of: #"^Sector\s+\d+\s*(?:\((.*)\))?$"#,
                    with: "$1",
                    options: .regularExpression
                )
                ids.insert(try repository.save(flight))
            }
            refresh()
            selectedRouteFlightIDs = ids
            statusMessage = "Pasted \(ids.count) unlocked flight\(ids.count == 1 ? "" : "s")."
        } catch {
            statusMessage = "Could not paste flights: \(error)"
        }
    }

    func startNewFlight() {
        selectedSection = .flights
        selectedFlightID = nil
        selectedRouteFlightIDs = []
        draftFlight = normalizedDraft(FlightEntry(
            date: Date(),
            operation: "MP",
            entryKind: lastEntryKind,
            pilotFunction: lastEntryKind == "Simulator" ? "FSTD" : "Co-pilot"
        ))
    }

    func duplicateCurrentFlight() {
        guard var draftFlight else { return }
        draftFlight.id = nil
        draftFlight.sourcePK = nil
        draftFlight.locked = false
        draftFlight.date = Date()
        self.draftFlight = draftFlight
        normalizeDraft()
        selectedFlightID = nil
        selectedRouteFlightIDs = []
    }

    func unlockSelectedFlight() {
        guard let selectedFlightID else { return }
        do {
            try repository.unlockFlight(id: selectedFlightID)
            refresh()
            statusMessage = "Entry unlocked. Changes will save automatically."
        } catch {
            statusMessage = "Could not unlock entry: \(error)"
        }
    }

    func lockSelectedFlight() {
        guard var draftFlight else { return }
        autoSaveTask?.cancel()
        draftFlight.locked = false
        do {
            let id = try repository.save(draftFlight)
            try repository.lockFlight(id: id)
            selectedFlightID = id
            refresh()
            statusMessage = "Entry saved and locked."
        } catch {
            statusMessage = "Could not lock entry: \(error)"
        }
    }

    func scheduleDraftAutosave() {
        guard let draftFlight, !draftFlight.locked, draftFlight.totalMinutes > 0 else { return }
        autoSaveTask?.cancel()
        autoSaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            self?.persistDraftAutomatically()
        }
    }

    private func persistDraftAutomatically() {
        guard !isPersistingDraft, let draftFlight, !draftFlight.locked, draftFlight.totalMinutes > 0 else { return }
        isPersistingDraft = true
        defer { isPersistingDraft = false }
        do {
            let id = try repository.save(draftFlight)
            selectedFlightID = id
            refresh()
            statusMessage = "Changes saved."
        } catch {
            statusMessage = "Could not save changes: \(error)"
        }
    }

    func setDraftEntryKind(_ kind: String) {
        lastEntryKind = kind == "Simulator" ? "Simulator" : "Flight"
        draftFlight?.entryKind = lastEntryKind
        normalizeDraft()
    }

    func normalizeDraft() {
        guard let draftFlight else { return }
        self.draftFlight = normalizedDraft(draftFlight)
    }

    private func normalizedDraft(_ input: FlightEntry) -> FlightEntry {
        var flight = input
        flight.entryKind = flight.entryKind == "Simulator" ? "Simulator" : "Flight"
        flight.signatureName = ""
        flight.signatureReference = ""
        if flight.crewNameList.count >= 2 { flight.operation = "MP" }
        if flight.entryKind == "Simulator" {
            flight.pilotFunction = "FSTD"
            flight.fstdMinutes = flight.totalMinutes
            flight.picMinutes = 0
            flight.picDayMinutes = 0
            flight.picNightMinutes = 0
            flight.picusMinutes = 0
            flight.picusDayMinutes = 0
            flight.picusNightMinutes = 0
            flight.copilotMinutes = 0
            flight.copilotDayMinutes = 0
            flight.copilotNightMinutes = 0
            flight.instrumentMinutes = 0
            flight.crossCountryMinutes = 0
            flight.pilotFlying = false
            flight.dayTakeoffs = 0
            flight.nightTakeoffs = 0
            flight.totalTakeoffs = 0
            flight.dayLandings = 0
            flight.nightLandings = 0
            flight.totalLandings = 0
        } else {
            flight.fstdMinutes = 0
            if flight.instrumentMinutes == 0 { flight.instrumentMinutes = flight.totalMinutes }
            if flight.crossCountryMinutes == 0 { flight.crossCountryMinutes = flight.totalMinutes }
            if flight.pilotFlying {
                flight.pilotFunction = "PICUS"
                flight.picMinutes = 0
                flight.picNightMinutes = 0
                flight.picDayMinutes = 0
                flight.picusMinutes = flight.totalMinutes
                flight.picusNightMinutes = min(flight.totalMinutes, flight.nightMinutes)
                flight.picusDayMinutes = max(0, flight.picusMinutes - flight.picusNightMinutes)
                flight.copilotMinutes = 0
                flight.copilotDayMinutes = 0
                flight.copilotNightMinutes = 0
            } else {
                flight.pilotFunction = "Co-pilot"
                flight.picMinutes = 0
                flight.picDayMinutes = 0
                flight.picNightMinutes = 0
                flight.picusMinutes = 0
                flight.picusDayMinutes = 0
                flight.picusNightMinutes = 0
                flight.copilotMinutes = flight.totalMinutes
                flight.copilotNightMinutes = min(flight.totalMinutes, flight.nightMinutes)
                flight.copilotDayMinutes = max(0, flight.totalMinutes - flight.copilotNightMinutes)
            }
            flight.totalTakeoffs = flight.dayTakeoffs + flight.nightTakeoffs
            flight.totalLandings = flight.dayLandings + flight.nightLandings
        }
        flight.crewRoles = FlightEntry.crewRolesText(
            from: FlightEntry.parseCrewRoles(flight.crewRoles),
            names: flight.crewNameList
        )
        return flight
    }

    func importDocuments(urls: [URL]) {
        do {
            importCandidates = try FlightDocumentImporter.candidates(from: urls, suggestions: suggestions)
            selectedImportIDs = Set(importCandidates.map(\.id))
            selectedSection = .imports
            statusMessage = "Found \(importCandidates.count) possible flights. Review before importing."
        } catch {
            statusMessage = "Document import failed: \(error)"
        }
    }

    func importLogTenDatabase(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let count = try repository.replaceWithLogTenDatabase(at: url)
            selectedFlightID = nil
            selectedRouteFlightIDs = []
            draftFlight = nil
            importCandidates.removeAll()
            selectedImportIDs.removeAll()
            logTenComparison = LogTenComparisonSnapshot()
            refresh()
            statusMessage = "Imported \(count.formatted()) LogTen Pro flights."
        } catch {
            statusMessage = "LogTen Pro import failed: \(error)"
        }
    }

    func acceptSelectedImports() {
        let selected = importCandidates.filter { selectedImportIDs.contains($0.id) }
        guard !selected.isEmpty else {
            statusMessage = "No import rows selected."
            return
        }
        do {
            for candidate in selected {
                _ = try repository.save(candidate.flight)
            }
            importCandidates.removeAll { selectedImportIDs.contains($0.id) }
            selectedImportIDs.removeAll()
            refresh()
            statusMessage = "Imported \(selected.count) reviewed flights."
        } catch {
            statusMessage = "Import save failed: \(error)"
        }
    }

    func deleteSelectedFlight() {
        guard let selectedFlightID else { return }
        do {
            try repository.deleteFlight(id: selectedFlightID)
            self.selectedFlightID = nil
            self.selectedRouteFlightIDs.remove(selectedFlightID)
            self.draftFlight = nil
            refresh()
            statusMessage = "Deleted flight."
        } catch {
            statusMessage = "Delete failed: \(error)"
        }
    }

    func exportReports() {
        do {
            let allFlights = try repository.flights()
            lastExport = try ReportExporter.exportCAAResources(flights: allFlights, summary: try repository.summary(), to: paths.backupFolder)
            statusMessage = "Exported CSV and printable HTML."
        } catch {
            statusMessage = "Export failed: \(error)"
        }
    }

    func createEncryptedBackup() {
        do {
            lastBackup = try EncryptedBackupService.createBackup(
                database: paths.workingDatabase,
                destinationFolder: paths.backupFolder,
                passphrase: backupPassphrase
            )
            backupPassphrase = ""
            statusMessage = "Created encrypted backup."
        } catch {
            statusMessage = "Encrypted backup failed: \(error)"
        }
    }

    func restoreEncryptedBackup(url: URL) {
        do {
            let restorePoint = paths.backupFolder.appendingPathComponent("Blackbox-pre-restore-\(Int(Date().timeIntervalSince1970)).sqlite")
            if FileManager.default.fileExists(atPath: paths.workingDatabase.path) {
                try? FileManager.default.copyItem(at: paths.workingDatabase, to: restorePoint)
            }
            try EncryptedBackupService.restoreBackup(
                encryptedBackup: url,
                destinationDatabase: paths.workingDatabase,
                passphrase: backupPassphrase
            )
            backupPassphrase = ""
            selectedFlightID = nil
            selectedRouteFlightIDs = []
            draftFlight = nil
            refresh()
            statusMessage = "Restored encrypted backup."
        } catch {
            statusMessage = "Restore failed: \(error)"
        }
    }

    func saveAirportOverride() {
        do {
            try repository.saveAirportOverride(airportOverride)
            airportOverride = AirportOverride(identifier: "", name: "", latitude: 0, longitude: 0)
            refresh()
            statusMessage = "Saved airport coordinate override."
        } catch {
            statusMessage = "Airport override failed: \(error)"
        }
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case flights = "Flights"
    case pages = "Pages"
    case aircraft = "Aircraft"
    case people = "People"
    case analysis = "Analysis"
    case map = "3D Map"
    case comparison = "Compare"
    case imports = "Import"
    case compliance = "CAA Check"
    case reports = "Reports"

    var id: String { rawValue }
    var subtitle: String {
        switch self {
        case .dashboard: return "Totals and readiness"
        case .flights: return "Flight entries"
        case .pages: return "16-sector totals"
        case .aircraft: return "Fleet history"
        case .people: return "Crew history"
        case .analysis: return "Types and places"
        case .map: return "Route globe"
        case .comparison: return "LogTen side by side"
        case .imports: return "PDF and OCR"
        case .compliance: return "CAA audit"
        case .reports: return "CSV and print"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.67percent"
        case .flights: return "airplane"
        case .pages: return "book.pages"
        case .aircraft: return "airplane.circle"
        case .people: return "person.2"
        case .analysis: return "chart.bar.xaxis"
        case .map: return "globe.europe.africa"
        case .comparison: return "rectangle.split.2x1"
        case .imports: return "doc.viewfinder"
        case .compliance: return "checkmark.seal"
        case .reports: return "doc.text"
        }
    }
}
