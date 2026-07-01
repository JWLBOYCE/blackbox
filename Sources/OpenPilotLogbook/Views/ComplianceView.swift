import SwiftUI
import OpenPilotLogbookCore

struct ComplianceView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("CAA Check")
                    .font(.system(size: 34, weight: .semibold))
                Text("FCL.050 readiness for your electronic and printable logbook.")
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            HStack(spacing: 10) {
                MetricTile(title: "Checked", value: "\(store.compliance.checkedFlights)", systemImage: "checklist", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Issues", value: "\(store.compliance.issues.count)", systemImage: store.compliance.issues.isEmpty ? "checkmark.seal" : "exclamationmark.triangle", tint: store.compliance.issues.isEmpty ? OpenPilotTheme.green : OpenPilotTheme.amber)
                MetricTile(title: "CAA Export", value: store.compliance.caaExportReady ? "Ready" : "Review", systemImage: "doc.badge.gearshape", tint: store.compliance.caaExportReady ? OpenPilotTheme.green : OpenPilotTheme.amber)
            }
            ReadinessStrip(isReady: store.compliance.caaExportReady, issueCount: store.compliance.issues.count) {
                store.exportReports()
            }
            Panel("Validation Issues", systemImage: "checkmark.shield") {
                Table(store.compliance.issues) {
                    TableColumn("Date") { issue in
                        Text(LogbookFormatters.dateFormatter.string(from: issue.date))
                    }
                    TableColumn("Field", value: \.field)
                    TableColumn("Issue", value: \.message)
                    TableColumn("Flight ID") { issue in
                        Text("\(issue.flightID)").monospacedDigit()
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .navigationTitle("CAA Check")
    }
}
