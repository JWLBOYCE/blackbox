import SwiftUI
import OpenPilotLogbookCore

struct AnalysisView: View {
    @ObservedObject var store: LogbookStore
    @State private var selectedTab: AnalysisTab = .types

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Analysis")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Review type totals, people, and places visited.")
                        .foregroundStyle(OpenPilotTheme.muted)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                MetricTile(title: "Nautical miles", value: String(format: "%.0f", store.summary.distanceNM), systemImage: "point.topleft.down.curvedto.point.bottomright.up", tint: OpenPilotTheme.blue)
                MetricTile(title: "Passengers", value: "\(store.summary.passengers)", systemImage: "person.3", tint: OpenPilotTheme.green)
                MetricTile(title: "People", value: "\(store.people.count)", systemImage: "person.2.wave.2", tint: OpenPilotTheme.cyan)
                MetricTile(title: "Places", value: "\(store.places.count)", systemImage: "mappin.and.ellipse", tint: OpenPilotTheme.amber)
            }

            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Analysis", selection: $selectedTab) {
                        ForEach(AnalysisTab.allCases) { tab in
                            Label(tab.title, systemImage: tab.systemImage).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 560)

                    switch selectedTab {
                    case .types:
                        typeTable
                    case .people:
                        peopleTable
                    case .places:
                        placesTable
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(24)
        .navigationTitle("Analysis")
    }

    private var typeTable: some View {
        VStack(spacing: 8) {
            AnalysisHeader(columns: [
                ("Type", nil),
                ("Flights", 90),
                ("Hours", 110),
                ("Co-pilot Day", 130),
                ("Co-pilot Night", 140),
                ("NM", 110)
            ])
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.typeSummaries) { item in
                        AnalysisRow {
                            Text(item.aircraftType.isEmpty ? "Unknown" : item.aircraftType)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(item.flightCount)").monospacedDigit().frame(width: 90, alignment: .trailing)
                            Text(LogbookFormatters.hours(item.totalMinutes)).monospacedDigit().frame(width: 110, alignment: .trailing)
                            Text(LogbookFormatters.hours(item.copilotDayMinutes)).monospacedDigit().frame(width: 130, alignment: .trailing)
                            Text(LogbookFormatters.hours(item.copilotNightMinutes)).monospacedDigit().frame(width: 140, alignment: .trailing)
                            Text(String(format: "%.0f", item.distanceNM)).monospacedDigit().frame(width: 110, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var peopleTable: some View {
        VStack(spacing: 8) {
            AnalysisHeader(columns: [("Person", nil), ("Flights", 110), ("Hours", 130)])
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.people) { item in
                        AnalysisRow {
                            Text(item.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(item.flightCount)").monospacedDigit().frame(width: 110, alignment: .trailing)
                            Text(LogbookFormatters.hours(item.totalMinutes)).monospacedDigit().frame(width: 130, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }

    private var placesTable: some View {
        VStack(spacing: 8) {
            AnalysisHeader(columns: [("Place", 90), ("Name", nil), ("Departures", 110), ("Arrivals", 100), ("Visits", 90)])
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.places) { item in
                        AnalysisRow {
                            Text(item.identifier).frame(width: 90, alignment: .leading)
                            Text(item.name.isEmpty ? "Unknown" : item.name)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(item.departures)").monospacedDigit().frame(width: 110, alignment: .trailing)
                            Text("\(item.arrivals)").monospacedDigit().frame(width: 100, alignment: .trailing)
                            Text("\(item.departures + item.arrivals)").monospacedDigit().frame(width: 90, alignment: .trailing)
                        }
                    }
                }
            }
        }
    }
}

private enum AnalysisTab: String, CaseIterable, Identifiable {
    case types
    case people
    case places

    var id: String { rawValue }

    var title: String {
        switch self {
        case .types: return "By Type"
        case .people: return "People"
        case .places: return "Places"
        }
    }

    var systemImage: String {
        switch self {
        case .types: return "airplane.circle"
        case .people: return "person.2"
        case .places: return "mappin.and.ellipse"
        }
    }
}

private struct AnalysisHeader: View {
    var columns: [(String, CGFloat?)]

    var body: some View {
        HStack(spacing: 14) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                Text(column.0)
                    .frame(width: column.1, alignment: column.1 == nil ? .leading : .trailing)
                    .frame(maxWidth: column.1 == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(OpenPilotTheme.muted)
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}

private struct AnalysisRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 14) {
            content
        }
        .font(.callout.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.white.opacity(0.055), lineWidth: 1)
        }
    }
}
