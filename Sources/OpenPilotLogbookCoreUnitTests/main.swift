import CryptoKit
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
    try testSelfContainedSQLiteFixture()
    try testHHMMExportsAndEscaping()
    try testPrivacyGuardBlocksPrivateArtifactsOnly()
    try testEncryptedBackupRoundTrip()
    try testLegacyEncryptedBackupRestore()
    try testRestoreRejectsExecutableSchema()
    try testLegacySchemaBackupPreviewUpgrade()
    try testRestorePreviewDiscardRemovesPlaintext()
    testCSVFormulaNeutralisation()
    testDocumentDurationBounds()
    testApplicationSupportDefaultAvoidsDesktopStorage()
    testRecencyAndDuplicates()
    testRosterPolicyIgnoresGroundDutiesAndNormalizesAirports()
    try testRepositoryAirportOverrideDuplicateAndComplianceGuidance()
    try testFolderAccessStoreLifecycle()
}

func testSelfContainedSQLiteFixture() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceURL = root.appendingPathComponent("Source.sqlite")
    let copiedURL = root.appendingPathComponent("Copied.sqlite")

    do {
        let source = try SQLiteConnection(path: sourceURL.path)
        try source.execute("CREATE TABLE synthetic_flights(id INTEGER PRIMARY KEY, flight_number TEXT NOT NULL)")
        try source.execute("INSERT INTO synthetic_flights VALUES(1, 'SYN-WAL-1')")
        try source.finalizeAsSelfContainedDatabase()
    }

    let fileManager = FileManager.default
    expect(!fileManager.fileExists(atPath: sourceURL.path + "-wal"), "standalone fixture should not retain a WAL")
    try fileManager.copyItem(at: sourceURL, to: copiedURL)

    let copied = try SQLiteConnection(path: copiedURL.path, readOnly: true)
    let row = try copied.rows("SELECT id, flight_number FROM synthetic_flights").first
    expect(row?["id"]?.int == 1, "copied standalone fixture should retain its row")
    expect(row?["flight_number"]?.string == "SYN-WAL-1", "copied standalone fixture should retain its values")
    let integrity = try copied.integrityCheck().lowercased()
    expect(integrity == "ok", "copied standalone fixture should pass integrity_check")
}

func testFolderAccessStoreLifecycle() throws {
    let suiteName = "Blackbox.FolderAccessStoreTests.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        expect(false, "isolated defaults suite should be available")
        return
    }
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let root = try makeTempDirectory()
    let folder = root.appendingPathComponent("Exports", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let store = FolderAccessStore(defaults: defaults, keyPrefix: "Blackbox.test.folder", mode: .standard)

    expect(store.resolve(.exports) == .missing, "an unset folder bookmark should be missing")
    try store.remember(folder, for: .exports)
    guard case .available(let resolved) = store.resolve(.exports) else {
        expect(false, "a remembered folder should resolve")
        return
    }
    expect(resolved.standardizedFileURL == folder.standardizedFileURL, "the resolved folder should match the selected destination")

    try FileManager.default.removeItem(at: folder)
    expect(store.resolve(.exports) == .stale, "a deleted bookmarked folder should require reselection")
    store.forget(.exports)
    expect(store.resolve(.exports) == .missing, "forget should clear a saved folder bookmark")
    try? FileManager.default.removeItem(at: root)
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
    expect(encryptedBytes.starts(with: Data("BLACKBOX-ENCRYPTED-BACKUP".utf8)), "new encrypted backups should use the versioned envelope")
    expect(manifest.contains("\"version\": 2"), "backup manifest should identify the hardened format")
    expect(manifest.contains("PBKDF2-HMAC-SHA256"), "backup manifest should identify the password KDF")
    expect(manifest.contains("contains no flight rows"), "manifest should document privacy boundary")

    try EncryptedBackupService.restoreBackup(encryptedBackup: backup.encryptedBackup, destinationDatabase: restored, passphrase: "correct horse battery staple")
    let restoredBytes = try Data(contentsOf: restored)
    let sourceBytes = try Data(contentsOf: source)
    expect(restoredBytes == sourceBytes, "restored database should match source")
}

func testLegacyEncryptedBackupRestore() throws {
    let temp = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: temp) }
    let legacyURL = temp.appendingPathComponent("Legacy.blackboxbackup")
    let restoredURL = temp.appendingPathComponent("Legacy-Restored.sqlite")
    let passphrase = "legacy-compatible-passphrase"
    let plaintext = Data("synthetic legacy backup".utf8)
    let digest = SHA256.hash(data: Data(passphrase.utf8))
    let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: Data(digest)))
    try sealed.combined!.write(to: legacyURL)

    try EncryptedBackupService.restoreBackup(encryptedBackup: legacyURL, destinationDatabase: restoredURL, passphrase: passphrase)
    let restored = try Data(contentsOf: restoredURL)
    expect(restored == plaintext, "version 1 encrypted backups should remain restorable")
}

func testRestoreRejectsExecutableSchema() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
    let targetRoot = root.appendingPathComponent("Target", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
    let sourcePaths = testPaths(sourceRoot)
    let targetPaths = testPaths(targetRoot)
    let source = LogbookRepository(paths: sourcePaths)
    let target = LogbookRepository(paths: targetPaths)
    try source.bootstrapIfNeeded()
    try target.bootstrapIfNeeded()
    let sourceDatabase = try SQLiteConnection(path: sourcePaths.workingDatabase.path)
    try sourceDatabase.execute("CREATE TRIGGER malicious_restore_trigger AFTER INSERT ON flights BEGIN DELETE FROM flights; END")
    let backup = try EncryptedBackupService.createBackup(
        database: sourcePaths.workingDatabase,
        destinationFolder: root.appendingPathComponent("Encrypted", isDirectory: true),
        passphrase: "synthetic-schema-attack"
    )
    var rejected = false
    do {
        _ = try target.prepareRestore(from: backup.encryptedBackup, passphrase: "synthetic-schema-attack")
    } catch {
        rejected = true
    }
    expect(rejected, "restore preview should reject SQLite triggers before activation")
}

func testLegacySchemaBackupPreviewUpgrade() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let sourceRoot = root.appendingPathComponent("Legacy", isDirectory: true)
    let targetRoot = root.appendingPathComponent("Target", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: targetRoot, withIntermediateDirectories: true)
    let sourceURL = sourceRoot.appendingPathComponent("Legacy.sqlite")
    let legacy = try SQLiteConnection(path: sourceURL.path)
    try legacy.execute("CREATE TABLE flights (id INTEGER PRIMARY KEY AUTOINCREMENT, date TEXT NOT NULL, total_minutes INTEGER NOT NULL DEFAULT 0, locked INTEGER NOT NULL DEFAULT 0)")
    try legacy.execute("INSERT INTO flights(date, total_minutes, locked) VALUES('2026-01-01T00:00:00Z', 45, 1)")
    try legacy.execute("PRAGMA user_version = 1")
    try legacy.finalizeAsSelfContainedDatabase()
    let backup = try EncryptedBackupService.createBackup(
        database: sourceURL,
        destinationFolder: root.appendingPathComponent("Encrypted", isDirectory: true),
        passphrase: "synthetic-legacy-schema"
    )
    let target = LogbookRepository(paths: testPaths(targetRoot))
    try target.bootstrapIfNeeded()
    let plan = try target.prepareRestore(from: backup.encryptedBackup, passphrase: "synthetic-legacy-schema")
    expect(plan.schemaVersion == LogbookRepository.currentSchemaVersion, "legacy backup preview should migrate to the current schema")
    expect(plan.restoredFlightCount == 1, "legacy backup preview should retain its flight")
    target.discardRestorePlan(plan)
}

func testRestorePreviewDiscardRemovesPlaintext() throws {
    let root = try makeTempDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repositoryRoot = root.appendingPathComponent("Repository", isDirectory: true)
    try FileManager.default.createDirectory(at: repositoryRoot, withIntermediateDirectories: true)
    let paths = testPaths(repositoryRoot)
    let repository = LogbookRepository(paths: paths)
    try repository.bootstrapIfNeeded()
    let backup = try EncryptedBackupService.createBackup(
        database: paths.workingDatabase,
        destinationFolder: root.appendingPathComponent("Encrypted", isDirectory: true),
        passphrase: "synthetic-preview-discard"
    )
    let plan = try repository.prepareRestore(from: backup.encryptedBackup, passphrase: "synthetic-preview-discard")
    let artifactRoot = plan.inspectedDatabaseURL.deletingLastPathComponent()
    expect(FileManager.default.fileExists(atPath: plan.inspectedDatabaseURL.path), "restore preview should create a private inspected database")
    repository.discardRestorePlan(plan)
    expect(!FileManager.default.fileExists(atPath: artifactRoot.path), "cancelling restore should remove its decrypted preview")
}

func testCSVFormulaNeutralisation() {
    for value in ["=1+1", "+SUM(A1:A2)", "-1+2", "@SUM(A1:A2)", "\t=HYPERLINK(\"https://example.invalid\")"] {
        expect(LogbookFormatters.csvEscape(value).contains("'"), "formula-like CSV text should be neutralised")
    }
    expect(LogbookFormatters.csvEscape("Synthetic note") == "Synthetic note", "ordinary CSV text should remain unchanged")
}

func testDocumentDurationBounds() {
    expect(TextFlightParser.parseDuration("12:34") == 754, "valid HH:MM durations should parse")
    expect(TextFlightParser.parseDuration("1:60") == nil, "invalid minute components should be rejected")
    expect(TextFlightParser.parseDuration("9223372036854775807:00") == nil, "oversized duration input should not overflow")
}

func testPaths(_ root: URL) -> LogbookPaths {
    LogbookPaths(
        backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
        sourceLogTenDatabase: root.appendingPathComponent("No LogTen Source.sqlite"),
        workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
    )
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
    try repository.bootstrapIfNeeded()
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
    _ = try repository.saveDraft(flight)
    _ = try repository.saveDraft(flight)
    _ = try repository.saveDraft(FlightEntry(
        date: utcDate(year: 2026, month: 7, day: 2),
        aircraftID: "A320#SIM",
        aircraftType: "FFS",
        entryKind: "Simulator",
        totalMinutes: 120,
        fstdMinutes: 120
    ))
    let summary = try repository.summary()
    expect(summary.totalMinutes == 90, "repository total should count flying time only")
    expect(summary.fstdMinutes == 120, "repository FSTD should retain simulator time")
    let duplicates = try repository.duplicateFlightGroups()
    expect(duplicates.count == 1, "repository duplicate groups should detect matching saved rows")

    var incomplete = FlightEntry(date: utcDate(year: 2026, month: 7, day: 2), totalMinutes: 0)
    let incompleteID = try repository.saveDraft(incomplete)
    incomplete.id = incompleteID
    _ = try repository.finalise(incomplete, acknowledgeWarnings: true)
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
