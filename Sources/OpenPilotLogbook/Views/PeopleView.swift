import SwiftUI
import OpenPilotLogbookCore

struct PeopleView: View {
    @ObservedObject var store: LogbookStore
    @State private var selection: String?
    @State private var sortOrder = [KeyPathComparator(\PersonSummary.flightCount, order: .reverse)]

    private var sortedPeople: [PersonSummary] {
        store.people.sorted(using: sortOrder)
    }

    private var selectedPerson: PersonSummary? {
        store.people.first { $0.id == selection }
    }

    private var matchingFlights: [FlightEntry] {
        guard let name = selectedPerson?.name else { return [] }
        return store.flights
            .filter { $0.crewNameList.contains(name) }
            .sorted { $0.date > $1.date }
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("People")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Select someone to review every sector flown together.")
                        .foregroundStyle(OpenPilotTheme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Table(sortedPeople, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Person", value: \PersonSummary.name)
                    TableColumn("Flights", value: \PersonSummary.flightCount) { person in
                        Text("\(person.flightCount)").monospacedDigit()
                    }
                    .width(75)
                    TableColumn("Hours", value: \PersonSummary.totalMinutes) { person in
                        Text(LogbookFormatters.hours(person.totalMinutes)).monospacedDigit()
                    }
                    .width(90)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            .frame(minWidth: 410, idealWidth: 530)

            PersonInspector(person: selectedPerson, flights: matchingFlights, openFlight: store.showFlight)
                .frame(minWidth: 420, idealWidth: 520)
        }
        .navigationTitle("People")
        .onAppear {
            if selection == nil { selection = sortedPeople.first?.id }
        }
    }
}

private struct PersonInspector: View {
    var person: PersonSummary?
    var flights: [FlightEntry]
    var openFlight: (FlightEntry) -> Void

    var body: some View {
        if let person {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(OpenPilotTheme.cyan)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.name).font(.title2.weight(.semibold))
                            Text("\(person.flightCount) flights · \(LogbookFormatters.hours(person.totalMinutes))")
                                .foregroundStyle(OpenPilotTheme.muted)
                        }
                    }

                    HStack(spacing: 10) {
                        inspectorMetric("Routes", Set(flights.map(\.routeDisplay)).count)
                        inspectorMetric("Aircraft", Set(flights.map(\.aircraftID)).count)
                        inspectorMetric("Landings", flights.reduce(0) { $0 + $1.totalLandings })
                    }

                    Panel("Flights together", systemImage: "airplane") {
                        LazyVStack(spacing: 0) {
                            ForEach(flights) { flight in
                                Button { openFlight(flight) } label: {
                                    HStack(spacing: 10) {
                                        Text(LogbookFormatters.dateFormatter.string(from: flight.date))
                                            .frame(width: 94, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(flight.routeDisplay.replacingOccurrences(of: " -> ", with: "-"))
                                            Text([flight.flightNumber, flight.aircraftID].filter { !$0.isEmpty }.joined(separator: " · "))
                                                .font(.caption)
                                                .foregroundStyle(OpenPilotTheme.muted)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Text(flight.crewRoleMap[person.name] ?? "Crew")
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(OpenPilotTheme.cyan)
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
            EmptyStateBlock(title: "Select a person", message: "Their routes and shared flights will appear here.", systemImage: "person.2")
        }
    }

    private func inspectorMetric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).font(.caption2).foregroundStyle(OpenPilotTheme.muted)
            Text("\(value)").font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }
}
