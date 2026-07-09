import Foundation

public enum LogbookAnalysis {
    public static func recencySnapshot(flights: [FlightEntry], now: Date = Date()) -> RecencySnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let last12 = calendar.date(byAdding: .year, value: -1, to: now) ?? Date.distantPast
        let last90 = calendar.date(byAdding: .day, value: -90, to: now) ?? Date.distantPast
        let last12Flights = flights.filter { $0.date >= last12 && $0.date <= now }
        let last90Flights = flights.filter { $0.date >= last90 && $0.date <= now }
        let lastLanding = flights.filter { $0.totalLandings > 0 }.max(by: { $0.date < $1.date })?.date
        let lastNightLanding = flights.filter { $0.nightLandings > 0 }.max(by: { $0.date < $1.date })?.date
        return RecencySnapshot(
            hoursLast12Months: last12Flights.reduce(0) { $0 + $1.flyingMinutes },
            hoursLast90Days: last90Flights.reduce(0) { $0 + $1.flyingMinutes },
            landingsLast90Days: last90Flights.reduce(0) { $0 + $1.totalLandings },
            nightLandingsLast90Days: last90Flights.reduce(0) { $0 + $1.nightLandings },
            instrumentLast90Days: last90Flights.reduce(0) { $0 + $1.flyingInstrumentMinutes },
            daysSinceLastLanding: lastLanding.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 },
            daysSinceLastNightLanding: lastNightLanding.map { calendar.dateComponents([.day], from: $0, to: now).day ?? 0 }
        )
    }

    public static func duplicateGroups(flights: [FlightEntry]) -> [DuplicateFlightGroup] {
        let grouped = Dictionary(grouping: flights) { flight in
            [
                LogbookFormatters.isoDayFormatter.string(from: flight.date),
                flight.departure.uppercased(),
                flight.arrival.uppercased(),
                flight.aircraftID.uppercased(),
                flight.flightNumber.uppercased(),
                "\(flight.totalMinutes)"
            ].joined(separator: "|")
        }
        return grouped.compactMap { key, flights in
            let ordered = flights.sorted { $0.date < $1.date }
            return ordered.count > 1 ? DuplicateFlightGroup(id: key, flights: ordered) : nil
        }
        .sorted { $0.id < $1.id }
    }
}

public enum RosterImportPolicy {
    public static let ignoredDutyCodes: Set<String> = [
        "GDR", "GT", "SG", "GLD", "LR", "LB", "WR", "OFF", "DO", "SBY", "STBY", "LEAVE"
    ]

    public static func shouldImportDutyToken(_ token: String) -> Bool {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !ignoredDutyCodes.contains(normalized) else { return false }
        return normalized.count == 3 || normalized.count == 4
    }

    public static func normalizedICAO(_ token: String) -> String? {
        let normalized = token.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard shouldImportDutyToken(normalized) else { return nil }
        if normalized.count == 4 { return normalized }
        if let airport = AirportCoordinateService.shared.airport(for: normalized) {
            return airport.identifier
        }
        return nil
    }
}
