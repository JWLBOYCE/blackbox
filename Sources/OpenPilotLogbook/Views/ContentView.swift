import SwiftUI
import OpenPilotLogbookCore

struct ContentView: View {
    @ObservedObject var store: LogbookStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blackboxReduceMotionOverride) private var testReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || testReduceMotion }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            ZStack {
                OpenPilotTheme.background.ignoresSafeArea()
                detailView
            }
            .frame(minWidth: 560)
        }
        .navigationSplitViewStyle(.balanced)
        .searchable(text: $store.searchText, placement: .toolbar, prompt: "Search flights")
        .onSubmit(of: .search, store.applySearch)
        .onChange(of: store.searchText) { _, value in if value.isEmpty { store.applySearch() } }
        .toolbar { toolbar }
        .safeAreaInset(edge: .bottom) { statusBar }
        .alert("Unsaved Draft", isPresented: $store.showDiscardConfirmation) {
            Button("Cancel", role: .cancel, action: store.cancelPendingSelection)
            Button("Save Draft", action: store.saveDraftAndContinue)
            Button("Discard Changes", role: .destructive, action: store.discardChangesAndContinue)
        } message: {
            Text("This draft has changes that have not been saved. They will not be written automatically.")
        }
        .alert("Back Up & Upgrade", isPresented: Binding(get: { store.upgradePreflight != nil }, set: { if !$0 { store.upgradePreflight = nil } })) {
            Button("Quit", role: .cancel) { NSApp.terminate(nil) }
            Button("Back Up & Upgrade", action: store.performUpgrade)
        } message: {
            if let plan = store.upgradePreflight {
                Text("Blackbox will preserve \(plan.flightCount) entries exactly, create \(plan.proposedBackupURL.lastPathComponent), migrate schema \(plan.currentSchemaVersion) to \(plan.targetSchemaVersion), and verify every legacy field and SQLite integrity before opening.")
            }
        }
        .alert("Confirm CAA-format Export", isPresented: $store.showExportConfirmation) {
            Button("Cancel", role: .cancel, action: store.cancelExport)
            Button("Export CAA-format Report", action: store.confirmExport)
        } message: {
            Text("Export exactly \(store.exportPreviewFlights.count) finalised active record\(store.exportPreviewFlights.count == 1 ? "" : "s") using the visible filters to \(store.pendingExportDestinationName). Drafts, superseded entries, and Trash are excluded. This is not regulatory certification.")
        }
        .transaction { transaction in if reduceMotion { transaction.animation = nil } }
        .accessibilityIdentifier("blackbox.root")
    }

    private var sidebar: some View {
        List(selection: Binding(get: { store.selectedSection }, set: store.requestSection)) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.rawValue)
                            Text(section.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: section.icon).frame(width: 18)
                    }
                    .tag(section as AppSection?)
                    .accessibilityLabel("\(section.rawValue), \(section.subtitle)")
                    .accessibilityIdentifier("sidebar.\(section.rawValue.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            } header: {
                Label("Blackbox", systemImage: "airplane")
                    .font(.headline)
                    .foregroundStyle(.primary)
            }
            Section("Overview") {
                LabeledContent("Flights", value: store.summary.flightCount.formatted())
                LabeledContent("Total", value: LogbookFormatters.hours(store.summary.totalMinutes))
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 250)
    }

    @ViewBuilder private var detailView: some View {
        switch store.selectedSection ?? .dashboard {
        case .dashboard: DashboardView(store: store)
        case .flights: FlightsView(store: store)
        case .pages: LogbookPagesView(store: store)
        case .aircraft: AircraftView(store: store)
        case .people: PeopleView(store: store)
        case .analysis: AnalysisView(store: store)
        case .map: MapDashboardView(store: store)
        case .comparison: LogTenComparisonView(store: store)
        case .imports: ImportView(store: store)
        case .compliance: ComplianceView(store: store)
        case .reports: ReportsView(store: store)
        case .history: HistoryView(store: store)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: store.startNewFlight) { Label("New Flight", systemImage: "plus") }
                .help("New Flight (Command-N)")
                .accessibilityIdentifier("toolbar.newFlight")
            Button(action: { _ = store.saveDraft() }) { Label("Save Draft", systemImage: "square.and.arrow.down") }
                .disabled(!store.canSaveDraft)
                .help("Save Draft (Command-S)")
                .accessibilityIdentifier("toolbar.saveDraft")
            Button(action: store.refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
            Button(action: store.exportToRememberedFolder) { Label("Export CAA-format Report", systemImage: "square.and.arrow.up") }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 16) {
            Label("Local records", systemImage: "circle.fill").foregroundStyle(OpenPilotTheme.green)
            Text(store.statusMessage)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .accessibilityIdentifier("status.message")
            Spacer()
            Label(store.compliance.checkedFlights == 0 ? "No finalised entries checked" : (store.compliance.caaExportReady ? "Internal checks passed" : "Review needed"), systemImage: store.compliance.checkedFlights == 0 ? "doc.badge.clock" : (store.compliance.caaExportReady ? "checkmark.circle" : "exclamationmark.triangle"))
                .foregroundStyle(store.compliance.checkedFlights == 0 ? OpenPilotTheme.blue : (store.compliance.caaExportReady ? OpenPilotTheme.green : OpenPilotTheme.amber))
        }
        .font(.footnote)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
