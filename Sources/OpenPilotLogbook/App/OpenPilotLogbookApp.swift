import SwiftUI
import AppKit
import OpenPilotLogbookCore

@main
struct OpenPilotLogbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = LogbookStore(paths: UITestLaunchConfiguration.pathsForCurrentLaunch())

    var body: some Scene {
        WindowGroup("Blackbox") {
            ContentView(store: store)
                .modifier(UITestAccessibilityEnvironment())
                .frame(minWidth: 860, minHeight: 680)
                .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Flight") { store.startNewFlight() }
                    .keyboardShortcut("n", modifiers: [.command])
                Button("Save Draft") { store.saveDraft() }
                    .keyboardShortcut("s", modifiers: [.command])
                    .disabled(!store.canSaveDraft)
                Button("Finalise Entry") { store.requestFinalise() }
                    .keyboardShortcut(.return, modifiers: [.command, .shift])
                    .disabled(!store.canFinalise)
                Button("Export CAA-format Report") { store.exportToRememberedFolder() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Search Flights") {
                    store.requestSearchFocus()
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            CommandMenu("Flights") {
                Button("Copy Selected Flights") { store.copySelectedFlights() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
                Button("Paste Flights") { store.pasteFlights() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
                Button("Duplicate Flight") { store.duplicateCurrentFlight() }
                    .keyboardShortcut("d", modifiers: [.command])
                Divider()
                Button("Show Logbook Pages") { store.requestSection(.pages) }
                    .keyboardShortcut("p", modifiers: [.command, .option])
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppSnapshotRunner.runIfRequested() {
            return
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        UITestLaunchConfiguration.configureApplicationIfRequested()
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
    @Published var logTenComparisonState: LogTenComparisonState = .idle
    @Published var recency = RecencySnapshot()
    @Published var duplicateGroups: [DuplicateFlightGroup] = []
    @Published var airportOverrides: [AirportOverride] = []
    @Published var searchText = ""
    @Published var searchFocusRequest = 0
    @Published var flightQuery = FlightQuery()
    @Published private(set) var availableAircraftIDs: [String] = []
    @Published private(set) var availableAircraftTypes: [String] = []
    @Published private(set) var availablePilotFunctions: [String] = []
    @Published private(set) var availableOperations: [String] = []
    @Published private(set) var availableEntryKinds: [String] = []
    @Published var savedAnalysisGroups: [SavedAnalysisGroup] = []
    @Published var currencyLandingLimit: Int {
        didSet { UserDefaults.standard.set(currencyLandingLimit, forKey: "Blackbox.currencyLandingLimit") }
    }
    @Published var currencyLookbackDays: Int {
        didSet { UserDefaults.standard.set(currencyLookbackDays, forKey: "Blackbox.currencyLookbackDays") }
    }
    @Published var draftFlight: FlightEntry?
    @Published var validationReport = FlightValidationReport()
    @Published var flightSuggestions: [FlightSuggestion] = []
    @Published var selectedSuggestionIDs = Set<String>()
    @Published var pendingImportPlan: ImportPlan?
    @Published var pendingRestorePlan: RestorePlan?
    @Published var upgradePreflight: UpgradePreflight?
    @Published var operationBatches: [OperationBatch] = []
    @Published var trashItems: [TrashItem] = []
    @Published var flightRevisions: [FlightRevision] = []
    @Published var historyQuery = HistoryQuery()
    @Published var historyRelatedFlightIDs = Set<Int64>()
    @Published var requestedHistoryDestination: HistoryDestination?
    @Published var showFinaliseConfirmation = false
    @Published var showTrashConfirmation = false
    @Published var showDiscardConfirmation = false
    @Published var showExportConfirmation = false
    @Published var pendingSelectionID: Int64?
    @Published var pendingSection: AppSection?
    @Published var pendingStartNew = false
    private var pendingSearchFocus = false
    @Published var isDraftDirty = false
    @Published var statusMessage = "Loading records..."
    @Published var lastExport: (csv: URL, html: URL)?
    @Published var lastBackup: BackupResult?
    @Published var lastBackupVerification: OperationVerification?
    @Published var lastVerifiedBackupURL: URL?
    @Published var selectedExportFolder: URL?
    @Published var selectedBackupFolder: URL?
    @Published var folderAccessMessage: String?
    @Published var backupPassphrase = ""
    @Published var airportOverride = AirportOverride(identifier: "", name: "", latitude: 0, longitude: 0)
    @Published var lastEntryKind: String {
        didSet { UserDefaults.standard.set(lastEntryKind, forKey: "OpenPilotLogbook.lastEntryKind") }
    }
    private var persistedDraft: FlightEntry?
    private var pendingExportFolder: URL?
    private let folderAccessStore: FolderAccessStore

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

    var canSaveDraft: Bool { draftFlight?.recordState == .draft && isDraftDirty }
    var canFinalise: Bool { draftFlight?.recordState == .draft }
    var exportPreviewFlights: [FlightEntry] {
        var query = flightQuery
        query.recordStates = [.finalised]
        return (try? repository.flights(query: query)) ?? []
    }

    let repository: LogbookRepository
    let paths: LogbookPaths
    let platformServices: any PlatformServices

    init(paths: LogbookPaths = .applicationSupport, platformServices: (any PlatformServices)? = nil, folderAccessStore: FolderAccessStore? = nil) {
        self.paths = paths
        self.repository = LogbookRepository(paths: paths)
        self.platformServices = platformServices ?? MacPlatformServices()
        self.folderAccessStore = folderAccessStore ?? FolderAccessStore()
        self.lastEntryKind = UserDefaults.standard.string(forKey: "OpenPilotLogbook.lastEntryKind") ?? "Flight"
        self.currencyLandingLimit = UserDefaults.standard.object(forKey: "Blackbox.currencyLandingLimit") as? Int ?? 3
        self.currencyLookbackDays = UserDefaults.standard.object(forKey: "Blackbox.currencyLookbackDays") as? Int ?? 90
        if let data = UserDefaults.standard.data(forKey: "Blackbox.savedAnalysisGroups"),
           let groups = try? JSONDecoder().decode([SavedAnalysisGroup].self, from: data) {
            self.savedAnalysisGroups = groups
        }
        switch self.folderAccessStore.resolve(.exports) {
        case .available(let url): self.selectedExportFolder = url
        case .stale: self.folderAccessMessage = "The saved export folder is no longer available. Choose it again."
        case .missing: break
        }
        switch self.folderAccessStore.resolve(.backups) {
        case .available(let url): self.selectedBackupFolder = url
        case .stale: self.folderAccessMessage = "The saved backup folder is no longer available. Choose it again."
        case .missing: break
        }
        refresh()
    }

    func refresh() {
        do {
            try repository.bootstrapIfNeeded()
            _ = try repository.recoverPendingOperationAudits()
            flightQuery.text = searchText
            let filterUniverse = try repository.flights(query: FlightQuery(recordStates: Set(FlightRecordState.allCases)))
            availableAircraftIDs = uniqueValues(\.aircraftID, in: filterUniverse)
            availableAircraftTypes = uniqueValues(\.aircraftType, in: filterUniverse)
            availablePilotFunctions = uniqueValues(\.pilotFunction, in: filterUniverse)
            availableOperations = uniqueValues(\.operation, in: filterUniverse)
            availableEntryKinds = uniqueValues(\.entryKind, in: filterUniverse)
            flights = try repository.flights(query: flightQuery)
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
            operationBatches = try repository.operationBatches()
            restoreLastVerifiedBackupStatus(from: operationBatches)
            trashItems = try repository.trash()
            flightRevisions = try repository.history()
            if selectedFlightID == nil, let first = flights.first {
                selectedFlightID = first.id
                selectedRouteFlightIDs = []
                draftFlight = first
                persistedDraft = first
            } else if let id = selectedFlightID {
                draftFlight = try repository.flight(id: id)
                persistedDraft = draftFlight
            }
            updateDraftDiagnostics()
            isDraftDirty = false
            statusMessage = "Loaded \(summary.flightCount) flights."
        } catch LogbookRepositoryError.upgradeRequired(let preflight) {
            upgradePreflight = preflight
            statusMessage = "Review the backup and schema upgrade before opening this logbook."
        } catch {
            statusMessage = "Record load failed: \(error)"
        }
    }

    func refreshLogTenComparison() {
        logTenComparisonState = .loading
        logTenComparisonState = repository.logTenComparisonState()
        switch logTenComparisonState {
        case .loaded:
            statusMessage = "Compared LogTen Pro with Blackbox."
        case .empty:
            statusMessage = "The LogTen source contains no flight records."
        case .unavailable(let message), .failed(let message):
            statusMessage = "Comparison failed: \(message)"
        case .idle, .loading:
            break
        }
    }

    func applySearch() {
        do {
            flightQuery.text = searchText
            flights = try repository.flights(query: flightQuery)
            statusMessage = searchText.isEmpty ? "Showing all flights." : "Filtered to \(flights.count) flights."
        } catch {
            statusMessage = "Search failed: \(error)"
        }
    }

    func requestSearchFocus() {
        if selectedSection == .flights {
            searchFocusRequest += 1
            return
        }
        if selectedSection != .flights {
            requestSection(.flights)
        }
        if isDraftDirty {
            pendingSearchFocus = true
        } else {
            searchFocusRequest += 1
        }
    }

    func applyFlightQuery(_ query: FlightQuery, message: String? = nil) {
        guard !isDraftDirty else {
            statusMessage = "Save or discard the current draft before changing filters."
            return
        }
        flightQuery = query
        searchText = query.text
        refresh()
        if let message { statusMessage = message }
    }

    func resetFlightFilters() {
        applyFlightQuery(FlightQuery(), message: "Reset all flight filters.")
    }

    private func uniqueValues(_ keyPath: KeyPath<FlightEntry, String>, in source: [FlightEntry]) -> [String] {
        Array(Set(source.map { $0[keyPath: keyPath] }.filter { !$0.isEmpty })).sorted()
    }

    func saveAnalysisGroup(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        savedAnalysisGroups.append(SavedAnalysisGroup(
            name: trimmed,
            query: flightQuery,
            landingLimit: currencyLandingLimit,
            lookbackDays: currencyLookbackDays
        ))
        persistAnalysisGroups()
        statusMessage = "Saved analysis group ‘\(trimmed)’ locally."
    }

    func applyAnalysisGroup(_ group: SavedAnalysisGroup) {
        if let value = group.landingLimit { currencyLandingLimit = value }
        if let value = group.lookbackDays { currencyLookbackDays = value }
        applyFlightQuery(group.query, message: "Applied saved analysis group ‘\(group.name)’.")
    }

    func deleteAnalysisGroups(at offsets: IndexSet) {
        savedAnalysisGroups.remove(atOffsets: offsets)
        persistAnalysisGroups()
    }

    private func persistAnalysisGroups() {
        if let data = try? JSONEncoder().encode(savedAnalysisGroups) {
            UserDefaults.standard.set(data, forKey: "Blackbox.savedAnalysisGroups")
        }
    }

    func requestSection(_ section: AppSection?) {
        guard section != selectedSection else { return }
        if section == .history {
            historyQuery.flightID = nil
            historyRelatedFlightIDs.removeAll()
            requestedHistoryDestination = .trash
        }
        if isDraftDirty {
            pendingSection = section
            showDiscardConfirmation = true
        } else {
            selectedSection = section
        }
    }

    func drillDown(_ query: FlightQuery, description: String) {
        applyFlightQuery(query, message: "Showing flights for \(description).")
        if !isDraftDirty { selectedSection = .flights }
    }

    func selectFlight(id: Int64?) {
        if isDraftDirty {
            pendingSelectionID = id
            showDiscardConfirmation = true
            return
        }
        selectFlightImmediately(id: id)
    }

    func selectFlightImmediately(id: Int64?) {
        selectedFlightID = id
        guard let id else {
            draftFlight = nil
            selectedRouteFlightIDs = []
            return
        }
        selectedRouteFlightIDs = [id]
        do {
            draftFlight = try repository.flight(id: id)
            persistedDraft = draftFlight
            updateDraftDiagnostics()
            isDraftDirty = false
        } catch {
            statusMessage = "Could not load flight \(id): \(error)"
        }
    }

    func updateFlightSelection(from oldSelection: Set<Int64>, to newSelection: Set<Int64>) {
        selectedRouteFlightIDs = newSelection
        guard !newSelection.isEmpty else { return }
        let id = newSelection.subtracting(oldSelection).first ?? newSelection.sorted().last
        guard let id else { return }
        selectFlight(id: id)
    }

    func showFlight(_ flight: FlightEntry) {
        if isDraftDirty {
            pendingSection = .flights
            pendingSelectionID = flight.id
            showDiscardConfirmation = true
        } else {
            selectedSection = .flights
            selectFlightImmediately(id: flight.id)
        }
    }

    func showFlight(id: Int64) {
        do {
            guard let flight = try repository.flight(id: id) else {
                statusMessage = "Flight \(id) is no longer available."
                return
            }
            showFlight(flight)
        } catch {
            statusMessage = "Could not open flight \(id): \(error)"
        }
    }

    func toggleRouteSelection(for flight: FlightEntry) {
        guard let id = flight.id else { return }
        if selectedRouteFlightIDs.contains(id) {
            selectedRouteFlightIDs.remove(id)
        } else {
            selectedRouteFlightIDs.insert(id)
        }
        selectFlight(id: id)
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
        let type = NSPasteboard.PasteboardType("uk.co.blackbox.logbook.flightEntries")
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
        let type = NSPasteboard.PasteboardType("uk.co.blackbox.logbook.flightEntries")
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
                flight.recordState = .draft
                flight.amendsFlightID = nil
                flight.supersededByFlightID = nil
                flight.remarks = flight.remarks.replacingOccurrences(
                    of: #"^Sector\s+\d+\s*(?:\((.*)\))?$"#,
                    with: "$1",
                    options: .regularExpression
                )
                ids.insert(try repository.saveDraft(flight, origin: "paste"))
            }
            refresh()
            selectedRouteFlightIDs = ids
            statusMessage = "Pasted \(ids.count) unlocked flight\(ids.count == 1 ? "" : "s")."
        } catch {
            statusMessage = "Could not paste flights: \(error)"
        }
    }

    func startNewFlight() {
        if isDraftDirty {
            pendingStartNew = true
            showDiscardConfirmation = true
            return
        }
        startNewFlightImmediately()
    }

    private func startNewFlightImmediately() {
        selectedSection = .flights
        selectedFlightID = nil
        selectedRouteFlightIDs = []
        draftFlight = FlightEntry(
            date: Date(),
            operation: "MP",
            entryKind: lastEntryKind,
            pilotFunction: lastEntryKind == "Simulator" ? "FSTD" : "Co-pilot"
        )
        persistedDraft = nil
        updateDraftDiagnostics()
        isDraftDirty = false
    }

    func duplicateCurrentFlight() {
        guard var draftFlight else { return }
        draftFlight.id = nil
        draftFlight.sourcePK = nil
        draftFlight.locked = false
        draftFlight.recordState = .draft
        draftFlight.amendsFlightID = nil
        draftFlight.supersededByFlightID = nil
        draftFlight.date = Date()
        self.draftFlight = draftFlight
        selectedFlightID = nil
        selectedRouteFlightIDs = []
        persistedDraft = nil
        draftDidChange()
    }

    func beginAmendment() {
        guard let selectedFlightID else { return }
        do {
            let id = try repository.beginAmendment(of: selectedFlightID)
            refresh()
            selectFlightImmediately(id: id)
            announce("Created an amendment draft. The finalised original is unchanged.")
        } catch {
            announce("Could not create amendment: \(error)")
        }
    }

    @discardableResult
    func saveDraft() -> Bool {
        guard let draftFlight, draftFlight.recordState == .draft else { return false }
        if UITestLaunchConfiguration.shouldInjectSaveFailureForCurrentLaunch() {
            announce("Could not save draft: injected synthetic persistence failure")
            return false
        }
        do {
            let id = try repository.saveDraft(draftFlight)
            selectedFlightID = id
            refresh()
            selectFlightImmediately(id: id)
            announce("Draft saved")
            NSApp.keyWindow?.undoManager?.setActionName("Save Draft")
            return true
        } catch {
            announce("Could not save draft: \(error)")
            return false
        }
    }

    func saveDraftAndContinue() {
        guard saveDraft() else { return }
        discardChangesAndContinue()
    }

    func requestFinalise() {
        guard canFinalise else { return }
        updateDraftDiagnostics()
        guard let draftFlight else { return }
        do {
            validationReport = try repository.validationReport(for: draftFlight)
            guard !validationReport.hasErrors else {
                announce("Finalisation blocked. Resolve the structural validation errors first")
                return
            }
        } catch {
            announce("Finalisation blocked because amendment integrity could not be verified: \(error)")
            return
        }
        showFinaliseConfirmation = true
    }

    func confirmFinalise() {
        guard let draftFlight else { return }
        do {
            let id = try (draftFlight.amendsFlightID == nil
                ? repository.finalise(draftFlight, acknowledgeWarnings: true)
                : repository.finaliseAmendment(draftFlight, acknowledgeWarnings: true))
            selectedFlightID = id
            refresh()
            selectFlightImmediately(id: id)
            announce(draftFlight.amendsFlightID == nil ? "Entry finalised" : "Amendment finalised; the original is preserved as superseded")
        } catch {
            announce("Could not finalise entry: \(error)")
        }
    }

    func setDraftEntryKind(_ kind: String) {
        lastEntryKind = kind == "Simulator" ? "Simulator" : "Flight"
        draftFlight?.entryKind = lastEntryKind
        draftDidChange()
    }

    func draftDidChange() {
        isDraftDirty = draftFlight != persistedDraft
        updateDraftDiagnostics()
    }

    func acceptSuggestion(_ suggestion: FlightSuggestion) {
        guard suggestion.isActionable, let draftFlight else { return }
        let before = draftFlight
        self.draftFlight = FlightSuggestionEngine.applying(suggestion, to: draftFlight)
        draftDidChange()
        NSApp.keyWindow?.undoManager?.registerUndo(withTarget: self) { store in
            store.draftFlight = before
            store.draftDidChange()
            store.announce("Undid \(suggestion.title) suggestion")
        }
        NSApp.keyWindow?.undoManager?.setActionName("Accept Suggestion")
        announce("Accepted \(suggestion.title) suggestion")
    }

    func acceptSelectedSuggestions() {
        guard let draftFlight else { return }
        let batch = repository.prepareSuggestionBatch(for: draftFlight, selectedSuggestionIDs: selectedSuggestionIDs)
        let before = draftFlight
        self.draftFlight = repository.applySuggestionBatch(batch, to: draftFlight)
        selectedSuggestionIDs.removeAll()
        draftDidChange()
        NSApp.keyWindow?.undoManager?.registerUndo(withTarget: self) { store in
            store.draftFlight = before
            store.draftDidChange()
            store.announce("Undid accepted suggestions")
        }
        NSApp.keyWindow?.undoManager?.setActionName("Accept Selected Suggestions")
        announce("Accepted selected suggestions")
    }

    private func updateDraftDiagnostics() {
        guard let draftFlight else {
            validationReport = FlightValidationReport()
            flightSuggestions = []
            return
        }
        validationReport = FlightSuggestionEngine.validationReport(for: draftFlight)
        flightSuggestions = FlightSuggestionEngine.suggestions(for: draftFlight)
        selectedSuggestionIDs.formIntersection(Set(flightSuggestions.filter(\.isActionable).map(\.id)))
    }

    func importDocuments(urls: [URL]) {
        do {
            importCandidates = try urls.flatMap { url in
                try withScopedAccess(to: url) {
                    try FlightDocumentImporter.candidates(from: [url], suggestions: suggestions)
                }
            }
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
            pendingImportPlan = try repository.prepareImport(from: url)
            statusMessage = "Import preview ready. Nothing has been changed."
        } catch {
            statusMessage = "LogTen Pro preview failed: \(error)"
        }
    }

    func applyPendingImport() {
        guard let plan = pendingImportPlan else { return }
        guard planHasSelectedChanges(plan) else {
            announce("Nothing is selected to import. Choose at least one addition or changed field")
            return
        }
        do {
            _ = try repository.applyImport(plan)
            pendingImportPlan = nil
            importCandidates.removeAll()
            selectedImportIDs.removeAll()
            selectedFlightID = nil
            selectedRouteFlightIDs = []
            draftFlight = nil
            logTenComparisonState = .idle
            refresh()
            announce("Imported \(plan.additions.count) additions and reviewed \(plan.changes.count) changes. No absent records were removed")
        } catch LogbookRepositoryError.recoveryFailed {
            pendingImportPlan = nil
            announce("Import failed and recovery could not be verified. Stop using this database and preserve the diagnostic artifact")
        } catch LogbookRepositoryError.operationFailedWithVerifiedRecovery(_, let message, let recoveryOutcome) {
            pendingImportPlan = nil
            announce("Import failed. \(recoveryOutcome): \(message)")
        } catch {
            // Applying consumes the private source snapshot even on rollback.
            // Require a fresh read-only preview instead of offering a stale retry.
            pendingImportPlan = nil
            announce("Import failed before a recovery outcome could be reported: \(error)")
        }
    }

    func cancelPendingImport() {
        guard let plan = pendingImportPlan else { return }
        repository.discardImportPlan(plan)
        pendingImportPlan = nil
        statusMessage = "Import preview cancelled. No records were changed."
    }

    func planHasSelectedChanges(_ plan: ImportPlan) -> Bool {
        let includesAddition = plan.additions.contains { flight in
            guard let sourcePK = flight.sourcePK else { return false }
            let action = plan.resolutionActions[sourcePK] ?? plan.resultingActions[sourcePK]
            guard (action == .createDraft || action == .importSeparateDraft),
                  plan.duplicateDecisions[sourcePK] != .exclude else { return false }
            return plan.fieldSelections.contains { selection in
                selection.sourcePK == sourcePK && selection.decision == .include
            }
        }
        let includesChange = plan.changes.contains { change in
            let action = plan.resolutionActions[change.sourcePK] ?? plan.resultingActions[change.sourcePK]
            guard action == .updateDraft || action == .createAmendment || action == .importSeparateDraft,
                  plan.duplicateDecisions[change.sourcePK] != .exclude else { return false }
            return plan.fieldSelections.contains { selection in
                selection.sourcePK == change.sourcePK && selection.decision == .include
            }
        }
        return includesAddition || includesChange
    }

    func acceptSelectedImports() {
        let selected = importCandidates.filter { selectedImportIDs.contains($0.id) }
        guard !selected.isEmpty else {
            statusMessage = "No import rows selected."
            return
        }
        do {
            pendingImportPlan = try repository.prepareDocumentImport(
                candidates: selected.map(\.flight),
                sourceURL: URL(fileURLWithPath: "Reviewed document or OCR batch")
            )
            statusMessage = "Document import preview ready. Review every selected field before applying."
        } catch { statusMessage = "Document import preview failed: \(error)" }
    }

    func deleteSelectedFlight() {
        guard let selectedFlightID else { return }
        do {
            try repository.moveToTrash(id: selectedFlightID)
            self.selectedFlightID = nil
            self.selectedRouteFlightIDs.remove(selectedFlightID)
            self.draftFlight = nil
            refresh()
            NSApp.keyWindow?.undoManager?.registerUndo(withTarget: self) { store in
                store.restoreFlightFromTrash(id: selectedFlightID)
            }
            announce("Moved draft to Trash. Choose Undo to restore it")
        } catch {
            announce("Could not move draft to Trash: \(error)")
        }
    }

    func restoreFlightFromTrash(id: Int64) {
        do {
            try repository.restoreFromTrash(id: id)
            refresh()
            selectFlightImmediately(id: id)
            announce("Restored draft from Trash")
        } catch {
            announce("Could not restore draft: \(error)")
        }
    }

    func refreshHistory() {
        do {
            trashItems = try repository.trash()
            operationBatches = try repository.operationBatches()
            flightRevisions = try repository.history()
        } catch { statusMessage = "History refresh failed: \(error)" }
    }

    func restoreTrash(ids: Set<Int64>) {
        do {
            try repository.restoreFromTrash(ids: ids)
            refresh()
            refreshHistory()
            announce("Restored \(ids.count) draft\(ids.count == 1 ? "" : "s") from Trash")
        } catch { announce("Could not restore selected drafts: \(error)") }
    }

    func exportReports(to folder: URL) {
        let attemptedCount = exportPreviewFlights.count
        let attemptedMinutes = LogbookSummary(flights: exportPreviewFlights).totalMinutes
        do {
            var exportQuery = flightQuery
            exportQuery.recordStates = [.finalised]
            let finalised = try repository.flights(query: exportQuery)
            lastExport = try folderAccessStore.withAccess(to: folder) {
                try ReportExporter.exportCAAResources(flights: finalised, summary: LogbookSummary(flights: finalised), to: folder)
            }
            selectedExportFolder = folder
            try folderAccessStore.remember(folder, for: .exports)
            let files = [lastExport?.csv, lastExport?.html].compactMap { $0 }
            try repository.recordOperation(OperationBatch(
                kind: "export",
                source: folder.path,
                status: "completed",
                summary: "Exported \(finalised.count) finalised active records in CAA format",
                completedAt: Date(),
                affectedCount: finalised.count,
                beforeTotalMinutes: LogbookSummary(flights: finalised).totalMinutes,
                afterTotalMinutes: LogbookSummary(flights: finalised).totalMinutes,
                artifactURLs: files
            ))
            refreshHistory()
            announce("Exported \(finalised.count) finalised records in CAA format. This is not a regulatory certification")
        } catch {
            recordFailedOperation(
                kind: "export",
                source: folder.path,
                summary: "CAA-format export failed before completion: \(error.localizedDescription)",
                affectedCount: attemptedCount,
                totalMinutes: attemptedMinutes
            )
            statusMessage = "Export failed: \(error)"
        }
    }

    func requestExport(to folder: URL? = nil) {
        guard let destination = folder ?? selectedExportFolder else {
            chooseAndExportReports()
            return
        }
        pendingExportFolder = destination
        showExportConfirmation = true
    }

    var pendingExportDestinationName: String {
        (pendingExportFolder ?? selectedExportFolder)?.path(percentEncoded: false) ?? "No folder selected"
    }

    func confirmExport() {
        showExportConfirmation = false
        guard let folder = pendingExportFolder else { return }
        pendingExportFolder = nil
        exportReports(to: folder)
    }

    func cancelExport() {
        pendingExportFolder = nil
        showExportConfirmation = false
    }

    func chooseAndExportReports() {
        guard let url = platformServices.chooseFolder(title: "Choose Export Folder", prompt: "Export Here") else { return }
        requestExport(to: url)
    }

    func exportToRememberedFolder() {
        requestExport(to: selectedExportFolder)
    }

    private func restoreLastVerifiedBackupStatus(from batches: [OperationBatch]) {
        guard lastBackupVerification == nil,
              let batch = batches.first(where: {
                  $0.kind == "backup" && $0.status == "completed" && $0.verification?.passed == true
              }),
              let backupURL = batch.artifactURLs.first(where: { $0.pathExtension == "blackboxbackup" })
        else { return }
        lastBackupVerification = batch.verification
        lastVerifiedBackupURL = backupURL
        lastBackup = BackupResult(
            encryptedBackup: backupURL,
            manifest: batch.artifactURLs.first(where: { $0.pathExtension == "json" }) ?? backupURL.deletingPathExtension().appendingPathExtension("manifest.json")
        )
    }

    func createEncryptedBackup(in folder: URL? = nil) {
        let destination = folder ?? selectedBackupFolder ?? paths.backupFolder
        do {
            lastBackup = try folderAccessStore.withAccess(to: destination) {
                try EncryptedBackupService.createBackup(
                    database: paths.workingDatabase,
                    destinationFolder: destination,
                    passphrase: backupPassphrase
                )
            }
            selectedBackupFolder = destination
            if destination.standardizedFileURL.path != paths.backupFolder.standardizedFileURL.path {
                try folderAccessStore.remember(destination, for: .backups)
            }
            if let backup = lastBackup {
                lastBackupVerification = try repository.verifyEncryptedBackup(at: backup.encryptedBackup, passphrase: backupPassphrase)
                lastVerifiedBackupURL = backup.encryptedBackup
                try repository.recordOperation(OperationBatch(
                    kind: "backup",
                    source: destination.path,
                    status: lastBackupVerification?.passed == true ? "completed" : "failed",
                    summary: "Created and verified encrypted recovery backup",
                    backupPath: backup.encryptedBackup.path,
                    completedAt: Date(),
                    affectedCount: summary.flightCount,
                    beforeTotalMinutes: summary.totalMinutes,
                    afterTotalMinutes: summary.totalMinutes,
                    verification: lastBackupVerification,
                    artifactURLs: [backup.encryptedBackup, backup.manifest]
                ))
            }
            backupPassphrase = ""
            refreshHistory()
            announce("Created and verified encrypted backup")
        } catch {
            recordFailedOperation(
                kind: "backup",
                source: destination.path,
                summary: "Encrypted backup failed before verification: \(error.localizedDescription)",
                affectedCount: summary.flightCount,
                totalMinutes: summary.totalMinutes
            )
            statusMessage = "Encrypted backup failed: \(error)"
        }
    }

    func chooseAndCreateEncryptedBackup() {
        guard let url = platformServices.chooseFolder(title: "Choose Backup Folder", prompt: "Back Up Here") else { return }
        createEncryptedBackup(in: url)
    }

    func rehearseLastVerifiedRestore() {
        guard let lastVerifiedBackupURL else {
            statusMessage = "Create and verify an encrypted backup before rehearsing restore."
            return
        }
        do {
            let verification = try folderAccessStore.withAccess(to: lastVerifiedBackupURL.deletingLastPathComponent()) {
                try repository.rehearseRestore(from: lastVerifiedBackupURL, passphrase: backupPassphrase)
            }
            lastBackupVerification = verification
            backupPassphrase = ""
            try repository.recordOperation(OperationBatch(
                kind: "restore_rehearsal", source: lastVerifiedBackupURL.path,
                status: verification.passed ? "completed" : "failed",
                summary: "Inspected an encrypted backup in a disposable staging location",
                completedAt: Date(), affectedCount: verification.actualFlightCount,
                beforeTotalMinutes: summary.totalMinutes, afterTotalMinutes: verification.actualTotalMinutes,
                verification: verification, artifactURLs: [lastVerifiedBackupURL]
            ))
            refreshHistory()
            announce("Synthetic restore rehearsal completed without replacing the active database")
        } catch {
            recordFailedOperation(
                kind: "restore_rehearsal",
                source: lastVerifiedBackupURL.path,
                summary: "Synthetic restore rehearsal failed: \(error.localizedDescription)",
                affectedCount: summary.flightCount,
                totalMinutes: summary.totalMinutes
            )
            statusMessage = "Restore rehearsal failed: \(error)"
        }
    }

    func restoreEncryptedBackup(url: URL) {
        do {
            pendingRestorePlan = try withScopedAccess(to: url) {
                try repository.prepareRestore(from: url, passphrase: backupPassphrase)
            }
            backupPassphrase = ""
            statusMessage = "Restore preview verified. Nothing has been changed."
        } catch {
            statusMessage = "Restore preview failed: \(error)"
        }
    }

    func applyPendingRestore() {
        guard let plan = pendingRestorePlan else { return }
        do {
            let restorePoint = try repository.applyRestore(
                plan,
                injectingFailureAt: UITestLaunchConfiguration.restoreFailureStageForCurrentLaunch()
            )
            pendingRestorePlan = nil
            selectedFlightID = nil
            selectedRouteFlightIDs = []
            draftFlight = nil
            refresh()
            announce("Restored encrypted backup. Recovery point: \(restorePoint.lastPathComponent)")
        } catch LogbookRepositoryError.recoveryFailed {
            announce("Restore failed and recovery could not be verified. Stop using this database and preserve the diagnostic artifact")
        } catch LogbookRepositoryError.operationFailedWithVerifiedRecovery(_, let message, let recoveryOutcome) {
            announce("Restore failed. \(recoveryOutcome): \(message)")
        } catch {
            announce("Restore failed before a recovery outcome could be reported: \(error)")
        }
    }

    func performUpgrade() {
        guard let upgradePreflight else { return }
        do {
            let backup = try repository.backUpAndUpgrade(using: upgradePreflight)
            try repository.recordOperation(OperationBatch(
                kind: "migration", source: paths.workingDatabase.path, status: "completed",
                summary: "Schema \(upgradePreflight.currentSchemaVersion) upgraded to \(upgradePreflight.targetSchemaVersion) after verified backup",
                backupPath: backup.path, completedAt: Date(), affectedCount: upgradePreflight.flightCount,
                beforeTotalMinutes: summary.totalMinutes, afterTotalMinutes: summary.totalMinutes,
                recoveryOutcome: "Pre-upgrade database retained", artifactURLs: [backup]
            ))
            self.upgradePreflight = nil
            refresh()
            statusMessage = "Upgrade complete. Preserved backup: \(backup.lastPathComponent)."
        } catch {
            recordFailedOperation(
                kind: "migration",
                source: paths.workingDatabase.path,
                summary: "Migration failed before completion: \(error.localizedDescription)",
                affectedCount: upgradePreflight.flightCount,
                totalMinutes: summary.totalMinutes
            )
            statusMessage = "Upgrade failed without completing: \(error)"
        }
    }

    private func recordFailedOperation(kind: String, source: String, summary: String, affectedCount: Int, totalMinutes: Int) {
        do {
            try repository.recordOperation(OperationBatch(
                kind: kind,
                source: source,
                status: "failed",
                summary: summary,
                completedAt: Date(),
                affectedCount: affectedCount,
                beforeTotalMinutes: totalMinutes,
                afterTotalMinutes: totalMinutes,
                failureStage: "pre_completion",
                recoveryOutcome: "Active flight facts were not changed"
            ))
            refreshHistory()
        } catch {
            statusMessage = "\(summary). Operation history could not be recorded: \(error.localizedDescription)"
        }
    }

    func discardChangesAndContinue() {
        isDraftDirty = false
        if pendingStartNew {
            pendingStartNew = false
            pendingSection = nil
            pendingSelectionID = nil
            startNewFlightImmediately()
            return
        }
        let target = pendingSelectionID
        if let section = pendingSection {
            pendingSection = nil
            pendingSelectionID = nil
            selectedSection = section
            if let target { selectFlightImmediately(id: target) }
            if pendingSearchFocus, section == .flights {
                pendingSearchFocus = false
                searchFocusRequest += 1
            }
            return
        }
        pendingSelectionID = nil
        selectFlightImmediately(id: target)
    }

    func cancelPendingSelection() {
        pendingSelectionID = nil
        pendingSection = nil
        pendingStartNew = false
        pendingSearchFocus = false
        showDiscardConfirmation = false
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

    func showHistory(for flightID: Int64? = nil, destination: HistoryDestination? = nil) {
        historyQuery.flightID = flightID
        historyRelatedFlightIDs = flightID.map(amendmentChainIDs(startingAt:)) ?? []
        requestedHistoryDestination = destination ?? (flightID == nil ? .operations : .revisions)
        if isDraftDirty {
            pendingSection = .history
            showDiscardConfirmation = true
        } else {
            selectedSection = .history
        }
        refreshHistory()
    }

    func clearHistoryContext() {
        historyQuery.flightID = nil
        historyRelatedFlightIDs.removeAll()
        refreshHistory()
    }

    private func amendmentChainIDs(startingAt flightID: Int64) -> Set<Int64> {
        var visited = Set<Int64>()
        var pending = [flightID]
        while let currentID = pending.popLast(), visited.insert(currentID).inserted {
            guard let flight = try? repository.flight(id: currentID) else { continue }
            if let originalID = flight.amendsFlightID { pending.append(originalID) }
            if let successorID = flight.supersededByFlightID { pending.append(successorID) }
        }
        return visited
    }

    private func withScopedAccess<T>(to url: URL, _ work: () throws -> T) throws -> T {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try work()
    }

    func announce(_ message: String) {
        statusMessage = message
        NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

enum HistoryDestination: String, CaseIterable, Identifiable {
    case trash = "Trash"
    case operations = "Operations"
    case revisions = "Revisions"

    var id: String { rawValue }
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
    case compliance = "Logbook Checks"
    case reports = "Reports"
    case history = "History"

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
        case .compliance: return "Internal completeness"
        case .reports: return "CSV and print"
        case .history: return "Trash and audit trail"
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
        case .history: return "clock.arrow.circlepath"
        }
    }
}
