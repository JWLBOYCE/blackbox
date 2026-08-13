import SwiftUI
import OpenPilotLogbookCore

struct ComplianceView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Logbook Checks")
                    .pageTitleStyle()
                Text("Internal completeness and consistency checks for finalised entries. These checks are not regulatory certification.")
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            HStack(spacing: 10) {
                MetricTile(title: "Checked", value: "\(store.compliance.checkedFlights)", systemImage: "checklist", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Issues", value: "\(store.compliance.issues.count)", systemImage: store.compliance.issues.isEmpty ? "checkmark.seal" : "exclamationmark.triangle", tint: store.compliance.issues.isEmpty ? OpenPilotTheme.green : OpenPilotTheme.amber)
                MetricTile(title: "Export Check", value: store.compliance.caaExportReady ? "Passed" : "Review", systemImage: "doc.badge.gearshape", tint: store.compliance.caaExportReady ? OpenPilotTheme.green : OpenPilotTheme.amber)
            }
            ReadinessStrip(isReady: store.compliance.caaExportReady, issueCount: store.compliance.issues.count, checkedCount: store.compliance.checkedFlights) {
                store.chooseAndExportReports()
            }
            Panel("Validation Issues", systemImage: "checkmark.shield") {
                Table(store.compliance.issues) {
                    TableColumn("Date") { issue in
                        Text(LogbookFormatters.dateFormatter.string(from: issue.date))
                    }
                    TableColumn("Field", value: \.field)
                    TableColumn("Issue", value: \.message)
                    TableColumn("Fix") { issue in
                        Text(issue.guidance.isEmpty ? "Review this entry and complete the missing field." : issue.guidance)
                    }
                    TableColumn("Flight ID") { issue in
                        Button("\(issue.flightID)") {
                            store.showFlight(id: issue.flightID)
                        }
                        .buttonStyle(.link)
                        .monospacedDigit()
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .navigationTitle("Logbook Checks")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("checks.screen")
    }
}
