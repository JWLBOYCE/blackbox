import SwiftUI
import OpenPilotLogbookCore

struct LogbookPagesView: View {
    @ObservedObject var store: LogbookStore
    @State private var selectedPageID: Int?

    private var pages: [LogbookPageRecord] {
        Array(LogbookPageRecord.make(from: store.flights).reversed())
    }

    private var selectedPage: LogbookPageRecord? {
        pages.first { $0.id == selectedPageID } ?? pages.first
    }

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Logbook Pages")
                        .font(.system(size: 30, weight: .semibold))
                    Text("Sixteen sectors per page, with page and cumulative closing totals.")
                        .foregroundStyle(OpenPilotTheme.muted)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                Table(pages, selection: $selectedPageID) {
                    TableColumn("Page") { page in
                        Text("\(page.pageNumber)").monospacedDigit()
                    }
                    .width(55)
                    TableColumn("Period") { page in
                        Text(page.period)
                    }
                    .width(min: 170, ideal: 210)
                    TableColumn("Sectors") { page in
                        Text("\(page.sectorCount)").monospacedDigit()
                    }
                    .width(62)
                    TableColumn("Page Total") { page in
                        Text(LogbookFormatters.hours(page.page.totalMinutes)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Closing Total") { page in
                        Text(LogbookFormatters.hours(page.cumulative.totalMinutes)).monospacedDigit()
                    }
                    .width(100)
                    TableColumn("Ends") { page in
                        Text(page.endingFlightNumber.isEmpty ? page.endingRoute : page.endingFlightNumber)
                    }
                    .width(min: 80, ideal: 100)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
            .frame(minWidth: 510, idealWidth: 650)

            if let selectedPage {
                PageInspector(page: selectedPage) { flight in
                    store.showFlight(flight)
                }
                .frame(minWidth: 420, idealWidth: 480)
            }
        }
        .navigationTitle("Logbook Pages")
        .onAppear {
            if selectedPageID == nil { selectedPageID = pages.first?.id }
        }
    }
}

private struct PageInspector: View {
    var page: LogbookPageRecord
    var openFlight: (FlightEntry) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Page \(page.pageNumber)")
                            .font(.title2.weight(.semibold))
                        Text("\(page.period) · \(page.sectorCount) sectors")
                            .foregroundStyle(OpenPilotTheme.muted)
                    }
                    Spacer()
                    Button("Open ending flight") {
                        if let flight = page.flights.last { openFlight(flight) }
                    }
                        .buttonStyle(.bordered)
                }

                totalsPanel("This page", metrics: page.page)
                totalsPanel("Cumulative at \(page.endingLabel)", metrics: page.cumulative)

                Panel("Page sectors", systemImage: "list.number") {
                    VStack(spacing: 0) {
                        ForEach(page.flights) { flight in
                            Button {
                                openFlight(flight)
                            } label: {
                                HStack(spacing: 10) {
                                    Text(LogbookFormatters.dateFormatter.string(from: flight.date))
                                        .frame(width: 94, alignment: .leading)
                                    Text(flight.flightNumber.isEmpty ? "-" : flight.flightNumber)
                                        .frame(width: 72, alignment: .leading)
                                    Text(flight.routeDisplay.replacingOccurrences(of: " -> ", with: "-"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(LogbookFormatters.hours(flight.flyingMinutes))
                                        .monospacedDigit()
                                }
                                .contentShape(Rectangle())
                                .padding(.vertical, 7)
                            }
                            .buttonStyle(.plain)
                            Divider().opacity(0.18)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private func totalsPanel(_ title: String, metrics: PageMetrics) -> some View {
        Panel(title, systemImage: "sum") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), spacing: 10)], spacing: 10) {
                pageMetric("Total", metrics.totalMinutes)
                pageMetric("PICUS Day", metrics.picusDayMinutes)
                pageMetric("PICUS Night", metrics.picusNightMinutes)
                pageMetric("P2 Day", metrics.copilotDayMinutes)
                pageMetric("P2 Night", metrics.copilotNightMinutes)
                pageMetric("Instrument", metrics.instrumentMinutes)
                pageMetric("Cross-country", metrics.crossCountryMinutes)
            }
        }
    }

    private func pageMetric(_ title: String, _ minutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(OpenPilotTheme.muted)
            Text(LogbookFormatters.hours(minutes))
                .font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
    }

}

private struct LogbookPageRecord: Identifiable {
    var id: Int { pageNumber }
    var pageNumber: Int
    var flights: [FlightEntry]
    var page: PageMetrics
    var cumulative: PageMetrics

    var sectorCount: Int { flights.count }
    var startDate: Date { flights.first?.date ?? .distantPast }
    var period: String {
        guard let first = flights.first, let last = flights.last else { return "-" }
        return "\(LogbookFormatters.dateFormatter.string(from: first.date)) – \(LogbookFormatters.dateFormatter.string(from: last.date))"
    }
    var endingFlightNumber: String { flights.last?.flightNumber ?? "" }
    var endingRoute: String { flights.last?.routeDisplay ?? "" }
    var endingLabel: String { endingFlightNumber.isEmpty ? endingRoute : endingFlightNumber }
    var pageTotalMinutes: Int { page.totalMinutes }
    var closingTotalMinutes: Int { cumulative.totalMinutes }

    static func make(from flights: [FlightEntry]) -> [LogbookPageRecord] {
        let ordered = flights.sorted { ($0.date, $0.id ?? 0) < ($1.date, $1.id ?? 0) }
        var records: [LogbookPageRecord] = []
        var cumulative = PageMetrics()
        var start = 0
        while start < ordered.count {
            let end = min(start + 16, ordered.count)
            let chunk = Array(ordered[start..<end])
            let page = PageMetrics(flights: chunk)
            cumulative.add(page)
            records.append(LogbookPageRecord(pageNumber: records.count + 1, flights: chunk, page: page, cumulative: cumulative))
            start = end
        }
        return records
    }
}

private struct PageMetrics {
    var totalMinutes = 0
    var picusDayMinutes = 0
    var picusNightMinutes = 0
    var copilotDayMinutes = 0
    var copilotNightMinutes = 0
    var instrumentMinutes = 0
    var crossCountryMinutes = 0

    init() {}

    init(flights: [FlightEntry]) {
        for flight in flights {
            totalMinutes += flight.flyingMinutes
            picusDayMinutes += flight.picusDayMinutes
            picusNightMinutes += flight.picusNightMinutes
            copilotDayMinutes += flight.copilotDayMinutes
            copilotNightMinutes += flight.copilotNightMinutes
            instrumentMinutes += flight.flyingInstrumentMinutes
            crossCountryMinutes += flight.crossCountryMinutes
        }
    }

    mutating func add(_ other: PageMetrics) {
        totalMinutes += other.totalMinutes
        picusDayMinutes += other.picusDayMinutes
        picusNightMinutes += other.picusNightMinutes
        copilotDayMinutes += other.copilotDayMinutes
        copilotNightMinutes += other.copilotNightMinutes
        instrumentMinutes += other.instrumentMinutes
        crossCountryMinutes += other.crossCountryMinutes
    }
}
