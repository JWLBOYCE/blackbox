import SwiftUI
import OpenPilotLogbookCore

struct ContentView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, idealWidth: 245, maxWidth: 270)

            ZStack {
                OpenPilotTheme.background.ignoresSafeArea()
                detailView
            }
            .frame(minWidth: 880)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: store.startNewFlight) {
                    Label("New Flight", systemImage: "plus")
                }
                Button(action: store.refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button(action: store.exportReports) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 16) {
                Label("Local records", systemImage: "circle.fill")
                    .foregroundStyle(OpenPilotTheme.green)
                Text(store.statusMessage)
                    .foregroundStyle(OpenPilotTheme.muted)
                    .lineLimit(1)
                Spacer()
                Label(store.compliance.caaExportReady ? "CAA ready" : "Review needed", systemImage: store.compliance.caaExportReady ? "checkmark.circle" : "exclamationmark.triangle")
                    .foregroundStyle(store.compliance.caaExportReady ? OpenPilotTheme.green : OpenPilotTheme.amber)
            }
            .font(.footnote)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .appBackground()
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            sidebarHeader
            VStack(spacing: 5) {
                ForEach(AppSection.allCases) { section in
                    Button {
                        store.selectedSection = section
                    } label: {
                        SidebarRow(section: section, isSelected: store.selectedSection == section)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)

            Spacer(minLength: 12)
            sidebarSummary
                .padding(.bottom, 34)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.060, green: 0.095, blue: 0.125),
                    Color(red: 0.035, green: 0.055, blue: 0.070)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(OpenPilotTheme.border)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch store.selectedSection ?? .dashboard {
        case .dashboard:
            DashboardView(store: store)
        case .flights:
            FlightsView(store: store)
        case .aircraft:
            AircraftView(store: store)
        case .analysis:
            AnalysisView(store: store)
        case .map:
            MapDashboardView(store: store)
        case .comparison:
            LogTenComparisonView(store: store)
        case .imports:
            ImportView(store: store)
        case .compliance:
            ComplianceView(store: store)
        case .reports:
            ReportsView(store: store)
        }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(OpenPilotTheme.blue.gradient)
                Image(systemName: "airplane")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("Blackbox")
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text("CAA-ready flight records")
                    .font(.caption)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 10)
    }

    private var sidebarSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().opacity(0.35)
            VStack(alignment: .leading, spacing: 8) {
                Text("Overview")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OpenPilotTheme.muted)
                    .textCase(.uppercase)
                SummaryRow(label: "Flights", value: "\(store.summary.flightCount)")
                SummaryRow(label: "Total", value: LogbookFormatters.hours(store.summary.totalMinutes))
                SummaryRow(label: "Last 12 Months", value: LogbookFormatters.hours(hoursInLast12Months))
                SummaryRow(label: "Last Landing", value: lastLandingDate.map(LogbookFormatters.dateFormatter.string) ?? "None")
            }
            .padding(14)
            .background(OpenPilotTheme.panel, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
            .overlay {
                RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                    .stroke(OpenPilotTheme.border, lineWidth: 1)
            }
        }
        .padding(14)
    }

    private var hoursInLast12Months: Int {
        let threshold = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date.distantPast
        return store.flights
            .filter { $0.date >= threshold }
            .reduce(0) { $0 + $1.totalMinutes }
    }

    private var lastLandingDate: Date? {
        store.flights
            .filter { $0.totalLandings > 0 }
            .max(by: { $0.date < $1.date })?
            .date
    }
}

private struct SidebarRow: View {
    var section: AppSection
    var isSelected: Bool = false

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(section.rawValue)
                    .font(.callout.weight(.medium))
                Text(section.subtitle)
                    .font(.caption2)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
        } icon: {
            Image(systemName: section.icon)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 22)
        }
        .foregroundStyle(isSelected ? .white : .primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? OpenPilotTheme.blue.opacity(0.92) : Color.clear, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
    }
}

private struct SummaryRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(OpenPilotTheme.muted)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
                .lineLimit(1)
        }
        .font(.caption)
    }
}
