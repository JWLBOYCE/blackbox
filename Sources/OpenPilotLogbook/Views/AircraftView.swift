import SwiftUI
import OpenPilotLogbookCore

struct AircraftView: View {
    @ObservedObject var store: LogbookStore
    @State private var sortOrder = [KeyPathComparator(\AircraftSummary.totalMinutes, order: .reverse)]

    private var sortedAircraft: [AircraftSummary] {
        store.aircraft.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            Panel("Aircraft History", systemImage: "airplane.circle") {
                Table(sortedAircraft, sortOrder: $sortOrder) {
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
                .scrollContentBackground(.hidden)
            }
        }
        .padding(24)
        .navigationTitle("Aircraft")
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
            MetricTile(title: "Aircraft", value: "\(store.aircraft.count)", systemImage: "airplane.circle", tint: OpenPilotTheme.blue)
                .frame(width: 210)
        }
    }
}
