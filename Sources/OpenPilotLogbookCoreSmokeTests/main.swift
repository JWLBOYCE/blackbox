import Foundation
import AppKit
import OpenPilotLogbookCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Smoke test failed: \(message)\n", stderr)
        exit(1)
    }
}

expect(LogbookFormatters.hours(0) == "00:00", "zero hour formatting")
expect(LogbookFormatters.hours(65) == "01:05", "minute hour formatting")
expect(LogbookFormatters.hours(90) == "01:30", "HH:MM hour formatting")

let flight = FlightEntry(
    date: Date(timeIntervalSince1970: 0),
    departure: "EGLL",
    arrival: "EGKK",
    aircraftID: "G-TEST",
    aircraftType: "A320",
    operation: "MP",
    pilotFunction: "Co-pilot",
    totalMinutes: 60,
    copilotMinutes: 60,
    remarks: "Line check, \"signed\""
)
let csv = ReportExporter.csv(flights: [flight])
expect(csv.contains("\"Line check, \"\"signed\"\"\""), "CSV quote escaping")
expect(csv.contains("01:00"), "CSV should use HH:MM flight time")
expect(!csv.contains(",1.0,"), "CSV should not use decimal flight time")

let html = ReportExporter.html(flights: [], summary: LogbookSummary())
expect(!html.contains("Owner full name"), "HTML should not require owner signature placeholder")
expect(!html.contains("CAA reference number"), "HTML should not require CAA reference placeholder")
let flightHTML = ReportExporter.html(flights: [flight], summary: LogbookSummary(flightCount: 1, totalMinutes: 60, copilotMinutes: 60))
expect(flightHTML.contains("01:00"), "HTML should use HH:MM flight time")

let repository = LogbookRepository(paths: .desktopBackup)
try repository.bootstrapIfNeeded()
let summary = try repository.summary()
expect(summary.flightCount == 3036, "expected imported LogTen backup plus roster flight count")
expect(summary.distanceNM > 2_000_000, "expected imported route mileage")
expect(summary.copilotMinutes > 400_000, "expected LogTen co-pilot total from SIC, P1US, and multi-crew inference")
expect(summary.copilotDayMinutes > 300_000, "expected co-pilot day split from LogTen fields and route night split")
expect(summary.copilotNightMinutes > 100_000, "expected co-pilot night split from LogTen fields and route night split")
expect(summary.copilotDayMinutes + summary.copilotNightMinutes == summary.copilotMinutes, "expected co-pilot day and night to total co-pilot time")
let compliance = try repository.complianceSnapshot()
let functionIssues = compliance.issues.filter { $0.field == "Function" }
expect(functionIssues.isEmpty, "expected imported flights to have inferred CAA pilot function time")
let comparison = try repository.logTenComparisonSnapshot()
expect(comparison.logTen.flightCount > 2_900, "expected LogTen Pro source comparison rows")
expect(comparison.missingInBlackbox == 0, "expected every LogTen Pro source row to be present in Blackbox imports")
expect(comparison.missingInLogTen == 0, "expected every Blackbox imported row to map back to LogTen Pro")
expect(comparison.issues.isEmpty, "expected LogTen Pro source fields to match Blackbox imported rows")
expect(comparison.blackboxOnly.flightCount == 42, "expected roster entries to be Blackbox-only in comparison")
let mapRoutes = try repository.mapRoutes(limit: 5000)
let productionFlights = try repository.flights()
expect(productionFlights.first?.date == utcDate(year: 2026, month: 6, day: 29, hour: 18, minute: 15), "expected newest roster flight to be present")
let rosterSectorNumbers = productionFlights
    .filter { $0.date >= utcDate(year: 2026, month: 4, day: 24, hour: 0, minute: 0) && $0.date <= utcDate(year: 2026, month: 6, day: 29, hour: 23, minute: 59) }
    .compactMap { sectorNumber(in: $0.remarks) }
expect(rosterSectorNumbers.count == 42, "expected April, May, and June roster imports to have sector notes")
expect(rosterSectorNumbers.min() == 1988 && rosterSectorNumbers.max() == 2029, "expected roster sectors to continue from LogTen Pro")
let placeVisits = try repository.placeVisitSummaries()
let typeSummaries = try repository.typeSummaries()
let suggestionBundle = try repository.suggestions()
let people = try repository.personSummaries()
expect(mapRoutes.count > 2500, "expected geocoded routes for 3D map")
expect(placeVisits.count > 50, "expected place visit summaries")
expect(!typeSummaries.isEmpty, "expected aircraft type summaries")
expect(!suggestionBundle.aircraftIDs.isEmpty, "expected aircraft suggestions")
expect(people.contains { $0.name == "James Boyce" }, "expected people analytics to use full crew names")
expect(!people.contains { $0.name == "James" || $0.name == "Boyce" }, "expected people analytics not to split first and last names")
let egll = AirportCoordinateService.shared.coordinate(for: "EGLL")
expect(abs((egll?.latitude ?? 0) - 51.4706) < 0.05, "expected OurAirports EGLL latitude")
expect(abs((egll?.longitude ?? 0) - (-0.4619)) < 0.05, "expected OurAirports EGLL longitude")
let daylight = SolarDayNightCalculator.nightMinutes(
    departure: utcDate(year: 2026, month: 6, day: 21, hour: 12, minute: 0),
    durationMinutes: 60,
    departureLatitude: 51.4706,
    departureLongitude: -0.4619,
    arrivalLatitude: 51.1481,
    arrivalLongitude: -0.1903
)
let darkness = SolarDayNightCalculator.nightMinutes(
    departure: utcDate(year: 2026, month: 1, day: 15, hour: 23, minute: 0),
    durationMinutes: 60,
    departureLatitude: 51.4706,
    departureLongitude: -0.4619,
    arrivalLatitude: 51.1481,
    arrivalLongitude: -0.1903
)
expect(daylight == 0, "expected summer midday EGLL-EGKK sector to be day")
expect(darkness == 60, "expected winter late-night EGLL-EGKK sector to be night")

let parsed = TextFlightParser.parseCandidates(
    from: "21/06/2026 EGLL LCLK G-TEST 4:20 SIC4:20 NIGHT1:10 PAX144 1769NM",
    suggestions: try repository.suggestions()
)
expect(parsed.count == 1, "expected one parsed OCR candidate")
expect(parsed[0].flight.copilotNightMinutes == 70, "expected parsed SIC night split")
expect(parsed[0].flight.passengerCount == 144, "expected parsed passenger count")

let screenshotURL = FileManager.default.temporaryDirectory.appendingPathComponent("openpilotlogbook-import-check.png")
try makeImportScreenshot(text: "21/06/2026 EGLL LCLK G-TEST 4:20 SIC4:20 NIGHT1:10 PAX144 1769NM", url: screenshotURL)
let screenshotCandidates = try FlightDocumentImporter.candidates(from: [screenshotURL], suggestions: try repository.suggestions())
expect(!screenshotCandidates.isEmpty, "expected screenshot OCR import candidate")

let pdfURL = try makeImportPDF(text: "22/06/2026 EGLL EGKK G-PDFT 1:05 SIC1:05 PAX12 40NM")
let pdfCandidates = try FlightDocumentImporter.candidates(from: [pdfURL], suggestions: try repository.suggestions())
expect(!pdfCandidates.isEmpty, "expected PDF import candidate")

let exports = try ReportExporter.exportCAAResources(flights: try repository.flights(), summary: summary, to: LogbookPaths.desktopBackup.backupFolder)
let exportedHTML = try String(contentsOf: exports.html, encoding: .utf8)
let exportedCSV = try String(contentsOf: exports.csv, encoding: .utf8)
expect(exportedHTML.contains("Page totals"), "expected printable page totals")
expect(exportedHTML.contains("SIC Night"), "expected SIC night column in printable export")
expect(exportedCSV.contains("Co-pilot Day,Co-pilot Night"), "expected co-pilot split columns in CSV")

try checkDesktopWorkingStoreTodayAddDelete(repository: repository)
try checkEditableWorkflow(sourcePaths: .desktopBackup)
try checkLogTenImporter(sourcePaths: .desktopBackup)

print("OpenPilotLogbookCore smoke tests passed: \(summary.flightCount) imported flights.")

func makeImportScreenshot(text: String, url: URL) throws {
    let size = NSSize(width: 2200, height: 320)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.white.setFill()
    NSRect(origin: .zero, size: size).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 64, weight: .regular),
        .foregroundColor: NSColor.black
    ]
    (text as NSString).draw(in: NSRect(x: 40, y: 120, width: 2120, height: 120), withAttributes: attributes)
    image.unlockFocus()
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "OpenPilotLogbookSmoke", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create screenshot test image"])
    }
    try png.write(to: url)
}

func makeImportPDF(text: String) throws -> URL {
    let temp = FileManager.default.temporaryDirectory
    let pdfURL = temp.appendingPathComponent("openpilotlogbook-import-check.pdf")
    try? FileManager.default.removeItem(at: pdfURL)
    var mediaBox = CGRect(x: 0, y: 0, width: 1200, height: 300)
    guard let consumer = CGDataConsumer(url: pdfURL as CFURL),
          let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
        throw NSError(domain: "OpenPilotLogbookSmoke", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not create PDF context"])
    }
    context.beginPDFPage(nil)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    NSColor.white.setFill()
    NSRect(x: 0, y: 0, width: 1200, height: 300).fill()
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 42, weight: .regular),
        .foregroundColor: NSColor.black
    ]
    (text as NSString).draw(in: NSRect(x: 40, y: 130, width: 1120, height: 80), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    context.endPDFPage()
    context.closePDF()
    return pdfURL
}

func checkEditableWorkflow(sourcePaths: LogbookPaths) throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("OpenPilotLogbookSmoke-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let paths = LogbookPaths(
        backupFolder: temp,
        sourceLogTenDatabase: sourcePaths.sourceLogTenDatabase,
        workingDatabase: temp.appendingPathComponent("OpenPilotLogbook.sqlite")
    )
    let tempRepository = LogbookRepository(paths: paths)
    try tempRepository.bootstrapIfNeeded()
    let before = try tempRepository.summary().flightCount
    let editableDate = Date(timeIntervalSince1970: 1_782_000_000)
    let editableNight = SolarDayNightCalculator.nightMinutes(
        departure: editableDate,
        durationMinutes: 65,
        departureLatitude: 51.4706,
        departureLongitude: -0.4619,
        arrivalLatitude: 51.1481,
        arrivalLongitude: -0.1903
    )
    let id = try tempRepository.save(FlightEntry(
        date: editableDate,
        departure: "EGLL",
        arrival: "EGKK",
        aircraftID: "G-SMOK",
        aircraftType: "A320",
        operation: "MP",
        pilotFunction: "Co-pilot",
        totalMinutes: 65,
        copilotMinutes: 65,
        nightMinutes: 20,
        pilotFlying: true,
        passengerCount: 12,
        crewNames: "Test Captain | James Boyce | Relief Pilot",
        remarks: "Smoke editable workflow"
    ))
    var saved = try tempRepository.flight(id: id)
    expect(saved?.pilotFunction == "PIC", "expected pilot flying to promote function to PIC")
    expect(saved?.picDayMinutes == 65 - editableNight, "expected save-time PIC day split")
    expect(saved?.picNightMinutes == editableNight, "expected save-time PIC night split")
    expect(saved?.copilotMinutes == 0, "expected pilot-flying entry not to double-count co-pilot time")
    expect(saved?.instrumentMinutes == 65, "expected flight IFR/instrument to mirror total")
    expect(saved?.crossCountryMinutes == 65, "expected flight cross-country to mirror total")
    expect((saved?.distanceNM ?? 0) > 0, "expected save-time route distance")
    expect(saved?.operation == "MP", "expected two crew names to force multi-pilot operation")
    expect(saved?.totalTakeoffs == 1, "expected pilot-flying save to populate takeoff count")
    expect(saved?.totalLandings == 1, "expected pilot-flying save to populate landing count")
    expect(saved?.remarks.contains("Sector ") == true, "expected save-time sector note")
    expect(saved?.crewRoles.contains("Test Captain=Captain") == true, "expected first non-James crew member to infer Captain role")
    expect(saved?.crewRoles.contains("James Boyce=First Officer") == true, "expected James Boyce co-pilot role to display as First Officer")
    expect(saved?.crewRoles.contains("Relief Pilot=Other crew") == true, "expected additional crew to infer Other crew role")
    saved?.remarks = "Edited smoke note"
    if let saved {
        _ = try tempRepository.save(saved)
    }
    let edited = try tempRepository.flight(id: id)
    let personSummaries = try tempRepository.personSummaries()
    expect(edited?.remarks.contains("Edited smoke note") == true, "expected edit persistence")
    expect(personSummaries.contains { $0.name == "Test Captain" }, "expected people analytics after save")
    try tempRepository.deleteFlight(id: id)
    let deleted = try tempRepository.flight(id: id)
    let after = try tempRepository.summary().flightCount
    expect(deleted == nil, "expected delete persistence")
    expect(after == before, "expected delete to restore flight count")

    let nightID = try tempRepository.save(FlightEntry(
        date: utcDate(year: 2026, month: 1, day: 15, hour: 23, minute: 0),
        departure: "EGLL",
        arrival: "EGKK",
        aircraftID: "G-NITE",
        aircraftType: "A320",
        operation: "MP",
        pilotFunction: "Co-pilot",
        totalMinutes: 60,
        copilotMinutes: 60,
        remarks: "Smoke solar night split"
    ))
    let nightFlight = try tempRepository.flight(id: nightID)
    expect(nightFlight?.nightMinutes == 60, "expected save-time almanac night calculation")
    expect(nightFlight?.copilotNightMinutes == 60, "expected save-time almanac co-pilot night split")
    try tempRepository.deleteFlight(id: nightID)

    let simID = try tempRepository.save(FlightEntry(
        date: utcDate(year: 2026, month: 2, day: 1, hour: 12, minute: 0),
        aircraftID: "A320#SIM",
        aircraftType: "FFS, LEVEL D",
        operation: "MP",
        entryKind: "Simulator",
        totalMinutes: 120,
        remarks: "Smoke simulator"
    ))
    let sim = try tempRepository.flight(id: simID)
    expect(sim?.pilotFunction == "FSTD", "expected simulator to use FSTD function")
    expect(sim?.fstdMinutes == 120, "expected simulator FSTD time to mirror total")
    expect(sim?.picMinutes == 0 && sim?.copilotMinutes == 0, "expected simulator not to allocate flight role time")
    expect(sim?.departure.isEmpty == true && sim?.arrival.isEmpty == true, "expected simulator not to require route")
    try tempRepository.deleteFlight(id: simID)
    try? FileManager.default.removeItem(at: temp)
}

func checkLogTenImporter(sourcePaths: LogbookPaths) throws {
    let temp = FileManager.default.temporaryDirectory.appendingPathComponent("BlackboxLogTenImport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    let paths = LogbookPaths(
        backupFolder: temp,
        sourceLogTenDatabase: sourcePaths.sourceLogTenDatabase,
        workingDatabase: temp.appendingPathComponent("OpenPilotLogbook.sqlite")
    )
    let tempRepository = LogbookRepository(paths: paths)
    let imported = try tempRepository.replaceWithLogTenDatabase(at: sourcePaths.sourceLogTenDatabase)
    expect(imported == 2994, "expected LogTen importer to import source flight count")
    let importedSummary = try tempRepository.summary()
    expect(importedSummary.flightCount == 2994, "expected LogTen importer to replace temp store with source rows")
    let comparison = try tempRepository.logTenComparisonSnapshot()
    expect(comparison.blackboxOnly.flightCount == 0, "expected clean LogTen import to have no Blackbox-only rows")
    if let issue = comparison.issues.first {
        expect(false, "expected clean LogTen import to match source fields; first difference \(issue.sourcePK) \(issue.field) LogTen=\(issue.logTenValue) Blackbox=\(issue.blackboxValue)")
    }
    try? FileManager.default.removeItem(at: temp)
}

func sectorNumber(in remarks: String) -> Int? {
    guard let regex = try? NSRegularExpression(pattern: #"\bSector\s+(\d+)\b"#, options: [.caseInsensitive]) else { return nil }
    let range = NSRange(remarks.startIndex..<remarks.endIndex, in: remarks)
    guard let match = regex.firstMatch(in: remarks, range: range), match.numberOfRanges > 1,
          let swiftRange = Range(match.range(at: 1), in: remarks)
    else { return nil }
    return Int(remarks[swiftRange])
}

func utcDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
}

func checkDesktopWorkingStoreTodayAddDelete(repository: LogbookRepository) throws {
    let before = try repository.summary().flightCount
    let marker = "OpenPilot checker add-delete \(UUID().uuidString)"
    let date = Date()
    let expectedNight = SolarDayNightCalculator.nightMinutes(
        departure: date,
        durationMinutes: 55,
        departureLatitude: 51.4706,
        departureLongitude: -0.4619,
        arrivalLatitude: 51.1481,
        arrivalLongitude: -0.1903
    )
    let id = try repository.save(FlightEntry(
        date: date,
        departure: "EGLL",
        arrival: "EGKK",
        aircraftID: "G-TDAY",
        aircraftType: "A320",
        operation: "MP",
        pilotFunction: "Co-pilot",
        totalMinutes: 55,
        copilotMinutes: 55,
        nightMinutes: 15,
        passengerCount: 8,
        crewNames: "Checker Captain",
        remarks: marker
    ))
    defer { try? repository.deleteFlight(id: id) }
    let saved = try repository.flight(id: id)
    expect(saved != nil, "expected today's working-store test flight to save")
    expect(saved.map { Calendar.current.isDateInToday($0.date) } ?? false, "expected today's working-store test flight date")
    expect(saved?.nightMinutes == expectedNight, "expected today's working-store night split to be position-calculated")
    expect(saved?.copilotDayMinutes == 55 - expectedNight, "expected today's working-store SIC day split")
    expect(saved?.copilotNightMinutes == expectedNight, "expected today's working-store SIC night split")
    try repository.deleteFlight(id: id)
    let after = try repository.summary().flightCount
    let matchingFlights = try repository.flights(search: marker)
    expect(after == before, "expected today's working-store delete to restore flight count")
    expect(matchingFlights.isEmpty, "expected today's working-store delete to remove marker")
}
