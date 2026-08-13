import SwiftUI
import OpenPilotLogbookCore

struct AnalysisView: View {
    @ObservedObject var store: LogbookStore
    @State private var selectedTab: AnalysisTab = .types
    @State private var range: AnalysisRange = .all
    @State private var groupName = ""
    @State private var customStart = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    @State private var customEnd = Date()

    private var filteredSummary: LogbookSummary { LogbookSummary(flights: store.flights) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            filterBar
            FlightFilterBar(query: store.flightQuery, resultCount: store.flights.count, reset: store.resetFlightFilters)
            FlightQueryEditor(query: store.flightQuery, aircraftIDs: store.availableAircraftIDs, aircraftTypes: store.availableAircraftTypes, pilotFunctions: store.availablePilotFunctions, operations: store.availableOperations, entryKinds: store.availableEntryKinds, apply: { store.applyFlightQuery($0) })
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                MetricTile(title: "Filtered flights", value: store.flights.count.formatted(), systemImage: "airplane", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Hours", value: LogbookFormatters.hours(filteredSummary.totalMinutes), systemImage: "clock", tint: OpenPilotTheme.green)
                MetricTile(title: "Nautical miles", value: String(format: "%.0f", filteredSummary.distanceNM), systemImage: "point.topleft.down.curvedto.point.bottomright.up", tint: OpenPilotTheme.blue)
                MetricTile(title: "Places", value: filteredPlaces.count.formatted(), systemImage: "mappin.and.ellipse", tint: OpenPilotTheme.amber)
            }

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    analysisPanel.frame(minWidth: 660, maxWidth: .infinity, alignment: .top)
                    settingsPanel.frame(width: 320, alignment: .top)
                }
                VStack(alignment: .leading, spacing: 14) {
                    analysisPanel
                    settingsPanel
                }
            }
            Spacer(minLength: 0)
        }
        .padding(24)
        .navigationTitle("Analysis")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analysis.screen")
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Analysis").pageTitleStyle()
                Text("Every total uses the same visible-flight filter and can drill down to its entries.")
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            Menu("Saved Groups") {
                if store.savedAnalysisGroups.isEmpty { Text("No saved groups") }
                ForEach(store.savedAnalysisGroups) { group in
                    Button(group.name) { store.applyAnalysisGroup(group) }
                }
            }
            .accessibilityIdentifier("analysis.savedGroups")
        }
    }

    private var filterBar: some View {
        Panel {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { rangeControls; stateControls; Spacer(); saveGroupControls }
                VStack(alignment: .leading, spacing: 10) { rangeControls; stateControls; saveGroupControls }
            }
        }
    }

    @ViewBuilder private var rangeControls: some View {
        Picker("Date range", selection: $range) {
            ForEach(AnalysisRange.allCases) { Text($0.title).tag($0) }
        }
        .frame(width: 150)
        .onChange(of: range) { _, _ in applyRange() }
        if range == .custom {
            DatePicker("From", selection: $customStart, displayedComponents: .date).labelsHidden()
            DatePicker("To", selection: $customEnd, displayedComponents: .date).labelsHidden()
            Button("Apply") { applyRange() }
        }
    }

    private var stateControls: some View {
        Menu {
            Toggle("Drafts", isOn: stateBinding(.draft))
            Toggle("Finalised", isOn: stateBinding(.finalised))
            Toggle("Superseded", isOn: stateBinding(.superseded))
            Toggle("Trash", isOn: stateBinding(.trashed))
        } label: {
            Label("Record states", systemImage: "line.3.horizontal.decrease.circle")
        }
        .accessibilityIdentifier("analysis.recordStates")
    }

    private var saveGroupControls: some View {
        HStack {
            TextField("Group name", text: $groupName).textFieldStyle(.roundedBorder).frame(width: 150)
            Button("Save Group") {
                store.saveAnalysisGroup(named: groupName)
                groupName = ""
            }
            .disabled(groupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var analysisPanel: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Analysis", selection: $selectedTab) {
                    ForEach(AnalysisTab.allCases) { tab in Label(tab.title, systemImage: tab.systemImage).tag(tab) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)
                switch selectedTab {
                case .types: typeTable
                case .people: peopleTable
                case .places: placesTable
                }
            }
        }
    }

    private var settingsPanel: some View {
        Panel("Configurable Currency Indicator", systemImage: "slider.horizontal.3") {
            Text("A personal indicator only—not a certified or regulatory determination.")
                .font(.caption).foregroundStyle(OpenPilotTheme.muted)
            Stepper("Landing target: \(store.currencyLandingLimit)", value: $store.currencyLandingLimit, in: 1...20)
            Stepper("Lookback: \(store.currencyLookbackDays) days", value: $store.currencyLookbackDays, in: 1...365)
            let cutoff = Calendar.current.date(byAdding: .day, value: -store.currencyLookbackDays, to: Date()) ?? .distantPast
            let landings = store.flights.filter { $0.date >= cutoff }.reduce(0) { $0 + $1.totalLandings }
            Label(
                landings >= store.currencyLandingLimit ? "Configured threshold met" : "Below configured threshold",
                systemImage: landings >= store.currencyLandingLimit ? "checkmark.circle" : "exclamationmark.circle"
            )
            .foregroundStyle(landings >= store.currencyLandingLimit ? OpenPilotTheme.green : OpenPilotTheme.amber)
            Text("\(landings) landings in the selected \(store.currencyLookbackDays)-day window")
                .font(.caption).foregroundStyle(OpenPilotTheme.muted)
            if !store.savedAnalysisGroups.isEmpty {
                Divider()
                Text("Saved locally").font(.caption.weight(.semibold))
                List {
                    ForEach(store.savedAnalysisGroups) { group in Button(group.name) { store.applyAnalysisGroup(group) }.buttonStyle(.plain) }
                    .onDelete(perform: store.deleteAnalysisGroups)
                }.frame(minHeight: 100)
            }
        }
    }

    private var typeTable: some View {
        VStack(spacing: 8) {
            AnalysisHeader(columns: [("Type", nil), ("Flights", 90), ("Hours", 110), ("NM", 110)])
            ScrollView { LazyVStack(spacing: 6) {
                ForEach(filteredTypes) { item in
                    Button { drillToType(item.aircraftType) } label: { AnalysisRow {
                        Text(item.aircraftType.isEmpty ? "Unknown" : item.aircraftType).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.flightCount)").monospacedDigit().frame(width: 90, alignment: .trailing)
                        Text(LogbookFormatters.hours(item.totalMinutes)).monospacedDigit().frame(width: 110, alignment: .trailing)
                        Text(String(format: "%.0f", item.distanceNM)).monospacedDigit().frame(width: 110, alignment: .trailing)
                    }}.buttonStyle(.plain).accessibilityHint("Open matching flights")
                }
            }}
        }
    }

    private var peopleTable: some View {
        VStack(spacing: 8) {
            AnalysisHeader(columns: [("Person", nil), ("Flights", 110), ("Hours", 130)])
            ScrollView { LazyVStack(spacing: 6) {
                ForEach(filteredPeople) { item in
                    Button { drillToText(item.name, description: item.name) } label: { AnalysisRow {
                        Text(item.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.flightCount)").monospacedDigit().frame(width: 110, alignment: .trailing)
                        Text(LogbookFormatters.hours(item.totalMinutes)).monospacedDigit().frame(width: 130, alignment: .trailing)
                    }}.buttonStyle(.plain)
                }
            }}
        }
    }

    private var placesTable: some View {
        VStack(spacing: 8) {
            AnalysisHeader(columns: [("Place", 90), ("Name", nil), ("Departures", 110), ("Arrivals", 100)])
            ScrollView { LazyVStack(spacing: 6) {
                ForEach(filteredPlaces) { item in
                    Button { drillToText(item.identifier, description: item.identifier) } label: { AnalysisRow {
                        Text(item.identifier).frame(width: 90, alignment: .leading)
                        Text(item.name.isEmpty ? "Metadata unavailable" : item.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(item.departures)").monospacedDigit().frame(width: 110, alignment: .trailing)
                        Text("\(item.arrivals)").monospacedDigit().frame(width: 100, alignment: .trailing)
                    }}.buttonStyle(.plain)
                }
            }}
        }
    }

    private var filteredTypes: [TypeSummary] {
        Dictionary(grouping: store.flights, by: \.aircraftType).map { key, flights in
            TypeSummary(aircraftType: key, flightCount: flights.count, totalMinutes: flights.reduce(0) { $0 + $1.flyingMinutes }, copilotDayMinutes: flights.reduce(0) { $0 + $1.copilotDayMinutes }, copilotNightMinutes: flights.reduce(0) { $0 + $1.copilotNightMinutes }, distanceNM: flights.reduce(0) { $0 + $1.distanceNM })
        }.sorted { $0.totalMinutes > $1.totalMinutes }
    }

    private var filteredPeople: [PersonSummary] {
        var values: [String: (Int, Int)] = [:]
        for flight in store.flights { for name in FlightEntry.splitCrewNames(flight.crewNames) { let value = values[name] ?? (0, 0); values[name] = (value.0 + 1, value.1 + flight.flyingMinutes) } }
        return values.map { PersonSummary(name: $0.key, flightCount: $0.value.0, totalMinutes: $0.value.1) }.sorted { $0.flightCount > $1.flightCount }
    }

    private var filteredPlaces: [PlaceVisitSummary] {
        let names = Dictionary(uniqueKeysWithValues: store.places.map { ($0.identifier, $0.name) })
        var values: [String: (Int, Int)] = [:]
        for flight in store.flights {
            if !flight.departure.isEmpty { let value = values[flight.departure] ?? (0, 0); values[flight.departure] = (value.0 + 1, value.1) }
            if !flight.arrival.isEmpty { let value = values[flight.arrival] ?? (0, 0); values[flight.arrival] = (value.0, value.1 + 1) }
        }
        return values.map { PlaceVisitSummary(identifier: $0.key, name: names[$0.key] ?? "", departures: $0.value.0, arrivals: $0.value.1) }.sorted { ($0.departures + $0.arrivals) > ($1.departures + $1.arrivals) }
    }

    private func applyRange() {
        var query = store.flightQuery
        switch range {
        case .all: query.startDate = nil; query.endDate = nil
        case .ninetyDays: query.startDate = Calendar.current.date(byAdding: .day, value: -90, to: Date()); query.endDate = Date()
        case .twelveMonths: query.startDate = Calendar.current.date(byAdding: .year, value: -1, to: Date()); query.endDate = Date()
        case .custom: query.startDate = customStart; query.endDate = Calendar.current.date(byAdding: .day, value: 1, to: customEnd)
        }
        store.applyFlightQuery(query)
    }

    private func stateBinding(_ state: FlightRecordState) -> Binding<Bool> {
        Binding(get: { store.flightQuery.recordStates.contains(state) }, set: { enabled in
            var query = store.flightQuery
            if enabled { query.recordStates.insert(state) } else { query.recordStates.remove(state) }
            store.applyFlightQuery(query)
        })
    }

    private func drillToType(_ type: String) {
        var query = store.flightQuery
        query.aircraftTypes = type.isEmpty ? [] : [type]
        store.drillDown(query, description: type.isEmpty ? "unknown aircraft type" : type)
    }

    private func drillToText(_ text: String, description: String) {
        var query = store.flightQuery; query.text = text
        store.drillDown(query, description: description)
    }
}

private enum AnalysisRange: String, CaseIterable, Identifiable {
    case all, ninetyDays, twelveMonths, custom
    var id: String { rawValue }
    var title: String { switch self { case .all: "All time"; case .ninetyDays: "90 days"; case .twelveMonths: "12 months"; case .custom: "Custom" } }
}

private enum AnalysisTab: String, CaseIterable, Identifiable {
    case types, people, places
    var id: String { rawValue }
    var title: String { switch self { case .types: "By Type"; case .people: "People"; case .places: "Places" } }
    var systemImage: String { switch self { case .types: "airplane.circle"; case .people: "person.2"; case .places: "mappin.and.ellipse" } }
}

private struct AnalysisHeader: View {
    var columns: [(String, CGFloat?)]
    var body: some View { HStack(spacing: 14) { ForEach(Array(columns.enumerated()), id: \.offset) { _, column in Text(column.0).frame(width: column.1, alignment: column.1 == nil ? .leading : .trailing).frame(maxWidth: column.1 == nil ? .infinity : nil, alignment: .leading) } }.font(.caption.weight(.medium)).foregroundStyle(OpenPilotTheme.muted).padding(.horizontal, 14).padding(.vertical, 4) }
}

private struct AnalysisRow<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { HStack(spacing: 14) { content }.font(.callout.weight(.medium)).padding(.horizontal, 14).padding(.vertical, 9).background(OpenPilotTheme.panelRaised, in: RoundedRectangle(cornerRadius: 6)).overlay { RoundedRectangle(cornerRadius: 6).stroke(OpenPilotTheme.border, lineWidth: 1) } }
}
