import SwiftUI
import OpenPilotLogbookCore

struct LogTenComparisonView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                statusStrip
                totalsPanel
                blackboxOnlyPanel
                issuesPanel
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Compare")
        .onAppear {
            if store.logTenComparison.logTen.flightCount == 0 {
                store.refreshLogTenComparison()
            }
        }
    }

    private var snapshot: LogTenComparisonSnapshot { store.logTenComparison }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LogTen Comparison")
                    .font(.system(size: 34, weight: .semibold))
                Text(snapshot.sourceIsLiveLogTen ? "Live LogTen Pro source, opened read-only." : "Backup LogTen source, opened read-only.")
                    .font(.callout)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            Button {
                store.refreshLogTenComparison()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 18) {
            Image(systemName: snapshot.importedRowsMatch ? "checkmark.seal" : "exclamationmark.triangle")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(snapshot.importedRowsMatch ? OpenPilotTheme.green : OpenPilotTheme.amber)
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.importedRowsMatch ? "Imported LogTen Rows Match" : "Review Differences")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(snapshot.importedRowsMatch ? OpenPilotTheme.green : OpenPilotTheme.amber)
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
        }
        .padding(18)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(snapshot.importedRowsMatch ? OpenPilotTheme.green.opacity(0.35) : OpenPilotTheme.amber.opacity(0.45), lineWidth: 1)
        }
    }

    private var statusText: String {
        if snapshot.importedRowsMatch {
            return "All LogTen-sourced rows match Blackbox imports; Blackbox-only entries are shown separately."
        }
        return "\(snapshot.issues.count) field differences, \(snapshot.missingInBlackbox) missing in Blackbox, \(snapshot.missingInLogTen) missing in LogTen."
    }

    private var totalsPanel: some View {
        Panel("Side by Side Totals", systemImage: "rectangle.split.3x1") {
            VStack(spacing: 0) {
                ComparisonHeader()
                ForEach(comparisonRows, id: \.title) { row in
                    ComparisonRow(row: row)
                    Divider().opacity(0.22)
                }
            }
        }
    }

    private var blackboxOnlyPanel: some View {
        Panel("Blackbox-only Entries", systemImage: "plus.rectangle.on.folder") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                MetricTile(title: "Entries", value: snapshot.blackboxOnly.flightCount.formatted(), systemImage: "airplane", tint: OpenPilotTheme.blue)
                MetricTile(title: "Total", value: LogbookFormatters.hours(snapshot.blackboxOnly.totalMinutes), systemImage: "clock", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Co-pilot", value: LogbookFormatters.hours(snapshot.blackboxOnly.copilotMinutes), systemImage: "person.2", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Night", value: LogbookFormatters.hours(snapshot.blackboxOnly.nightMinutes), systemImage: "moon", tint: OpenPilotTheme.blue)
            }
        }
    }

    @ViewBuilder
    private var issuesPanel: some View {
        Panel("Differences", systemImage: "checklist") {
            if snapshot.issues.isEmpty && snapshot.missingInBlackbox == 0 && snapshot.missingInLogTen == 0 {
                EmptyStateBlock(title: "No Differences", message: "The LogTen-sourced rows line up with the imported Blackbox rows.", systemImage: "checkmark.circle")
                    .frame(minHeight: 180)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Date").frame(width: 96, alignment: .leading)
                        Text("Route").frame(width: 120, alignment: .leading)
                        Text("Field").frame(width: 130, alignment: .leading)
                        Text("LogTen Pro").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Blackbox").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OpenPilotTheme.muted)
                    .padding(.bottom, 8)

                    ForEach(snapshot.issues.prefix(80)) { issue in
                        HStack(alignment: .top, spacing: 10) {
                            Text(LogbookFormatters.dateFormatter.string(from: issue.date))
                                .frame(width: 96, alignment: .leading)
                            Text(issue.route.isEmpty ? "-" : issue.route.replacingOccurrences(of: " -> ", with: "->"))
                                .frame(width: 120, alignment: .leading)
                                .lineLimit(1)
                            Text(issue.field)
                                .frame(width: 130, alignment: .leading)
                            Text(issue.logTenValue.isEmpty ? "-" : issue.logTenValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                            Text(issue.blackboxValue.isEmpty ? "-" : issue.blackboxValue)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(2)
                        }
                        .font(.callout)
                        .padding(.vertical, 7)
                        Divider().opacity(0.18)
                    }
                }
            }
        }
    }

    private var comparisonRows: [ComparisonValueRow] {
        [
            row("Flights", "\(snapshot.logTen.flightCount)", "\(snapshot.blackboxImported.flightCount)", "\(snapshot.blackboxAll.flightCount)"),
            row("Total", LogbookFormatters.hours(snapshot.logTen.totalMinutes), LogbookFormatters.hours(snapshot.blackboxImported.totalMinutes), LogbookFormatters.hours(snapshot.blackboxAll.totalMinutes)),
            row("PIC", LogbookFormatters.hours(snapshot.logTen.picMinutes), LogbookFormatters.hours(snapshot.blackboxImported.picMinutes), LogbookFormatters.hours(snapshot.blackboxAll.picMinutes)),
            row("Co-pilot", LogbookFormatters.hours(snapshot.logTen.copilotMinutes), LogbookFormatters.hours(snapshot.blackboxImported.copilotMinutes), LogbookFormatters.hours(snapshot.blackboxAll.copilotMinutes)),
            row("Co-pilot day", LogbookFormatters.hours(snapshot.logTen.copilotDayMinutes), LogbookFormatters.hours(snapshot.blackboxImported.copilotDayMinutes), LogbookFormatters.hours(snapshot.blackboxAll.copilotDayMinutes)),
            row("Co-pilot night", LogbookFormatters.hours(snapshot.logTen.copilotNightMinutes), LogbookFormatters.hours(snapshot.blackboxImported.copilotNightMinutes), LogbookFormatters.hours(snapshot.blackboxAll.copilotNightMinutes)),
            row("Night", LogbookFormatters.hours(snapshot.logTen.nightMinutes), LogbookFormatters.hours(snapshot.blackboxImported.nightMinutes), LogbookFormatters.hours(snapshot.blackboxAll.nightMinutes)),
            row("Landings", "\(snapshot.logTen.landings)", "\(snapshot.blackboxImported.landings)", "\(snapshot.blackboxAll.landings)"),
            row("Nautical miles", String(format: "%.0f", snapshot.logTen.distanceNM), String(format: "%.0f", snapshot.blackboxImported.distanceNM), String(format: "%.0f", snapshot.blackboxAll.distanceNM))
        ]
    }

    private func row(_ title: String, _ logTen: String, _ imported: String, _ all: String) -> ComparisonValueRow {
        ComparisonValueRow(title: title, logTen: logTen, blackboxImported: imported, blackboxAll: all)
    }
}

private struct ComparisonValueRow {
    var title: String
    var logTen: String
    var blackboxImported: String
    var blackboxAll: String
}

private struct ComparisonHeader: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("Metric").frame(width: 150, alignment: .leading)
            Text("LogTen Pro").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Blackbox Imported").frame(maxWidth: .infinity, alignment: .trailing)
            Text("Blackbox All").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(OpenPilotTheme.muted)
        .padding(.bottom, 8)
    }
}

private struct ComparisonRow: View {
    var row: ComparisonValueRow

    var body: some View {
        HStack(spacing: 10) {
            Text(row.title)
                .foregroundStyle(OpenPilotTheme.muted)
                .frame(width: 150, alignment: .leading)
            Text(row.logTen)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.blackboxImported)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(row.blackboxAll)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout.monospacedDigit())
        .padding(.vertical, 8)
    }
}
