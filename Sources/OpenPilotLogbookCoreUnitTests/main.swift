import Foundation
import OpenPilotLogbookCore

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("Unit test failed: \(message)\n", stderr)
        exit(1)
    }
}

try runUnitTests()
print("OpenPilotLogbookCore unit tests passed.")

func runUnitTests() throws {
    try testHHMMExportsAndEscaping()
    try testPrivacyGuardBlocksPrivateArtifactsOnly()
    try testEncryptedBackupRoundTrip()
    testApplicationSupportDefaultAvoidsDesktopStorage()
    testRecencyAndDuplicates()
    testRosterPolicyIgnoresGroundDutiesAndNormalizesAirports()
    try testRepositoryAirportOverrideDuplicateAndComplianceGuidance()
}

func testHHMMExportsAndEscaping() throws {
    let flight = FlightEntry(
        date: utcDate(year: 2026, month: 7, day: 1),
        departure: "EGLL",
        arrival: "EGKK",
        aircraftID: "G-TEST",
        aircraftType: "A320",
        totalMinutes: 65,
        copilotMinutes: 65,
        remarks: "Line check, \"signed\""
    )
    let csv = ReportExporter.csv(flights: [flight])
    expect(csv.contains("01:05"), "CSV should use HH:MM")
    expect(csv.contains("\"Line check, \"\"signed\"\"\""), "CSV should escape quotes")
    expect(!csv.contains("1.08"), "CSV should not use decimal hours")

    let simulator = FlightEntry(
        date: utcDate(year: 2026, month: 7, day: 2),
        aircraftID: "A320#SIM",
        aircraftType: "FFS",
        entryKind: "Simulator",
        totalMinutes: 120,
        instrumentMinutes: 120,
        fstdMinutes: 120
    )
    let simColumns = ReportExporter.csv(flights: [simulator])
        .split(separator: "\n", omittingEmptySubsequences: false)[1]
        .split(separator: ",", omittingEmptySubsequences: false)
    expect(simulator.flyingMinutes == 0, "simulator flying minutes should be zero")
    expect(simulator.flyingInstrumentMinutes == 0, "simulator instrument minutes should not count as flying instrument time")
    expect(simColumns[6] == "00:00", "CSV Total should exclude simulator time")
    expect(simColumns[14] == "00:00", "CSV Instrument should exclude simulator time")
    expect(simColumns[15] == "02:00", "CSV FSTD should retain simulator time")
}

func testPrivacyGuardBlocksPrivateArtifactsOnly() throws {
    let blocked = PrivacyGuard.blockedTrackedPaths([
        "Sources/OpenPilotLogbookCore/Resources/airports.csv",
        "fixtures/LogTenCoreDataStore.sql",
        "exports/roster-2606.pdf",
        "OpenPilotLogbook.sqlite",
        "docs/readme.md"
    ])
    expect(blocked == [
        "OpenPilotLogbook.sqlite",
        "exports/roster-2606.pdf",
        "fixtures/LogTenCoreDataStore.sql"
    ], "privacy guard should block only private artifacts")
}

func testEncryptedBackupRoundTrip() throws {
    let temp = try makeTempDirectory()
    let source = temp.appendingPathComponent("OpenPilotLogbook.sqlite")
    let restored = temp.appendingPathComponent("Restored.sqlite")
    let plaintext = Data("synthetic database content".utf8)
    try plaintext.write(to: source)

    let backup = try EncryptedBackupService.createBackup(database: source, destinationFolder: temp, passphrase: "correct horse battery staple")
    expect(FileManager.default.fileExists(atPath: backup.encryptedBackup.path), "encrypted backup file should exist")
    expect(FileManager.default.fileExists(atPath: backup.manifest.path), "backup manifest should exist")
    let encryptedBytes = try Data(contentsOf: backup.encryptedBackup)
    let manifest = try String(contentsOf: backup.manifest)
    expect(encryptedBytes.range(of: plaintext) == nil, "encrypted payload should not contain plaintext database bytes")
    expect(manifest.contains("contains no flight rows"), "manifest should document privacy boundary")

    try EncryptedBackupService.restoreBackup(encryptedBackup: backup.encryptedBackup, destinationDatabase: restored, passphrase: "correct horse battery staple")
    let restoredBytes = try Data(contentsOf: restored)
    let sourceBytes = try Data(contentsOf: source)
    expect(restoredBytes == sourceBytes, "restored database should match source")
}

func testApplicationSupportDefaultAvoidsDesktopStorage() {
    let paths = LogbookPaths.applicationSupport
    expect(paths.workingDatabase.path.contains("/Library/Application Support/Blackbox/"), "default working database should use Application Support")
    expect(!paths.workingDatabase.path.contains("/Desktop/"), "default working database should not use Desktop")
}

func testRecencyAndDuplicates() {
    let now = utcDate(year: 2026, month: 7, day: 1)
    let recent = FlightEntry(
        id: 1,
        date: utcDate(year: 2026, month: 6, day: 1),
        departure: "EGLL",
        arrival: "EGKK",
        aircraftID: "G-TEST",
        flightNumber: "BA1",
        totalMinutes: 60,
        instrumentMinutes: 60,
        nightLandings: 1,
        totalLandings: 1
    )
    let duplicate = FlightEntry(
        id: 2,
        date: utcDate(year: 2026, month: 6, day: 1, hour: 2),
        departure: "EGLL",
        arrival: "EGKK",
        aircraftID: "G-TEST",
        flightNumber: "BA1",
        totalMinutes: 60,
        instrumentMinutes: 60,
        nightLandings: 1,
        totalLandings: 1
    )
    let simulator = FlightEntry(
        id: 4,
        date: utcDate(year: 2026, month: 6, day: 2),
        totalMinutes: 120,
        instrumentMinutes: 120,
        fstdMinutes: 120
    )
    let old = FlightEntry(id: 3, date: utcDate(year: 2024, month: 1, day: 1), totalMinutes: 500)
    let recency = LogbookAnalysis.recencySnapshot(flights: [recent, duplicate, simulator, old], now: now)
    expect(recency.hoursLast12Months == 120, "last-12-month flying hours should exclude simulator time")
    expect(recency.landingsLast90Days == 2, "90-day landings should total recent entries")
    expect(recency.nightLandingsLast90Days == 2, "90-day night landings should total recent entries")
    expect(recency.instrumentLast90Days == 120, "90-day instrument time should exclude simulator time")
    expect(LogbookAnalysis.duplicateGroups(flights: [recent, duplicate, old]).count == 1, "duplicate detector should group matching flights")
}

func testRosterPolicyIgnoresGroundDutiesAndNormalizesAirports() {
    expect(!RosterImportPolicy.shouldImportDutyToken("GDR"), "GDR should be ignored")
    expect(!RosterImportPolicy.shouldImportDutyToken("GT"), "GT should be ignored")
    expect(RosterImportPolicy.normalizedICAO("LCA") == "LCLK", "LCA should normalize to LCLK")
    expect(RosterImportPolicy.normalizedICAO("EGLL") == "EGLL", "ICAO codes should remain unchanged")
}

func testRepositoryAirportOverrideDuplicateAndComplianceGuidance() throws {
    let temp = try makeTempDirectory()
    let paths = LogbookPaths(
        backupFolder: temp,
        sourceLogTenDatabase: temp.appendingPathComponent("missing.sql"),
        workingDatabase: temp.appendingPathComponent("OpenPilotLogbook.sqlite")
    )
    let repository = LogbookRepository(paths: paths)
    try repository.createSchema(in: SQLiteConnection(path: paths.workingDatabase.path))
    try repository.saveAirportOverride(AirportOverride(identifier: "ZZZZ", name: "Synthetic Airport", latitude: 10.25, longitude: 20.5))
    let overrides = try repository.airportOverrides()
    expect(overrides.first?.identifier == "ZZZZ", "airport override should persist")

    let flight = FlightEntry(
        date: utcDate(year: 2026, month: 7, day: 1),
        departure: "ZZZZ",
        arrival: "ZZZZ",
        aircraftID: "G-DUPE",
        aircraftType: "A320",
        flightNumber: "TEST1",
        operation: "MP",
        totalMinutes: 45,
        copilotMinutes: 45
    )
    _ = try repository.save(flight)
    _ = try repository.save(flight)
    _ = try repository.save(FlightEntry(
        date: utcDate(year: 2026, month: 7, day: 2),
        aircraftID: "A320#SIM",
        aircraftType: "FFS",
        entryKind: "Simulator",
        totalMinutes: 120
    ))
    let summary = try repository.summary()
    expect(summary.totalMinutes == 90, "repository total should count flying time only")
    expect(summary.fstdMinutes == 120, "repository FSTD should retain simulator time")
    let duplicates = try repository.duplicateFlightGroups()
    expect(duplicates.count == 1, "repository duplicate groups should detect matching saved rows")

    _ = try repository.save(FlightEntry(date: utcDate(year: 2026, month: 7, day: 2), totalMinutes: 0))
    let compliance = try repository.complianceSnapshot()
    expect(compliance.issues.contains { !$0.guidance.isEmpty }, "compliance issues should include guidance")
}

func makeTempDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("BlackboxTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func utcDate(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
}
