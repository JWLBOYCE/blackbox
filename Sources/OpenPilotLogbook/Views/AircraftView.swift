import SwiftUI
import OpenPilotLogbookCore

struct AircraftView: View {
    @ObservedObject var store: LogbookStore
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\AircraftSummary.totalMinutes, order: .reverse)]

    private var sortedAircraft: [AircraftSummary] {
        store.aircraft.sorted(using: sortOrder)
    }

    private var selectedAircraft: AircraftSummary? {
        store.aircraft.first { $0.id == selection }
    }

    private var matchingFlights: [FlightEntry] {
        guard let aircraft = selectedAircraft else { return [] }
        return store.flights
            .filter { $0.aircraftID == aircraft.aircraftID && $0.aircraftType == aircraft.aircraftType }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                header
                Table(sortedAircraft, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Aircraft", value: \.aircraftID) { item in
                        Text(item.aircraftID.isEmpty ? "Unknown" : item.aircraftID)
                    }
                    TableColumn("Type", value: \.aircraftType) { item in
                        Text(item.aircraftType.isEmpty ? "Unknown" : item.aircraftType)
                    }
                    TableColumn("Flights", value: \.flightCount) { item in
                        Text("\(item.flightCount)").monospacedDigit()
                    }
                    TableColumn("Hours", value: \.totalMinutes) { item in
                        Text(LogbookFormatters.hours(item.totalMinutes)).monospacedDigit()
                    }
                    TableColumn("Landings", value: \.landings) { item in
                        Text("\(item.landings)").monospacedDigit()
                    }
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            .padding(.leading, 20)
            .padding(.vertical, 20)
            .frame(minWidth: 470, idealWidth: 610)

            AircraftInspector(aircraft: selectedAircraft, flights: matchingFlights, openFlight: store.showFlight)
                .frame(minWidth: 420, idealWidth: 500)
        }
        .navigationTitle("Aircraft")
        .onAppear {
            if selection == nil { selection = sortedAircraft.first?.id }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text("Aircraft")
                    .font(.system(size: 34, weight: .semibold))
                Text("Fleet totals by registration and type.")
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            Text("\(store.aircraft.count.formatted()) aircraft")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OpenPilotTheme.muted)
        }
    }
}

private struct AircraftInspector: View {
    var aircraft: AircraftSummary?
    var flights: [FlightEntry]
    var openFlight: (FlightEntry) -> Void

    var body: some View {
        if let aircraft {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "airplane.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(OpenPilotTheme.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(aircraft.aircraftID.isEmpty ? "Unknown aircraft" : aircraft.aircraftID)
                                .font(.title2.weight(.semibold))
                            Text(aircraft.aircraftType)
                                .foregroundStyle(OpenPilotTheme.muted)
                        }
                    }
                    HStack(spacing: 10) {
                        metric("Flights", aircraft.flightCount)
                        metric("Hours", LogbookFormatters.hours(aircraft.totalMinutes))
                        metric("Landings", "\(aircraft.landings)")
                    }
                    Panel("Flight history", systemImage: "clock.arrow.circlepath") {
                        LazyVStack(spacing: 0) {
                            ForEach(flights) { flight in
                                Button { openFlight(flight) } label: {
                                    HStack(spacing: 10) {
                                        Text(LogbookFormatters.dateFormatter.string(from: flight.date))
                                            .frame(width: 94, alignment: .leading)
                                        Text(flight.routeDisplay.replacingOccurrences(of: " -> ", with: "-"))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(flight.flightNumber)
                                            .frame(width: 70, alignment: .leading)
                                        Text(LogbookFormatters.hours(flight.flyingMinutes))
                                            .monospacedDigit()
                                    }
                                    .padding(.vertical, 7)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider().opacity(0.18)
                            }
                        }
                    }
                }
                .padding(20)
            }
        } else {
            EmptyStateBlock(title: "Select an aircraft", message: "Its routes and flight history will appear here.", systemImage: "airplane.circle")
        }
    }

    private func metric(_ title: String, _ value: some StringProtocol) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(OpenPilotTheme.muted)
            Text(value).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        metric(title, String(value))
    }
}
