import SwiftUI
import OpenPilotLogbookCore

struct ReportsView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Reports")
                    .font(.system(size: 34, weight: .semibold))
                Text("Generate CAA-style CSV and print-ready HTML with page totals.")
                    .foregroundStyle(OpenPilotTheme.muted)
            }

            HStack(spacing: 10) {
                MetricTile(title: "Flights", value: "\(store.summary.flightCount)", systemImage: "airplane", tint: OpenPilotTheme.blue)
                MetricTile(title: "Total", value: LogbookFormatters.hours(store.summary.totalMinutes), systemImage: "clock", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Co-pilot", value: LogbookFormatters.hours(store.summary.copilotMinutes), systemImage: "person.2", tint: OpenPilotTheme.cyan)
            }

            Panel("Export Pack", systemImage: "doc.text") {
                HStack(spacing: 12) {
                    Button {
                        store.exportReports()
                    } label: {
                        Label("Export CAA CSV and HTML", systemImage: "square.and.arrow.up")
                            .frame(minWidth: 210)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        NSWorkspace.shared.open(store.paths.backupFolder)
                    } label: {
                        Label("Show Exports", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
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
            Spacer()
        }
        .padding(24)
        .navigationTitle("Reports")
    }
}
