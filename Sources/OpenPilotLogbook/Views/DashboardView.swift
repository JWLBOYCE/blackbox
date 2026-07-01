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
            MetricTile(title: "Mapped NM", value: String(format: "%.0f", store.summary.distanceNM), systemImage: "globe.europe.africa", tint: OpenPilotTheme.blue)
            MetricTile(title: "Landings", value: store.summary.landings.formatted(), systemImage: "arrow.down.to.line", tint: OpenPilotTheme.green)
        }
    }

    private var lowerGrid: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                recentFlightsPanel
                    .frame(minWidth: 500)
                splitPanel
                    .frame(width: 290)
                routesPanel
                    .frame(width: 300)
            }

            VStack(alignment: .leading, spacing: 14) {
                recentFlightsPanel
                HStack(alignment: .top, spacing: 14) {
                    splitPanel
                    routesPanel
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

private struct RoutePreview: View {
    var routes: [MapRoute]
    var onOpen: () -> Void

    var body: some View {
        ZStack {
            EarthGlobePreview(routes: routes)
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
        .frame(minHeight: 260)
    }
}

private struct EarthGlobePreview: View {
    var routes: [MapRoute]
    private let centerLongitude = -18.0
    private let centerLatitude = 28.0

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let center = CGPoint(x: size.width * 0.50, y: size.height * 0.47)
            let radius = min(size.width, size.height) * 0.43
            let globeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)

            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [Color(red: 0.010, green: 0.035, blue: 0.055), Color(red: 0.018, green: 0.070, blue: 0.105)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            ))
            context.fill(Path(ellipseIn: globeRect), with: .radialGradient(
                Gradient(colors: [
                    Color(red: 0.055, green: 0.190, blue: 0.275),
                    Color(red: 0.025, green: 0.085, blue: 0.145),
                    Color(red: 0.005, green: 0.020, blue: 0.035)
                ]),
                center: CGPoint(x: center.x - radius * 0.28, y: center.y - radius * 0.32),
                startRadius: radius * 0.05,
                endRadius: radius
            ))

            var clipped = context
            clipped.clip(to: Path(ellipseIn: globeRect))
            drawGraticule(context: &clipped, center: center, radius: radius)
            drawLand(context: &clipped, center: center, radius: radius)
            drawRoutes(context: &clipped, center: center, radius: radius)

            context.stroke(Path(ellipseIn: globeRect), with: .color(OpenPilotTheme.cyan.opacity(0.32)), lineWidth: 1.4)
            context.stroke(Path(ellipseIn: globeRect.insetBy(dx: -3, dy: -3)), with: .color(OpenPilotTheme.cyan.opacity(0.12)), lineWidth: 6)
        }
    }

    private func drawGraticule(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            var path = Path()
            var didMove = false
            for longitude in stride(from: -180.0, through: 180.0, by: 4.0) {
                guard let point = project(latitude: latitude, longitude: longitude, center: center, radius: radius) else {
                    didMove = false
                    continue
                }
                if didMove { path.addLine(to: point) } else { path.move(to: point); didMove = true }
            }
            context.stroke(path, with: .color(.white.opacity(0.11)), lineWidth: 0.8)
        }
        for longitude in stride(from: -180.0, through: 180.0, by: 30.0) {
            var path = Path()
            var didMove = false
            for latitude in stride(from: -80.0, through: 80.0, by: 4.0) {
                guard let point = project(latitude: latitude, longitude: longitude, center: center, radius: radius) else {
                    didMove = false
                    continue
                }
                if didMove { path.addLine(to: point) } else { path.move(to: point); didMove = true }
            }
            context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.8)
        }
    }

    private func drawLand(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        let landmasses: [[(Double, Double)]] = [
            [(-10, 35), (5, 58), (38, 60), (70, 52), (100, 58), (145, 45), (136, 18), (100, 8), (72, 20), (40, 25), (18, 36)],
            [(-18, 35), (28, 32), (50, 8), (42, -25), (20, -35), (2, -20), (-9, 5)],
            [(-168, 70), (-140, 68), (-105, 58), (-86, 48), (-78, 30), (-96, 18), (-116, 25), (-132, 45), (-155, 54)],
            [(-83, 12), (-65, 5), (-50, -12), (-54, -34), (-70, -55), (-78, -28)],
            [(108, -12), (154, -10), (154, -36), (122, -42), (112, -26)]
        ]
        for landmass in landmasses {
            var path = Path()
            var started = false
            for coordinate in landmass {
                guard let point = project(latitude: coordinate.1, longitude: coordinate.0, center: center, radius: radius) else { continue }
                if started { path.addLine(to: point) } else { path.move(to: point); started = true }
            }
            if started {
                path.closeSubpath()
                context.fill(path, with: .color(Color(red: 0.230, green: 0.420, blue: 0.255).opacity(0.84)))
                context.stroke(path, with: .color(Color(red: 0.480, green: 0.640, blue: 0.400).opacity(0.32)), lineWidth: 0.8)
            }
        }
    }

    private func drawRoutes(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for route in routes.prefix(90) {
            guard
                let start = project(latitude: route.departureLatitude, longitude: route.departureLongitude, center: center, radius: radius),
                let end = project(latitude: route.arrivalLatitude, longitude: route.arrivalLongitude, center: center, radius: radius)
            else { continue }
            let lift = min(42, max(12, hypot(start.x - end.x, start.y - end.y) * 0.18))
            var path = Path()
            path.move(to: start)
            path.addQuadCurve(to: end, control: CGPoint(x: (start.x + end.x) / 2, y: min(start.y, end.y) - lift))
            context.stroke(path, with: .color(OpenPilotTheme.cyan.opacity(0.58)), lineWidth: 1.1)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 1.7, y: start.y - 1.7, width: 3.4, height: 3.4)), with: .color(.white.opacity(0.75)))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 1.7, y: end.y - 1.7, width: 3.4, height: 3.4)), with: .color(.white.opacity(0.75)))
        }
    }

    private func project(latitude: Double, longitude: Double, center: CGPoint, radius: CGFloat) -> CGPoint? {
        let lat = latitude * .pi / 180
        let lon = (longitude - centerLongitude) * .pi / 180
        let lat0 = centerLatitude * .pi / 180
        let visible = sin(lat0) * sin(lat) + cos(lat0) * cos(lat) * cos(lon)
        guard visible >= -0.03 else { return nil }
        let x = radius * CGFloat(cos(lat) * sin(lon))
        let y = -radius * CGFloat(cos(lat0) * sin(lat) - sin(lat0) * cos(lat) * cos(lon))
        return CGPoint(x: center.x + x, y: center.y + y)
    }
}
