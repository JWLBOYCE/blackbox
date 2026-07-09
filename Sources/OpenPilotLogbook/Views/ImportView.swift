import SwiftUI
import UniformTypeIdentifiers
import OpenPilotLogbookCore

struct ImportView: View {
    @ObservedObject var store: LogbookStore
    @State private var showImporter = false
    @State private var showLogTenImporter = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Import")
                        .font(.system(size: 34, weight: .semibold))
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

                    Button {
                        showImporter = true
                    } label: {
                        Label("Choose Files", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Panel("LogTen Pro Database", systemImage: "externaldrive.badge.plus") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose LogTenCoreDataStore.sql to replace the current Blackbox working database from a LogTen Pro source.")
                        .font(.callout)
                    Text("Blackbox opens the selected database read-only, creates a timestamped backup of the current Blackbox database, and imports using the same LogTen headings and mappings as the original migration.")
                        .font(.caption)
                        .foregroundStyle(OpenPilotTheme.muted)
                }
            }

            Panel("Review Queue", systemImage: "doc.viewfinder") {
                HStack(spacing: 10) {
                    Button("Import Selected", action: store.acceptSelectedImports)
                        .buttonStyle(.borderedProminent)
                        .disabled(store.selectedImportIDs.isEmpty)
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
            }
        }
        .padding(24)
        .navigationTitle("Import")
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
}
