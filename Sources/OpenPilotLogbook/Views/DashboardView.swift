import SwiftUI
import OpenPilotLogbookCore

struct DashboardView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                metrics
                ReadinessStrip(
                    isReady: store.compliance.caaExportReady,
                    issueCount: store.compliance.issues.count
                ) {
                    store.selectedSection = .compliance
                }
                lowerGrid
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("Dashboard")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dashboard")
                    .font(.system(size: 36, weight: .semibold, design: .default))
                Text("Overview of your flying activity and CAA readiness.")
                    .font(.callout)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Loaded \(store.summary.flightCount.formatted()) flights")
                    .font(.callout.weight(.medium))
                Text(store.summary.lastFlightDate.map { "Last flight " + LogbookFormatters.dateFormatter.string(from: $0) } ?? "No flights loaded")
                    .font(.caption)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
        }
    }

    private var metrics: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
            MetricTile(title: "Flights", value: store.summary.flightCount.formatted(), systemImage: "airplane", tint: OpenPilotTheme.blue)
            MetricTile(title: "Total", value: LogbookFormatters.hours(store.summary.totalMinutes), systemImage: "clock", tint: OpenPilotTheme.cyan)
            MetricTile(title: "Co-pilot", value: LogbookFormatters.hours(store.summary.copilotMinutes), systemImage: "person.2", tint: OpenPilotTheme.cyan)
            MetricTile(title: "Co-pilot Day", value: LogbookFormatters.hours(store.summary.copilotDayMinutes), systemImage: "sun.max", tint: OpenPilotTheme.amber)
            MetricTile(title: "Co-pilot Night", value: LogbookFormatters.hours(store.summary.copilotNightMinutes), systemImage: "moon.stars", tint: OpenPilotTheme.blue)
            MetricTile(title: "Night", value: LogbookFormatters.hours(store.summary.nightMinutes), systemImage: "moon", tint: OpenPilotTheme.cyan)
            MetricTile(title: "Last 12 Months", value: LogbookFormatters.hours(store.recency.hoursLast12Months), systemImage: "calendar.badge.clock", tint: OpenPilotTheme.green)
            MetricTile(title: "90 Day Landings", value: "\(store.recency.landingsLast90Days)", systemImage: "arrow.down.to.line", tint: OpenPilotTheme.green)
            MetricTile(title: "Mapped NM", value: String(format: "%.0f", store.summary.distanceNM), systemImage: "globe.europe.africa", tint: OpenPilotTheme.blue)
            MetricTile(title: "Duplicates", value: "\(store.duplicateGroups.count)", systemImage: "doc.on.doc", tint: store.duplicateGroups.isEmpty ? OpenPilotTheme.green : OpenPilotTheme.amber)
        }
    }

    private var lowerGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                recentFlightsPanel
                    .frame(width: 860)
                VStack(spacing: 14) {
                    routesPanel
                        .frame(height: 340)
                    HStack(alignment: .top, spacing: 14) {
                        splitPanel
                        recencyPanel
                    }
                }
                .frame(width: 620)
            }

            VStack(alignment: .leading, spacing: 14) {
                routesPanel
                recentFlightsPanel
                HStack(alignment: .top, spacing: 14) {
                    splitPanel
                    recencyPanel
                }
            }
        }
    }

    private var recentFlightsPanel: some View {
        Panel("Recent Flights", systemImage: "list.bullet.rectangle") {
            recentFlights
        }
    }

    private var splitPanel: some View {
        Panel("Co-pilot Day / Night Split", systemImage: "chart.pie") {
            SplitRingChart(dayMinutes: store.summary.copilotDayMinutes, nightMinutes: store.summary.copilotNightMinutes)
            Divider().opacity(0.35)
            ProgressLine(
                title: "Night currency",
                value: LogbookFormatters.hours(store.summary.nightMinutes),
                progress: min(1, Double(store.summary.nightMinutes) / 5_400),
                tint: OpenPilotTheme.green
            )
        }
    }

    private var routesPanel: some View {
        Panel("Recent Routes", systemImage: "map") {
            RoutePreview(routes: store.visibleRoutes) {
                store.selectedSection = .map
            }
        }
    }

    private var recencyPanel: some View {
        Panel("Recency", systemImage: "calendar.badge.clock") {
            VStack(alignment: .leading, spacing: 12) {
                ProgressLine(title: "Last 90 days", value: LogbookFormatters.hours(store.recency.hoursLast90Days), progress: min(1, Double(store.recency.hoursLast90Days) / 6_000), tint: OpenPilotTheme.cyan)
                ProgressLine(title: "Instrument 90 days", value: LogbookFormatters.hours(store.recency.instrumentLast90Days), progress: min(1, Double(store.recency.instrumentLast90Days) / 360), tint: OpenPilotTheme.blue)
                Divider().opacity(0.35)
                DashboardSummaryRow(label: "Landings 90 days", value: "\(store.recency.landingsLast90Days)")
                DashboardSummaryRow(label: "Night landings 90 days", value: "\(store.recency.nightLandingsLast90Days)")
                DashboardSummaryRow(label: "Last landing", value: store.recency.daysSinceLastLanding.map { "\($0)d ago" } ?? "None")
                DashboardSummaryRow(label: "Last night landing", value: store.recency.daysSinceLastNightLanding.map { "\($0)d ago" } ?? "None")
            }
        }
    }

    private var recentFlights: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Date").frame(width: 110, alignment: .leading)
                Text("Aircraft").frame(width: 90, alignment: .leading)
                Text("Route").frame(maxWidth: .infinity, alignment: .leading)
                Text("Duration").frame(width: 88, alignment: .trailing)
                Text("Status").frame(width: 58, alignment: .trailing)
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(OpenPilotTheme.muted)
            .padding(.bottom, 8)

            ForEach(Array(store.flights.prefix(8))) { flight in
                HStack(spacing: 10) {
                    Text(LogbookFormatters.dateFormatter.string(from: flight.date))
                        .frame(width: 110, alignment: .leading)
                    Text(flight.aircraftID.isEmpty ? "Unknown" : flight.aircraftID)
                        .frame(width: 90, alignment: .leading)
                    Text(flight.routeDisplay.isEmpty ? "No route" : flight.routeDisplay.replacingOccurrences(of: " -> ", with: "->"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(1)
                    Text(LogbookFormatters.hours(flight.totalMinutes))
                        .font(.callout.monospacedDigit())
                        .frame(width: 88, alignment: .trailing)
                    StatusGlyph(ok: flight.totalMinutes > 0 && !flight.aircraftID.isEmpty)
                        .frame(width: 58, alignment: .trailing)
                }
                .font(.callout)
                .padding(.vertical, 8)
                Divider().opacity(0.22)
            }

            HStack {
                Button("View All Flights") { store.selectedSection = .flights }
                    .buttonStyle(.bordered)
                Spacer()
                Text("Showing \(min(8, store.flights.count)) of \(store.flights.count.formatted())")
                    .font(.caption)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            .padding(.top, 12)
        }
    }
}

private struct DashboardSummaryRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(OpenPilotTheme.muted)
            Spacer()
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .font(.caption)
    }
}

private struct RoutePreview: View {
    var routes: [MapRoute]
    var onOpen: () -> Void
    private var isSnapshot: Bool {
        ProcessInfo.processInfo.environment["OPENPILOT_SNAPSHOT_PATH"] != nil
    }

    var body: some View {
        ZStack {
            globe
                .clipShape(RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
            LinearGradient(
                colors: [Color.black.opacity(0.08), Color.black.opacity(0.34)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
            VStack {
                Spacer()
                HStack {
                    Button("Open 3D Map", action: onOpen)
                        .buttonStyle(.bordered)
                    Spacer()
                    Label("\(routes.count.formatted()) routes", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .font(.caption)
                        .foregroundStyle(OpenPilotTheme.muted)
                }
                .padding(14)
            }
        }
        .frame(minHeight: 300)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dashboard route globe")
        .accessibilityValue("\(routes.count.formatted()) mapped routes")
    }

    @ViewBuilder
    private var globe: some View {
        if isSnapshot {
            BlueMarbleGlobeCanvas(routes: routes)
        } else {
            WorldSceneView(routes: routes, routeLimit: 700, allowsCameraControl: false, cameraDistance: 6.1)
        }
    }
}
