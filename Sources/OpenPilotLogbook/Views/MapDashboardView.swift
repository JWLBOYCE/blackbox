import SwiftUI
import OpenPilotLogbookCore

struct MapDashboardView: View {
    @ObservedObject var store: LogbookStore
    @State private var showAirports = true
    private let renderedRouteLimit = 1_200
    private var isSnapshot: Bool {
        ProcessInfo.processInfo.environment["OPENPILOT_SNAPSHOT_PATH"] != nil
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            globeSurface

            GeometryReader { geometry in
                let isCompact = geometry.size.width < 1_050

                VStack(alignment: .leading, spacing: 16) {
                    mapControlPanel(isCompact: isCompact)
                    Spacer(minLength: 16)
                    HStack {
                        Spacer()
                        bottomControls
                    }
                }
                .padding(isCompact ? 16 : 24)
                // Keep the native menu's full hit target above the hosted
                // window edge when CI constrains the requested window to the
                // runner display's available height.
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("3D Map")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("3D route map")
        .accessibilityValue(routeSubtitle)
        .accessibilityIdentifier("map.screen")
    }

    @ViewBuilder
    private func mapControlPanel(isCompact: Bool) -> some View {
        VStack(alignment: .leading, spacing: isCompact ? 12 : 10) {
            if isCompact {
                FlightFilterBar(query: store.flightQuery, resultCount: store.flights.count, reset: store.resetFlightFilters)
                HStack(alignment: .top, spacing: 12) {
                    mapTitle
                    Spacer(minLength: 8)
                    queryEditor
                }
                Divider()
                compactControlGrid
            } else {
                HStack(spacing: 12) {
                    FlightFilterBar(query: store.flightQuery, resultCount: store.flights.count, reset: store.resetFlightFilters)
                    Spacer(minLength: 12)
                    queryEditor
                }
                Divider()
                regularControlRow
            }
        }
        .padding(isCompact ? 14 : 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner + 2))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner + 2)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("map.controls")
    }

    private var regularControlRow: some View {
        HStack(alignment: .center, spacing: 10) {
            mapTitle
                .frame(width: 220, alignment: .leading)
            Spacer(minLength: 8)
            rangePicker
                .frame(width: 120)
            aircraftPicker
                .frame(width: 140)
            typePicker
                .frame(width: 120)
            airportsToggle
            showAllRoutesButton
            distanceMetric
            shownMetric
        }
    }

    private var compactControlGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150, maximum: 210), spacing: 10, alignment: .leading)],
            alignment: .leading,
            spacing: 10
        ) {
            rangePicker
                .frame(maxWidth: .infinity)
            aircraftPicker
                .frame(maxWidth: .infinity)
            typePicker
                .frame(maxWidth: .infinity)
            airportsToggle
                .frame(maxWidth: .infinity)
            showAllRoutesButton
                .frame(maxWidth: .infinity, alignment: .leading)
            distanceMetric
                .frame(maxWidth: .infinity)
            shownMetric
                .frame(maxWidth: .infinity)
        }
    }

    private var mapTitle: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("3D Route Map")
                .pageTitleStyle()
            Text(routeSubtitle)
                .font(.subheadline)
                .foregroundStyle(OpenPilotTheme.muted)
                .lineLimit(2)
        }
        .accessibilityElement(children: .combine)
    }

    private var queryEditor: some View {
        FlightQueryEditor(
            query: store.flightQuery,
            aircraftIDs: store.availableAircraftIDs,
            aircraftTypes: store.availableAircraftTypes,
            pilotFunctions: store.availablePilotFunctions,
            operations: store.availableOperations,
            entryKinds: store.availableEntryKinds,
            apply: { store.applyFlightQuery($0) }
        )
    }

    private var rangePicker: some View {
        Picker("Range", selection: rangeBinding) {
            ForEach(MapRange.allCases) { Text($0.title).tag($0) }
        }
        .accessibilityIdentifier("map.filter.range")
    }

    private var aircraftPicker: some View {
        Picker("Aircraft", selection: aircraftBinding) {
            Text("All Aircraft").tag("All Aircraft")
            ForEach(Array(Set(store.routes.map(\.aircraftID))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag($0) }
        }
        .accessibilityIdentifier("map.filter.aircraft")
    }

    private var typePicker: some View {
        Picker("Type", selection: typeBinding) {
            Text("All Types").tag("All Types")
            ForEach(Array(Set(store.routes.map(\.entryKind))).sorted(), id: \.self) { Text($0).tag($0) }
        }
        .accessibilityIdentifier("map.filter.type")
    }

    private var airportsToggle: some View {
        Toggle(isOn: $showAirports) {
            Label("Airports", systemImage: "mappin.and.ellipse")
        }
        .toggleStyle(.switch)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
        .accessibilityIdentifier("map.filter.airports")
    }

    @ViewBuilder
    private var showAllRoutesButton: some View {
        if !store.selectedRouteFlightIDs.isEmpty {
            Button("Show All Routes") {
                store.showAllRoutes()
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("map.showAllRoutes")
        }
    }

    private var distanceMetric: some View {
        MapOverlayMetric(
            title: store.selectedRouteFlightIDs.isEmpty ? "Total NM" : "Selected NM",
            value: String(format: "%.0f", routeDistanceNM),
            systemImage: "globe.europe.africa"
        )
    }

    private var shownMetric: some View {
        MapOverlayMetric(title: "Shown", value: shownRouteText, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
    }

    private var bottomControls: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(filteredRoutes.prefix(20)) { route in
                    Button("\(route.departure) → \(route.arrival) · \(LogbookFormatters.dateFormatter.string(from: route.date))") {
                        store.showFlight(id: route.id)
                    }
                    .accessibilityIdentifier("map.route.\(route.id)")
                }
            } label: {
                Label("Open a shown flight", systemImage: "list.bullet")
            }
            .accessibilityIdentifier("map.openFlight")
            Label("Drag to rotate. Scroll to zoom.", systemImage: "globe")
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var globeSurface: some View {
        if isSnapshot {
            BlueMarbleGlobeCanvas(routes: filteredRoutes, showAirports: showAirports)
                .ignoresSafeArea()
        } else {
            WorldSceneView(routes: filteredRoutes, routeLimit: renderedRouteLimit, cameraDistance: 5.8, showAirports: showAirports)
                .ignoresSafeArea()
        }
        LinearGradient(
            colors: [
                Color.black.opacity(0.48),
                Color.black.opacity(0.10),
                Color.black.opacity(0.32)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var routeSubtitle: String {
        if store.selectedRouteFlightIDs.isEmpty {
            return "\(filteredRoutes.count.formatted()) filtered geocoded routes from \(store.flights.count.formatted()) flights"
        }
        if filteredRoutes.count == 1 {
            let route = filteredRoutes[0]
            return "Selected route \(route.departure) -> \(route.arrival)"
        }
        return "\(filteredRoutes.count.formatted()) selected routes"
    }

    private var routeDistanceNM: Double {
        if store.selectedRouteFlightIDs.isEmpty {
            return store.flights.reduce(0) { $0 + $1.distanceNM }
        }
        return filteredRoutes.reduce(0) { $0 + $1.distanceNM }
    }

    private var shownRouteText: String {
        let shown = min(filteredRoutes.count, renderedRouteLimit)
        if shown == filteredRoutes.count {
            return shown.formatted()
        }
        return "\(shown.formatted())/\(filteredRoutes.count.formatted())"
    }

    private var filteredRoutes: [MapRoute] {
        let queryFlightIDs = Set(store.flights.compactMap(\.id))
        return store.visibleRoutes.filter { queryFlightIDs.contains($0.id) }
    }

    private var rangeBinding: Binding<MapRange> {
        Binding(get: {
            guard let start = store.flightQuery.startDate else { return .all }
            let days = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
            return days <= 95 ? .ninetyDays : .twelveMonths
        }, set: { range in
            var query = store.flightQuery
            switch range {
            case .all: query.startDate = nil; query.endDate = nil
            case .ninetyDays: query.startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()); query.endDate = Date()
            case .twelveMonths: query.startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()); query.endDate = Date()
            }
            store.applyFlightQuery(query)
        })
    }

    private var aircraftBinding: Binding<String> {
        Binding(get: { store.flightQuery.aircraftIDs.first ?? "All Aircraft" }, set: { aircraft in
            var query = store.flightQuery
            query.aircraftIDs = aircraft == "All Aircraft" ? [] : [aircraft]
            store.applyFlightQuery(query)
        })
    }

    private var typeBinding: Binding<String> {
        Binding(get: { store.flightQuery.entryKinds.first ?? "All Types" }, set: { type in
            var query = store.flightQuery
            query.entryKinds = type == "All Types" ? [] : [type]
            store.applyFlightQuery(query)
        })
    }
}

private enum MapRange: String, CaseIterable, Identifiable {
    case all, ninetyDays, twelveMonths
    var id: String { rawValue }
    var title: String { self == .all ? "All time" : (self == .ninetyDays ? "90 days" : "12 months") }
}

private struct MapOverlayMetric: View {
    var title: String
    var value: String
    var systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(OpenPilotTheme.cyan)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(title.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(OpenPilotTheme.muted)
                Text(value)
                    .font(.headline.monospacedDigit().weight(.semibold))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
    }
}

struct BlueMarbleGlobeCanvas: View {
    var routes: [MapRoute]
    var showAirports = false
    private let centerLongitude = 22.0
    private let centerLatitude = 16.0

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(Path(rect), with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.005, green: 0.014, blue: 0.024),
                    Color(red: 0.010, green: 0.038, blue: 0.055),
                    Color.black
                ]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY),
                endPoint: CGPoint(x: rect.maxX, y: rect.maxY)
            ))

            let radius = min(size.width, size.height) * 0.39
            let center = CGPoint(x: size.width * 0.58, y: size.height * 0.53)
            let globeRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            var globeContext = context
            globeContext.clip(to: Path(ellipseIn: globeRect))
            drawBlueMarble(context: &globeContext, center: center, radius: radius)
            drawGraticule(context: &globeContext, center: center, radius: radius)
            drawRoutes(context: &globeContext, center: center, radius: radius)
            if showAirports {
                drawAirports(context: &globeContext, center: center, radius: radius)
            }

            context.fill(Path(ellipseIn: globeRect), with: .radialGradient(
                Gradient(colors: [
                    Color.white.opacity(0.22),
                    Color.clear,
                    Color.black.opacity(0.42)
                ]),
                center: CGPoint(x: center.x - radius * 0.30, y: center.y - radius * 0.35),
                startRadius: radius * 0.02,
                endRadius: radius * 1.05
            ))
            context.stroke(Path(ellipseIn: globeRect), with: .color(OpenPilotTheme.cyan.opacity(0.42)), lineWidth: 1.5)
            context.stroke(Path(ellipseIn: globeRect.insetBy(dx: -5, dy: -5)), with: .color(OpenPilotTheme.cyan.opacity(0.16)), lineWidth: 10)
        }
        .accessibilityLabel("Route globe")
        .accessibilityValue("\(routes.count.formatted()) mapped routes")
    }

    private func drawBlueMarble(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        guard let image = Self.texture else { return }
        let symbol = Image(nsImage: image)
        let textureWidth = radius * 4.0
        let textureHeight = radius * 2.0
        let xOffset = CGFloat((centerLongitude + 180) / 360) * textureWidth
        let yOffset = CGFloat((90 - centerLatitude) / 180) * textureHeight
        let baseX = center.x - xOffset
        let baseY = center.y - yOffset
        for dx in stride(from: -textureWidth * 2, through: textureWidth * 2, by: textureWidth) {
            context.draw(symbol, in: CGRect(x: baseX + dx, y: baseY, width: textureWidth, height: textureHeight))
        }
    }

    private func drawGraticule(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for latitude in stride(from: -60.0, through: 60.0, by: 30.0) {
            var path = Path()
            var didMove = false
            for longitude in stride(from: -180.0, through: 180.0, by: 3.0) {
                guard let point = project(latitude: latitude, longitude: longitude, center: center, radius: radius) else {
                    didMove = false
                    continue
                }
                if didMove { path.addLine(to: point) } else { path.move(to: point); didMove = true }
            }
            context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 0.8)
        }
        for longitude in stride(from: -180.0, through: 180.0, by: 30.0) {
            var path = Path()
            var didMove = false
            for latitude in stride(from: -80.0, through: 80.0, by: 3.0) {
                guard let point = project(latitude: latitude, longitude: longitude, center: center, radius: radius) else {
                    didMove = false
                    continue
                }
                if didMove { path.addLine(to: point) } else { path.move(to: point); didMove = true }
            }
            context.stroke(path, with: .color(.white.opacity(0.10)), lineWidth: 0.8)
        }
    }

    private func drawRoutes(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for route in routes.prefix(320) {
            guard
                let start = project(latitude: route.departureLatitude, longitude: route.departureLongitude, center: center, radius: radius),
                let end = project(latitude: route.arrivalLatitude, longitude: route.arrivalLongitude, center: center, radius: radius)
            else { continue }
            var path = Path()
            path.move(to: start)
            let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 - min(80, hypot(start.x - end.x, start.y - end.y) * 0.16))
            path.addQuadCurve(to: end, control: mid)
            context.stroke(path, with: .color(OpenPilotTheme.cyan.opacity(0.48)), lineWidth: 1.0)
            context.fill(Path(ellipseIn: CGRect(x: start.x - 2, y: start.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.70)))
            context.fill(Path(ellipseIn: CGRect(x: end.x - 2, y: end.y - 2, width: 4, height: 4)), with: .color(.white.opacity(0.70)))
        }
    }

    private func drawAirports(context: inout GraphicsContext, center: CGPoint, radius: CGFloat) {
        for airport in airportMarkers.prefix(240) {
            guard let point = project(latitude: airport.latitude, longitude: airport.longitude, center: center, radius: radius) else { continue }
            context.fill(Path(ellipseIn: CGRect(x: point.x - 3.2, y: point.y - 3.2, width: 6.4, height: 6.4)), with: .color(OpenPilotTheme.amber.opacity(0.92)))
            context.stroke(Path(ellipseIn: CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13)), with: .color(OpenPilotTheme.amber.opacity(0.22)), lineWidth: 1.2)
        }
    }

    private var airportMarkers: [AirportMarker] {
        var seen = Set<String>()
        var markers: [AirportMarker] = []

        func add(_ code: String, latitude: Double, longitude: Double) {
            let fallbackCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !fallbackCode.isEmpty else { return }
            let airport = AirportCoordinateService.shared.airport(for: fallbackCode)
            let key = airport?.identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? fallbackCode
            guard !seen.contains(key) else { return }
            seen.insert(key)
            markers.append(AirportMarker(
                latitude: airport?.latitude ?? latitude,
                longitude: airport?.longitude ?? longitude
            ))
        }

        for route in routes.prefix(700) {
            add(route.departure, latitude: route.departureLatitude, longitude: route.departureLongitude)
            add(route.arrival, latitude: route.arrivalLatitude, longitude: route.arrivalLongitude)
        }
        return markers
    }

    private struct AirportMarker {
        var latitude: Double
        var longitude: Double
    }

    private func project(latitude: Double, longitude: Double, center: CGPoint, radius: CGFloat) -> CGPoint? {
        let lat = latitude * .pi / 180
        let lon = (longitude - centerLongitude) * .pi / 180
        let centerLat = centerLatitude * .pi / 180
        let cosc = sin(centerLat) * sin(lat) + cos(centerLat) * cos(lat) * cos(lon)
        guard cosc >= 0 else { return nil }
        let x = radius * CGFloat(cos(lat) * sin(lon))
        let y = -radius * CGFloat(cos(centerLat) * sin(lat) - sin(centerLat) * cos(lat) * cos(lon))
        return CGPoint(x: center.x + x, y: center.y + y)
    }

    private static let texture: NSImage? = {
        guard let url = LogbookResources.earthBlueMarbleURL else { return nil }
        return NSImage(contentsOf: url)
    }()
}
