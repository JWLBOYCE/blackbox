import SwiftUI
import AppKit
import OpenPilotLogbookCore

struct FlightsView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        HSplitView {
            Panel {
                VStack(spacing: 12) {
                    HStack {
                        Text("Flights")
                            .font(.title2.weight(.semibold))
                        Spacer()
                        Text("\(store.flights.count.formatted()) entries")
                            .font(.caption)
                            .foregroundStyle(OpenPilotTheme.muted)
                    }
                    flightSearch
                    if !store.highlightedFlights.isEmpty {
                        HighlightedFlightsTotals(flights: store.highlightedFlights) {
                            store.showAllRoutes()
                        }
                    }
                    flightList
                }
            }
            .padding(.leading, 22)
            .padding(.vertical, 22)
            .frame(minWidth: 390, idealWidth: 500)

            FlightEditorView(store: store)
                .padding(.trailing, 22)
                .padding(.vertical, 22)
                .frame(minWidth: 520)
        }
        .navigationTitle("Flights")
    }

    private var flightSearch: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(OpenPilotTheme.muted)
            TextField("Search flights, aircraft, route, remarks", text: $store.searchText)
                .textFieldStyle(.plain)
                .onSubmit { store.applySearch() }
                .onChange(of: store.searchText) { _, newValue in
                    if newValue.isEmpty { store.applySearch() }
                }
            if !store.searchText.isEmpty {
                Button {
                    store.searchText = ""
                    store.applySearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(OpenPilotTheme.muted)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.070), in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
    }

    private var flightList: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 500
            VStack(spacing: 8) {
                FlightListHeader(compact: compact)

                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.flights) { flight in
                            Button {
                                if NSEvent.modifierFlags.contains(.command) {
                                    store.toggleRouteSelection(for: flight)
                                } else {
                                    store.selectFlight(id: flight.id)
                                }
                            } label: {
                                FlightRow(
                                    flight: flight,
                                    isSelected: flight.id.map { store.selectedRouteFlightIDs.contains($0) } ?? false,
                                    compact: compact
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }
}

private struct HighlightedFlightsTotals: View {
    var flights: [FlightEntry]
    var onClear: () -> Void

    private var totals: FlightSelectionTotals {
        FlightSelectionTotals(flights: flights)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("\(flights.count.formatted()) highlighted", systemImage: "checkmark.circle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OpenPilotTheme.cyan)
                Spacer()
                Button("Clear", action: onClear)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                TotalsChip("Total", LogbookFormatters.hours(totals.totalMinutes))
                TotalsChip("PIC", LogbookFormatters.hours(totals.picMinutes))
                TotalsChip("PICUS", LogbookFormatters.hours(totals.picusMinutes))
                TotalsChip("Co-pilot", LogbookFormatters.hours(totals.copilotMinutes))
                TotalsChip("Night", LogbookFormatters.hours(totals.nightMinutes))
                TotalsChip("IFR", LogbookFormatters.hours(totals.instrumentMinutes))
                TotalsChip("XC", LogbookFormatters.hours(totals.crossCountryMinutes))
                TotalsChip("FSTD", LogbookFormatters.hours(totals.fstdMinutes))
                TotalsChip("T/O", "\(totals.totalTakeoffs)")
                TotalsChip("Ldg", "\(totals.totalLandings)")
                TotalsChip("PF", "\(totals.pilotFlyingCount)")
                TotalsChip("NM", String(format: "%.0f", totals.distanceNM))
            }
        }
        .padding(12)
        .background(OpenPilotTheme.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.blue.opacity(0.36), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlighted flight totals")
    }
}

private struct TotalsChip: View {
    var title: String
    var value: String

    init(_ title: String, _ value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(OpenPilotTheme.muted)
                .lineLimit(1)
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.050), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct FlightSelectionTotals {
    var totalMinutes = 0
    var picMinutes = 0
    var picusMinutes = 0
    var copilotMinutes = 0
    var nightMinutes = 0
    var instrumentMinutes = 0
    var crossCountryMinutes = 0
    var fstdMinutes = 0
    var totalTakeoffs = 0
    var totalLandings = 0
    var pilotFlyingCount = 0
    var distanceNM: Double = 0

    init(flights: [FlightEntry]) {
        totalMinutes = flights.reduce(0) { $0 + $1.totalMinutes }
        picMinutes = flights.reduce(0) { $0 + $1.picMinutes }
        picusMinutes = flights.reduce(0) { $0 + $1.picusMinutes }
        copilotMinutes = flights.reduce(0) { $0 + $1.copilotMinutes }
        nightMinutes = flights.reduce(0) { $0 + $1.nightMinutes }
        instrumentMinutes = flights.reduce(0) { $0 + $1.instrumentMinutes }
        crossCountryMinutes = flights.reduce(0) { $0 + $1.crossCountryMinutes }
        fstdMinutes = flights.reduce(0) { $0 + $1.fstdMinutes }
        totalTakeoffs = flights.reduce(0) { $0 + $1.totalTakeoffs }
        totalLandings = flights.reduce(0) { $0 + $1.totalLandings }
        pilotFlyingCount = flights.filter(\.pilotFlying).count
        distanceNM = flights.reduce(0) { $0 + $1.distanceNM }
    }
}

private struct FlightListHeader: View {
    var compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text("Date").frame(width: compact ? 88 : 96, alignment: .leading)
            if !compact {
                Text("Route").frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Aircraft").frame(maxWidth: compact ? .infinity : 86, alignment: .leading)
            Text("Duration").frame(width: compact ? 70 : 82, alignment: .trailing)
            Text("T/L").frame(width: compact ? 38 : 54, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(OpenPilotTheme.muted)
        .padding(.horizontal, 12)
    }
}

struct FlightRow: View {
    var flight: FlightEntry
    var isSelected = false
    var compact = false

    var body: some View {
        HStack(spacing: 10) {
            Text(LogbookFormatters.dateFormatter.string(from: flight.date))
                .frame(width: compact ? 88 : 96, alignment: .leading)
                .lineLimit(1)
            if !compact {
                Text(flight.routeDisplay.isEmpty ? "No route" : flight.routeDisplay.replacingOccurrences(of: " -> ", with: "->"))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(1)
            }
            Text(flight.aircraftID.isEmpty ? "Unknown" : flight.aircraftID)
                .frame(maxWidth: compact ? .infinity : 86, alignment: .leading)
                .lineLimit(1)
            Text(LogbookFormatters.hours(flight.totalMinutes))
                .font(.callout.monospacedDigit())
                .frame(width: compact ? 70 : 82, alignment: .trailing)
            Text("\(flight.totalTakeoffs)/\(flight.totalLandings)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(flight.pilotFlying ? OpenPilotTheme.green : OpenPilotTheme.muted)
                .frame(width: compact ? 38 : 54, alignment: .trailing)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(isSelected ? OpenPilotTheme.blue.opacity(0.28) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? OpenPilotTheme.blue.opacity(0.58) : Color.white.opacity(0.055), lineWidth: 1)
        }
    }
}

struct FlightEditorView: View {
    @ObservedObject var store: LogbookStore

    var body: some View {
        Panel {
            if let binding = Binding($store.draftFlight) {
                VStack(spacing: 0) {
                    ScrollView {
                                VStack(alignment: .leading, spacing: 14) {
                                    editorHeader(for: binding.wrappedValue)
                                    FlightSection("Flight", systemImage: "airplane") {
                                        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                                            GridRow {
                                                Picker("Entry", selection: binding.entryKind) {
                                                    Label("Flight", systemImage: "airplane").tag("Flight")
                                                    Label("Simulator", systemImage: "rectangle.inset.filled").tag("Simulator")
                                                }
                                                .pickerStyle(.segmented)
                                                .onChange(of: binding.wrappedValue.entryKind) { _, newValue in
                                                    store.setDraftEntryKind(newValue)
                                                }
                                                EmptyView()
                                            }
                                            GridRow {
                                                DatePicker("Date", selection: binding.date, displayedComponents: [.date])
                                                DatePicker("Time (Zulu)", selection: binding.date, displayedComponents: [.hourAndMinute])
                                    }
                                    GridRow {
                                        Picker("Operation", selection: binding.operation) {
                                            Text("Single pilot").tag("SP")
                                            Text("Multi-pilot").tag("MP")
                                        }
                                        EmptyView()
                                    }
                                    GridRow {
                                        SuggestionTextField("Departure", text: binding.departure, suggestions: store.suggestions.places)
                                        SuggestionTextField("Arrival", text: binding.arrival, suggestions: store.suggestions.places)
                                    }
                                    GridRow {
                                        TextField("Route", text: binding.route)
                                        TextField("Flight number", text: binding.flightNumber)
                                    }
                                }
                            }
                            FlightSection("Aircraft", systemImage: "airplane.circle") {
                                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 12) {
                                    GridRow {
                                        SuggestionTextField("Aircraft ID / registration", text: binding.aircraftID, suggestions: store.suggestions.aircraftIDs)
                                        SuggestionTextField("Aircraft type", text: binding.aircraftType, suggestions: store.suggestions.aircraftTypes)
                                    }
                                    GridRow {
                                                Picker("Function", selection: binding.pilotFunction) {
                                                    Text("Unspecified").tag("")
                                                    Text("PIC").tag("PIC")
                                                    Text("PICUS").tag("PICUS")
                                                    Text("Co-pilot").tag("Co-pilot")
                                                    Text("Dual").tag("Dual")
                                                    Text("Instructor").tag("Instructor")
                                                    Text("FSTD").tag("FSTD")
                                                }
                                                CrewNamesField(text: binding.crewNames, roles: binding.crewRoles, suggestions: store.suggestions.people)
                                            }
                                        }
                                    }
                                    FlightSection("Times and Landings", systemImage: "clock") {
                                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
                                            MinutesStepper("Total", minutes: binding.totalMinutes)
                                            MinutesStepper("PIC", minutes: binding.picMinutes)
                                            MinutesStepper("PIC Day", minutes: binding.picDayMinutes)
                                            MinutesStepper("PIC Night", minutes: binding.picNightMinutes)
                                            MinutesStepper("PICUS", minutes: binding.picusMinutes)
                                            MinutesStepper("Co-pilot", minutes: binding.copilotMinutes)
                                            MinutesStepper("Co-pilot Day", minutes: binding.copilotDayMinutes)
                                            MinutesStepper("Co-pilot Night", minutes: binding.copilotNightMinutes)
                                            MinutesStepper("Night", minutes: binding.nightMinutes)
                                            MinutesStepper("Dual", minutes: binding.dualMinutes)
                                            MinutesStepper("Instructor", minutes: binding.instructorMinutes)
                                            MinutesStepper("IFR / Instrument", minutes: binding.instrumentMinutes)
                                            MinutesStepper("Cross-country", minutes: binding.crossCountryMinutes)
                                            MinutesStepper("FSTD", minutes: binding.fstdMinutes)
                                            Toggle("Pilot Flying", isOn: binding.pilotFlying)
                                                .toggleStyle(.checkbox)
                                                .fieldShell()
                                            NumericStepper(title: "Takeoffs", value: binding.totalTakeoffs, range: 0...999)
                                            NumericStepper(title: "Day Takeoffs", value: binding.dayTakeoffs, range: 0...999)
                                            NumericStepper(title: "Night Takeoffs", value: binding.nightTakeoffs, range: 0...999)
                                            NumericStepper(title: "Landings", value: binding.totalLandings, range: 0...999)
                                            NumericStepper(title: "Day Landings", value: binding.dayLandings, range: 0...999)
                                            NumericStepper(title: "Night Landings", value: binding.nightLandings, range: 0...999)
                                            NumericStepper(title: "Passengers", value: binding.passengerCount, range: 0...999)
                                            HStack {
                                                Text("Nautical miles")
                                                Spacer()
                                                TextField("NM", value: binding.distanceNM, format: .number.precision(.fractionLength(0...1)))
                                                    .multilineTextAlignment(.trailing)
                                            .frame(width: 86)
                                    }
                                    .fieldShell()
                                }
                            }
                            FlightSection("Notes", systemImage: "text.bubble") {
                                TextEditor(text: binding.remarks)
                                    .font(.callout)
                                    .scrollContentBackground(.hidden)
                                    .frame(minHeight: 90)
                                    .padding(8)
                                            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(OpenPilotTheme.border, lineWidth: 1)
                                            }
                                        Toggle("Lock entry", isOn: binding.locked)
                                    }
                                }
                                .padding(.bottom, 14)
                            }
                            actionBar
                        }
                        .onChange(of: binding.wrappedValue.totalMinutes) { _, _ in store.normalizeDraft() }
                        .onChange(of: binding.wrappedValue.nightMinutes) { _, _ in store.normalizeDraft() }
                        .onChange(of: binding.wrappedValue.pilotFlying) { _, _ in store.normalizeDraft() }
                        .onChange(of: binding.wrappedValue.pilotFunction) { _, _ in store.normalizeDraft() }
                        .onChange(of: binding.wrappedValue.crewNames) { _, _ in store.normalizeDraft() }
                    } else {
                EmptyStateBlock(title: "No Flight Selected", message: "Select an entry or create a new flight.", systemImage: "airplane")
            }
        }
    }

    private func editorHeader(for flight: FlightEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "airplane")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(OpenPilotTheme.cyan)
            VStack(alignment: .leading, spacing: 2) {
                Text(flight.routeDisplay.isEmpty ? "Flight Entry" : flight.routeDisplay)
                    .font(.title2.weight(.semibold))
                Text([flight.aircraftID, flight.aircraftType, flight.operation].filter { !$0.isEmpty }.joined(separator: " / "))
                    .font(.callout)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            StatusGlyph(ok: flight.totalMinutes > 0 && !flight.aircraftID.isEmpty)
        }
        .padding(.bottom, 2)
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button(action: store.saveDraft) {
                Label("Save", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity)
            }
            .keyboardShortcut("s", modifiers: [.command])
            .buttonStyle(.borderedProminent)

            Button(action: store.duplicateCurrentFlight) {
                Label("Duplicate", systemImage: "square.on.square")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(role: .destructive, action: store.deleteSelectedFlight) {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .disabled(store.selectedFlightID == nil)
            .buttonStyle(.bordered)
        }
        .padding(.top, 14)
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }
}

private struct FlightSection<Content: View>: View {
    var title: String
    var systemImage: String
    var content: Content

    init(_ title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)
            content
        }
        .padding(14)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: OpenPilotTheme.corner))
        .overlay {
            RoundedRectangle(cornerRadius: OpenPilotTheme.corner)
                .stroke(OpenPilotTheme.border, lineWidth: 1)
        }
    }
}

struct MinutesStepper: View {
    var title: String
    @Binding var minutes: Int
    @State private var text = ""
    @FocusState private var isFocused: Bool

    init(_ title: String, minutes: Binding<Int>) {
        self.title = title
        self._minutes = minutes
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("HH:MM", text: $text)
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 74)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(commitText)
                .onAppear { text = LogbookFormatters.hours(minutes) }
                .onChange(of: minutes) { _, newValue in
                    let formatted = LogbookFormatters.hours(newValue)
                    if text != formatted { text = formatted }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }
            Stepper("", value: $minutes, in: 0...20000, step: 1)
                .labelsHidden()
                .accessibilityLabel("\(title) one minute increment")
                .frame(width: 34)
        }
        .fieldShell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue(LogbookFormatters.hours(minutes))
    }

    private func commitText() {
        guard let parsed = Self.minutes(from: text), parsed != minutes else { return }
        minutes = min(max(parsed, 0), 20000)
    }

    private static func minutes(from text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2, let hours = Int(parts[0]), let mins = Int(parts[1]), mins >= 0, mins < 60 else { return nil }
            return (hours * 60) + mins
        }
        if trimmed.count <= 2, let mins = Int(trimmed) {
            return mins
        }
        guard let compact = Int(trimmed) else { return nil }
        return (compact / 100 * 60) + (compact % 100)
    }
}

private struct NumericStepper: View {
    var title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("0", text: $text)
                .font(.callout.monospacedDigit())
                .multilineTextAlignment(.trailing)
                .frame(width: 54)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(commitText)
                .onAppear { text = "\(value)" }
                .onChange(of: value) { _, newValue in
                    let formatted = "\(newValue)"
                    if text != formatted { text = formatted }
                }
                .onChange(of: isFocused) { _, focused in
                    if !focused { commitText() }
                }
            Stepper("", value: $value, in: range)
                .labelsHidden()
                .accessibilityLabel("\(title) increment")
                .frame(width: 34)
        }
        .fieldShell()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(value)")
    }

    private func commitText() {
        guard let parsed = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        value = min(max(parsed, range.lowerBound), range.upperBound)
    }
}

struct SuggestionTextField: View {
    var title: String
    @Binding var text: String
    var suggestions: [String]

    init(_ title: String, text: Binding<String>, suggestions: [String]) {
        self.title = title
        self._text = text
        self.suggestions = suggestions
    }

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text)
            Menu {
                let filtered = suggestions
                    .filter { text.isEmpty || $0.localizedCaseInsensitiveContains(text) }
                    .prefix(20)
                if filtered.isEmpty {
                    Text("No suggestions")
                } else {
                    ForEach(Array(filtered), id: \.self) { suggestion in
                        Button(suggestion) { text = suggestion }
                    }
                }
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("\(title) suggestions")
        }
    }
}

private struct CrewNamesField: View {
    @Binding var text: String
    @Binding var roles: String
    var suggestions: [String]

    private var names: [String] {
        FlightEntry.splitCrewNames(text)
    }

    private var roleMap: [String: String] {
        FlightEntry.parseCrewRoles(roles)
    }

    private var captainName: String {
        names.first { roleMap[$0] == "Captain" || roleMap[$0] == "PIC" } ?? ""
    }

    private var firstOfficerName: String {
        names.first { roleMap[$0] == "First Officer" || roleMap[$0] == "Co-pilot" } ?? ""
    }

    private var otherCrewText: String {
        names
            .filter { $0 != captainName && $0 != firstOfficerName }
            .joined(separator: " | ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledCrewField("Captain", text: binding(for: .captain), suggestions: suggestions)
            LabeledCrewField("First Officer", text: binding(for: .firstOfficer), suggestions: suggestions)
            LabeledCrewField("Instructor / Other crew", text: binding(for: .other), suggestions: suggestions)
            if !names.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(names, id: \.self) { name in
                        CrewRolePill(
                            name: name,
                            role: roleMap[name] ?? "Crew",
                            onChange: { role in setRole(role, for: name) }
                        )
                    }
                }
            }
        }
    }

    private enum CrewSlot {
        case captain
        case firstOfficer
        case other
    }

    private func binding(for slot: CrewSlot) -> Binding<String> {
        Binding {
            switch slot {
            case .captain: return captainName
            case .firstOfficer: return firstOfficerName
            case .other: return otherCrewText
            }
        } set: { value in
            let normalized = Self.normalizedCrewText(value)
            switch slot {
            case .captain:
                updateCrew(captain: normalized, firstOfficer: firstOfficerName, other: otherCrewText)
            case .firstOfficer:
                updateCrew(captain: captainName, firstOfficer: normalized, other: otherCrewText)
            case .other:
                updateCrew(captain: captainName, firstOfficer: firstOfficerName, other: normalized)
            }
        }
    }

    private func updateCrew(captain: String, firstOfficer: String, other: String) {
        let captainNames = FlightEntry.splitCrewNames(captain)
        let firstOfficerNames = FlightEntry.splitCrewNames(firstOfficer)
        let otherNames = FlightEntry.splitCrewNames(other)
        let combined = (captainNames + firstOfficerNames + otherNames).reduce(into: [String]()) { result, name in
            if !result.contains(name) { result.append(name) }
        }
        var updatedRoles = roleMap
        for name in captainNames { updatedRoles[name] = "Captain" }
        for name in firstOfficerNames { updatedRoles[name] = "First Officer" }
        for name in otherNames where updatedRoles[name] == nil || updatedRoles[name] == "Crew" {
            updatedRoles[name] = "Other crew"
        }
        text = combined.joined(separator: " | ")
        roles = FlightEntry.crewRolesText(from: updatedRoles, names: combined)
    }

    private func setRole(_ role: String, for name: String) {
        var updated = roleMap
        updated[name] = role
        roles = FlightEntry.crewRolesText(from: updated, names: names)
    }

    private static func normalizedCrewText(_ value: String) -> String {
        let parts = value
            .components(separatedBy: ", ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 2, parts.count.isMultiple(of: 2) else { return value }
        return stride(from: 0, to: parts.count, by: 2)
            .map { "\(parts[$0 + 1]) \(parts[$0])" }
            .joined(separator: " | ")
    }
}

private struct LabeledCrewField: View {
    var title: String
    @Binding var text: String
    var suggestions: [String]

    init(_ title: String, text: Binding<String>, suggestions: [String]) {
        self.title = title
        self._text = text
        self.suggestions = suggestions
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(OpenPilotTheme.muted)
            SuggestionTextField(title, text: $text, suggestions: suggestions)
        }
    }
}

private struct CrewRolePill: View {
    var name: String
    var role: String
    var onChange: (String) -> Void

    private let roles = ["Captain", "First Officer", "Instructor", "Examiner", "Relief", "Cabin crew", "Observer", "Other crew"]

    var body: some View {
        Menu {
            ForEach(roles, id: \.self) { option in
                Button(option) { onChange(option) }
            }
        } label: {
            HStack(spacing: 6) {
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text(role)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(OpenPilotTheme.cyan)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OpenPilotTheme.blue.opacity(0.18), in: Capsule())
            .foregroundStyle(.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(role)")
        .accessibilityHint("Choose crew role")
    }
}

private struct FlowLayout<Content: View>: View {
    var spacing: CGFloat = 8
    var content: Content

    init(spacing: CGFloat = 8, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: spacing) { content }
            VStack(alignment: .leading, spacing: spacing) { content }
        }
    }
}

private extension View {
    func fieldShell() -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(OpenPilotTheme.border, lineWidth: 1)
            }
    }
}
