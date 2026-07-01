import Foundation

public enum ReportExporter {
    public static func exportCAAResources(flights: [FlightEntry], summary: LogbookSummary, to folder: URL) throws -> (csv: URL, html: URL) {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let csvURL = folder.appendingPathComponent("CAA_Logbook_Export_\(stamp).csv")
        let htmlURL = folder.appendingPathComponent("CAA_Logbook_Printable_\(stamp).html")
        try csv(flights: flights).write(to: csvURL, atomically: true, encoding: .utf8)
        try html(flights: flights, summary: summary).write(to: htmlURL, atomically: true, encoding: .utf8)
        return (csvURL, htmlURL)
    }

    public static func csv(flights: [FlightEntry]) -> String {
        let header = [
            "Date", "Departure", "Arrival", "Aircraft ID", "Aircraft Type", "SP/MP",
            "Total", "PIC", "Co-pilot", "Co-pilot Day", "Co-pilot Night", "Dual", "Instructor", "Night", "IFR/Instrument",
            "FSTD", "Pilot Flying", "Takeoffs", "Landings", "Passengers", "Nautical miles", "Notes"
        ].joined(separator: ",")
        let rows = flights.sorted { $0.date < $1.date }.map { flight in
            [
                LogbookFormatters.shortDateFormatter.string(from: flight.date),
                flight.departure, flight.arrival, flight.aircraftID, flight.aircraftType, flight.operation,
                LogbookFormatters.hours(flight.totalMinutes),
                LogbookFormatters.hours(flight.picMinutes),
                LogbookFormatters.hours(flight.copilotMinutes),
                LogbookFormatters.hours(flight.copilotDayMinutes),
                LogbookFormatters.hours(flight.copilotNightMinutes),
                LogbookFormatters.hours(flight.dualMinutes),
                LogbookFormatters.hours(flight.instructorMinutes),
                LogbookFormatters.hours(flight.nightMinutes),
                LogbookFormatters.hours(flight.instrumentMinutes),
                LogbookFormatters.hours(flight.fstdMinutes),
                flight.pilotFlying ? "Yes" : "No",
                String(flight.totalTakeoffs),
                String(flight.totalLandings),
                String(flight.passengerCount),
                String(format: "%.1f", flight.distanceNM),
                flight.remarks
            ].map(LogbookFormatters.csvEscape).joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    public static func html(flights: [FlightEntry], summary: LogbookSummary) -> String {
        let sortedFlights = flights.sorted { $0.date < $1.date }
        let pageSize = 24
        let pages = stride(from: 0, to: sortedFlights.count, by: pageSize).map { start -> String in
            let pageFlights = Array(sortedFlights[start..<min(start + pageSize, sortedFlights.count)])
            let rows = pageFlights.map { flight in
            """
            <tr>
              <td>\(escape(LogbookFormatters.shortDateFormatter.string(from: flight.date)))</td>
              <td>\(escape(flight.departure))</td>
              <td>\(escape(flight.arrival))</td>
              <td>\(escape(flight.aircraftID))</td>
              <td>\(escape(flight.aircraftType))</td>
              <td>\(escape(flight.operation))</td>
              <td>\(escape(LogbookFormatters.hours(flight.totalMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.picMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.copilotMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.copilotDayMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.copilotNightMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.dualMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.instructorMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.nightMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.instrumentMinutes)))</td>
              <td>\(escape(LogbookFormatters.hours(flight.fstdMinutes)))</td>
              <td>\(flight.pilotFlying ? "Yes" : "No")</td>
              <td>\(flight.totalTakeoffs)</td>
              <td>\(flight.totalLandings)</td>
              <td>\(flight.passengerCount)</td>
              <td>\(String(format: "%.0f", flight.distanceNM))</td>
              <td>\(escape(flight.remarks))</td>
            </tr>
            """
            }.joined(separator: "\n")
            let subtotal = LogbookSummary(
                flightCount: pageFlights.count,
                totalMinutes: pageFlights.reduce(0) { $0 + $1.totalMinutes },
                picMinutes: pageFlights.reduce(0) { $0 + $1.picMinutes },
                copilotMinutes: pageFlights.reduce(0) { $0 + $1.copilotMinutes },
                copilotDayMinutes: pageFlights.reduce(0) { $0 + $1.copilotDayMinutes },
                copilotNightMinutes: pageFlights.reduce(0) { $0 + $1.copilotNightMinutes },
                nightMinutes: pageFlights.reduce(0) { $0 + $1.nightMinutes },
                instrumentMinutes: pageFlights.reduce(0) { $0 + $1.instrumentMinutes },
                landings: pageFlights.reduce(0) { $0 + $1.totalLandings },
                passengers: pageFlights.reduce(0) { $0 + $1.passengerCount },
                distanceNM: pageFlights.reduce(0) { $0 + $1.distanceNM }
            )
            return """
            <section class="page">
              <table>
                <thead>
                  <tr>
                    <th>Date</th><th>Departure</th><th>Arrival</th><th>Aircraft</th><th>Type</th><th>SP/MP</th>
                    <th>Total</th><th>PIC</th><th>Co-pilot</th><th>SIC Day</th><th>SIC Night</th><th>Dual</th><th>Instructor</th><th>Night</th><th>IFR</th><th>FSTD</th><th>PF</th><th>TO</th><th>Landings</th><th>PAX</th><th>NM</th><th>Notes</th>
                  </tr>
                </thead>
                <tbody>
                  \(rows)
                </tbody>
                <tfoot>
                  <tr class="subtotal">
                    <td colspan="6">Page totals</td>
                    <td>\(LogbookFormatters.hours(subtotal.totalMinutes))</td>
                    <td>\(LogbookFormatters.hours(subtotal.picMinutes))</td>
                    <td>\(LogbookFormatters.hours(subtotal.copilotMinutes))</td>
                    <td>\(LogbookFormatters.hours(subtotal.copilotDayMinutes))</td>
                    <td>\(LogbookFormatters.hours(subtotal.copilotNightMinutes))</td>
                    <td>\(LogbookFormatters.hours(pageFlights.reduce(0) { $0 + $1.dualMinutes }))</td>
                    <td>\(LogbookFormatters.hours(pageFlights.reduce(0) { $0 + $1.instructorMinutes }))</td>
                    <td>\(LogbookFormatters.hours(subtotal.nightMinutes))</td>
                    <td>\(LogbookFormatters.hours(subtotal.instrumentMinutes))</td>
                    <td>\(LogbookFormatters.hours(pageFlights.reduce(0) { $0 + $1.fstdMinutes }))</td>
                    <td>\(pageFlights.filter(\.pilotFlying).count)</td>
                    <td>\(pageFlights.reduce(0) { $0 + $1.totalTakeoffs })</td>
                    <td>\(subtotal.landings)</td>
                    <td>\(subtotal.passengers)</td>
                    <td>\(String(format: "%.0f", subtotal.distanceNM))</td>
                    <td></td>
                  </tr>
                </tfoot>
              </table>
            </section>
            """
        }.joined(separator: "\n")
        return """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>CAA Pilot Logbook Export</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; margin: 32px; color: #111; }
            h1 { margin-bottom: 4px; }
            .meta { display: grid; grid-template-columns: 180px 1fr; gap: 8px; margin: 24px 0; }
            table { width: 100%; border-collapse: collapse; font-size: 10px; }
            th, td { border: 1px solid #999; padding: 4px 5px; vertical-align: top; }
            th { background: #f2f2f2; }
            .subtotal td { font-weight: 700; background: #fafafa; }
            .page { page-break-after: always; margin-top: 18px; }
            @media print { body { margin: 12mm; } table { font-size: 9px; } }
          </style>
        </head>
        <body>
          <h1>CAA Pilot Logbook Export</h1>
          <p>Electronic/printable pilot logbook copy.</p>
          <div class="meta">
            <strong>Flights</strong><span>\(summary.flightCount)</span>
            <strong>Total time</strong><span>\(LogbookFormatters.hours(summary.totalMinutes))</span>
            <strong>PIC</strong><span>\(LogbookFormatters.hours(summary.picMinutes))</span>
            <strong>Co-pilot</strong><span>\(LogbookFormatters.hours(summary.copilotMinutes))</span>
            <strong>Co-pilot day</strong><span>\(LogbookFormatters.hours(summary.copilotDayMinutes))</span>
            <strong>Co-pilot night</strong><span>\(LogbookFormatters.hours(summary.copilotNightMinutes))</span>
            <strong>Night</strong><span>\(LogbookFormatters.hours(summary.nightMinutes))</span>
            <strong>Instrument</strong><span>\(LogbookFormatters.hours(summary.instrumentMinutes))</span>
            <strong>Nautical miles</strong><span>\(String(format: "%.0f", summary.distanceNM)) NM</span>
            <strong>Passengers flown</strong><span>\(summary.passengers)</span>
          </div>
          <h2>Flight Entries</h2>
          \(pages)
        </body>
        </html>
        """
    }

    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
