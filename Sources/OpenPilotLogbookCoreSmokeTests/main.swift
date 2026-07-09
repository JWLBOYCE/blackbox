import Foundation
import OpenPilotLogbookCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Smoke test failed: \(message)\n", stderr)
        exit(1)
    }
}

let temporaryRoot = FileManager.default.temporaryDirectory
    .appendingPathComponent("BlackboxSmoke-\(UUID().uuidString)", isDirectory: true)
try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: temporaryRoot) }

let paths = LogbookPaths(
    backupFolder: temporaryRoot.appendingPathComponent("Backups", isDirectory: true),
    sourceLogTenDatabase: temporaryRoot.appendingPathComponent("MissingLogTenSource.sqlite"),
    workingDatabase: temporaryRoot.appendingPathComponent("Blackbox.sqlite")
)
let repository = LogbookRepository(paths: paths)
try FileManager.default.createDirectory(at: paths.backupFolder, withIntermediateDirectories: true)
try repository.bootstrapIfNeeded()
let initialSummary = try repository.summary()
expect(initialSummary.flightCount == 0, "expected an empty synthetic logbook")

expect(LogbookFormatters.hours(0) == "00:00", "zero hour formatting")
expect(LogbookFormatters.hours(65) == "01:05", "minute hour formatting")

let departure = utcDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0)
let flightID = try repository.save(FlightEntry(
    sourcePK: 900_001,
    date: departure,
    departure: "EGLL",
    arrival: "EGKK",
    aircraftID: "G-TEST",
    aircraftType: "A320",
    flightNumber: "TST101",
    operation: "MP",
    pilotFunction: "Co-pilot",
    totalMinutes: 65,
    copilotMinutes: 65,
    pilotFlying: true,
    crewNames: "Casey Captain | Avery Pilot",
    remarks: "Synthetic smoke flight"
))

guard var flight = try repository.flight(id: flightID) else {
    expect(false, "expected saved flight")
    exit(1)
}
expect(flight.pilotFunction == "PICUS", "expected pilot flying to use PICUS")
expect(flight.picusMinutes == 65 && flight.copilotMinutes == 0, "expected PICUS allocation")
expect(flight.instrumentMinutes == 65 && flight.crossCountryMinutes == 65, "expected flight IFR and cross-country allocation")
expect(flight.totalTakeoffs == 1 && flight.totalLandings == 1, "expected pilot-flying endpoints")
expect(flight.crewRoleMap["Casey Captain"] == "Captain", "expected captain role inference")
expect(flight.crewRoleMap["Avery Pilot"] == "First Officer", "expected first-officer role inference")
expect(flight.distanceNM > 0, "expected nautical-mile route distance")

flight.pilotFlying = false
flight.dayTakeoffs = 0
flight.nightTakeoffs = 1
flight.totalTakeoffs = 1
flight.dayLandings = 0
flight.nightLandings = 1
flight.totalLandings = 1
flight.crewRoles = "Casey Captain=Captain | Avery Pilot=First Officer"
_ = try repository.save(flight)
guard let overridden = try repository.flight(id: flightID) else {
    expect(false, "expected overridden flight")
    exit(1)
}
expect(overridden.sourcePK == 900_001, "expected source identifier to remain intact")
expect(overridden.nightTakeoffs == 1 && overridden.nightLandings == 1, "expected manual endpoint override to persist")
expect(overridden.crewRoleMap["Avery Pilot"] == "First Officer", "expected manual crew role override to persist")

try repository.lockFlight(id: flightID)
do {
    var locked = try repository.flight(id: flightID)!
    locked.remarks = "Blocked edit"
    _ = try repository.save(locked)
    expect(false, "expected locked flight save to fail")
} catch {}
try repository.unlockFlight(id: flightID)

let simulatorID = try repository.save(FlightEntry(
    date: departure,
    aircraftID: "SIM-A320",
    aircraftType: "Level D",
    entryKind: "Simulator",
    totalMinutes: 120,
    remarks: "Synthetic simulator"
))
let simulator = try repository.flight(id: simulatorID)
expect(simulator?.pilotFunction == "FSTD", "expected simulator function")
expect(simulator?.fstdMinutes == 120, "expected simulator allocation")

let summerNight = SolarDayNightCalculator.nightMinutes(
    departure: departure,
    durationMinutes: 60,
    departureLatitude: 51.4706,
    departureLongitude: -0.4619,
    arrivalLatitude: 51.1481,
    arrivalLongitude: -0.1903
)
expect(summerNight == 0, "expected summer daytime calculation")

let summary = try repository.summary()
expect(summary.flightCount == 2, "expected two synthetic entries")
expect(summary.totalMinutes == 65, "expected flying total to exclude simulator time")
expect(summary.fstdMinutes == 120, "expected simulator total to remain separate")
let routes = try repository.mapRoutes(limit: 10)
let people = try repository.personSummaries()
expect(routes.count == 1, "expected one geocoded synthetic route")
expect(people.contains { $0.name == "Avery Pilot" }, "expected full crew names in people summaries")

let csv = ReportExporter.csv(flights: [overridden])
expect(csv.contains("01:05"), "expected HH:MM in CSV")
let exports = try ReportExporter.exportCAAResources(
    flights: try repository.flights(),
    summary: summary,
    to: paths.backupFolder
)
let html = try String(contentsOf: exports.html, encoding: .utf8)
expect(html.contains("Page totals"), "expected printable page totals")

try repository.deleteFlight(id: simulatorID)
try repository.deleteFlight(id: flightID)
let finalSummary = try repository.summary()
expect(finalSummary.flightCount == 0, "expected synthetic entries to be removed")

print("OpenPilotLogbookCore smoke tests passed with synthetic data.")

func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
}
