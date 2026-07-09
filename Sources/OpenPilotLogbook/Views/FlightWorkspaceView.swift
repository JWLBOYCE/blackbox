import SwiftUI
import OpenPilotLogbookCore

struct FlightWorkspaceView: View {
    @ObservedObject var store: LogbookStore
    @State private var sortOrder = [KeyPathComparator(\FlightTableItem.date, order: .reverse)]

    private var rows: [FlightTableItem] {
        store.flights.map(FlightTableItem.init).sorted(using: sortOrder)
    }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                flightHeader
                if !store.highlightedFlights.isEmpty {
                    SelectionSummaryBar(flights: store.highlightedFlights)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                }
                Table(rows, selection: $store.selectedRouteFlightIDs, sortOrder: $sortOrder) {
                    TableColumn("Date", value: \FlightTableItem.date) { item in
                        Text(LogbookFormatters.dateFormatter.string(from: item.date))
                            .foregroundStyle(item.rowStyle)
                    }
                    .width(90)

                    TableColumn("Out", value: \FlightTableItem.date) { item in
                        Text(LogbookFormatters.zuluTimeFormatter.string(from: item.date))
                            .monospacedDigit()
                            .foregroundStyle(item.rowStyle)
                    }
                    .width(54)

                    TableColumn("In", value: \FlightTableItem.arrivalDate) { item in
                        Text(LogbookFormatters.zuluTimeFormatter.string(from: item.arrivalDate))
                            .monospacedDigit()
                            .foregroundStyle(item.rowStyle)
                    }
                    .width(54)

                    TableColumn("Flight / Route", value: \FlightTableItem.flightNumber) { item in
                        Text([item.flightNumber, item.route].filter { !$0.isEmpty }.joined(separator: " · "))
                            .lineLimit(1)
                            .foregroundStyle(item.rowStyle)
                    }
                    .width(94)

                    TableColumn("Role", value: \FlightTableItem.function) { item in
                        Text(item.function)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(item.flight.pilotFlying ? OpenPilotTheme.green : item.rowStyle)
                    }
                    .width(48)

                    TableColumn("Duration", value: \FlightTableItem.duration) { item in
                        Text(LogbookFormatters.hours(item.duration))
                            .monospacedDigit()
                            .foregroundStyle(item.rowStyle)
                    }
                    .width(52)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
                .onChange(of: store.selectedRouteFlightIDs) { oldValue, newValue in
                    store.updateFlightSelection(from: oldValue, to: newValue)
                }
            }
            .frame(minWidth: 530, idealWidth: 650)

            FlightEditorView(store: store)
                .padding(.trailing, 18)
                .padding(.vertical, 18)
                .frame(minWidth: 430)
        }
        .navigationTitle("Flights")
    }

    private var flightHeader: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Flights")
                    .font(.title2.weight(.semibold))
                Text("Click a heading to sort. Shift-click or use Shift-arrow to select a range.")
                    .font(.caption)
                    .foregroundStyle(OpenPilotTheme.muted)
            }
            Spacer()
            TextField("Search", text: $store.searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 210)
                .onSubmit { store.applySearch() }
            Button(action: store.copySelectedFlights) {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy selected flights")
            Button(action: store.pasteFlights) {
                Image(systemName: "doc.on.clipboard")
            }
            .help("Paste copied flights as unlocked entries")
            Text("\(store.flights.count.formatted())")
                .font(.caption.monospacedDigit())
                .foregroundStyle(OpenPilotTheme.muted)
        }
        .padding(14)
    }
}

private struct FlightTableItem: Identifiable {
    var flight: FlightEntry
    var id: Int64 { flight.id ?? -1 }
    var date: Date { flight.date }
    var arrivalDate: Date { flight.arrivalDate }
    var flightNumber: String { flight.flightNumber }
    var route: String { flight.routeDisplay.replacingOccurrences(of: " -> ", with: "-") }
    var aircraft: String { flight.aircraftID }
    var function: String { flight.pilotFunction == "Co-pilot" ? "P2" : flight.pilotFunction }
    var duration: Int { flight.flyingMinutes }
    var rowStyle: Color { flight.locked ? OpenPilotTheme.muted.opacity(0.72) : .primary }
}

private struct SelectionSummaryBar: View {
    var flights: [FlightEntry]

    private var total: (Int, Int, Int, Int, Int, Int, Int) {
        flights.reduce(into: (0, 0, 0, 0, 0, 0, 0)) { result, flight in
            result.0 += flight.flyingMinutes
            result.1 += flight.picusDayMinutes
            result.2 += flight.picusNightMinutes
            result.3 += flight.copilotDayMinutes
            result.4 += flight.copilotNightMinutes
            result.5 += flight.flyingInstrumentMinutes
            result.6 += flight.crossCountryMinutes
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Label("\(flights.count) selected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(OpenPilotTheme.cyan)
            summary("Total", total.0)
            summary("PICUS D", total.1)
            summary("PICUS N", total.2)
            summary("P2 D", total.3)
            summary("P2 N", total.4)
            summary("IFR", total.5)
            summary("XC", total.6)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OpenPilotTheme.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 6))
    }

    private func summary(_ title: String, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(OpenPilotTheme.muted)
            Text(LogbookFormatters.hours(minutes)).font(.caption.monospacedDigit().weight(.semibold))
        }
    }
}
