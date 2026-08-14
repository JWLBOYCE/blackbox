import SwiftUI
import OpenPilotLogbookCore

struct ContentView: View {
    @ObservedObject var store: LogbookStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.blackboxReduceMotionOverride) private var testReduceMotion

    private var reduceMotion: Bool { systemReduceMotion || testReduceMotion }
    var body: some View {
        ZStack {
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
            .disabled(store.showExportConfirmation)
            .accessibilityHidden(store.showExportConfirmation)

            if store.showExportConfirmation {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
                    .onTapGesture { }

                ExportConfirmationOverlay(store: store)
                    .padding(24)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(1)
            }
        }
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
        .transaction { transaction in if reduceMotion { transaction.animation = nil } }
    }

    private var sidebar: some View {
        List(selection: Binding(get: { store.selectedSection }, set: store.requestSection)) {
            Section {
                ForEach(AppSection.allCases) { section in
                    Button {
                        store.requestSection(section)
                    } label: {
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
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .tag(section as AppSection?)
                    .accessibilityElement(children: .combine)
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

private struct ExportConfirmationOverlay: View {
    @ObservedObject var store: LogbookStore

    private var recordDescription: String {
        let count = store.exportPreviewFlights.count
        return "\(count) finalised active record\(count == 1 ? "" : "s")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title2)
                    .foregroundStyle(OpenPilotTheme.blue)
                    .accessibilityHidden(true)
                Text("Confirm CAA-format Export")
                    .font(.title2.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("reports.exportConfirmation.title")
            }

            Text("Export exactly \(recordDescription) using the visible filters.")
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Text("Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(store.pendingExportDestinationName)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("reports.exportConfirmation.destination")
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 8) {
                Label("Drafts, superseded entries, and Trash are excluded.", systemImage: "line.3.horizontal.decrease.circle")
                Label("This export is not regulatory certification.", systemImage: "info.circle")
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", role: .cancel, action: store.cancelExport)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("reports.exportConfirmation.cancel")
                Button("Export CAA-format Report", action: store.confirmExport)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("reports.exportConfirmation.confirm")
            }
        }
        .padding(24)
        .frame(minWidth: 500, idealWidth: 600, maxWidth: 680)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .stroke(.separator.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.3), radius: 24, y: 12)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reports.exportConfirmation")
    }
}
