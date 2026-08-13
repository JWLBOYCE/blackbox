import Foundation
import Testing
@testable import OpenPilotLogbookCore

@Suite("Blackbox reliability")
struct ReliabilityTests {
    @Test("Draft round trip preserves every pilot-entered field")
    func draftRoundTripPreservesEveryPilotEnteredField() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = FlightEntry(
            sourcePK: 42,
            date: fixedDate(),
            departure: "ZZAA", arrival: "ZZBB", route: "DCT TEST", aircraftID: "G-SYNTH", aircraftType: "A320",
            flightNumber: "SYN42", operation: "SP", entryKind: "Simulator", pilotFunction: "PIC",
            totalMinutes: 97, picMinutes: 11, picDayMinutes: 7, picNightMinutes: 4, picusMinutes: 13,
            picusDayMinutes: 8, picusNightMinutes: 5, copilotMinutes: 17, copilotDayMinutes: 9, copilotNightMinutes: 8,
            dualMinutes: 19, instructorMinutes: 23, nightMinutes: 29, instrumentMinutes: 0, crossCountryMinutes: 0,
            fstdMinutes: 31, pilotFlying: true, dayTakeoffs: 2, nightTakeoffs: 3, totalTakeoffs: 9,
            dayLandings: 4, nightLandings: 5, totalLandings: 12, passengerCount: 6, distanceNM: 123.45,
            crewNames: "Alex Example | Sam Synthetic", crewRoles: "Alex Example=Captain | Sam Synthetic=Observer",
            departureLatitude: 1.25, departureLongitude: -2.5, arrivalLatitude: 3.75, arrivalLongitude: -4.5,
            remarks: "User-entered remarks", signatureName: "Synthetic Signer", signatureReference: "REF-42",
            recordState: .draft
        )
        let id = try repository.saveDraft(original)
        let loaded = try repository.flight(id: id)
        let saved = try #require(loaded)
        var expected = original
        expected.id = id
        #expect(saved == expected, "Persistence must not normalise, infer, clear, or allocate any entered field")
        #expect(try repository.revisions(for: id).first?.action == "created")
    }

    @Test("Finalise, amend, Trash, and Restore use explicit states")
    func finaliseAmendTrashAndRestoreTransitions() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let draftID = try repository.saveDraft(validFlight())
        let loadedDraft = try repository.flight(id: draftID)
        let draft = try #require(loadedDraft)
        _ = try repository.finalise(draft, acknowledgeWarnings: true)
        let loadedFinalised = try repository.flight(id: draftID)
        let finalised = try #require(loadedFinalised)
        #expect(finalised.recordState == .finalised)
        var immutableRejected = false
        do { _ = try repository.saveDraft(finalised) } catch { immutableRejected = true }
        #expect(immutableRejected)

        let amendmentID = try repository.beginAmendment(of: draftID)
        let loadedAmendment = try repository.flight(id: amendmentID)
        var amendment = try #require(loadedAmendment)
        amendment.remarks = "Corrected synthetic note"
        _ = try repository.saveDraft(amendment)
        let reloadedAmendment = try repository.flight(id: amendmentID)
        amendment = try #require(reloadedAmendment)
        _ = try repository.finaliseAmendment(amendment, acknowledgeWarnings: true)
        #expect(try repository.flight(id: draftID)?.recordState == .superseded)
        #expect(try repository.flight(id: draftID)?.supersededByFlightID == amendmentID)
        #expect(try repository.flight(id: amendmentID)?.recordState == .finalised)
        #expect(try repository.flight(id: amendmentID)?.amendsFlightID == draftID)

        let trashID = try repository.saveDraft(FlightEntry(date: fixedDate(), remarks: "Recoverable"))
        try repository.moveToTrash(id: trashID)
        #expect(try repository.flight(id: trashID)?.recordState == .trashed)
        try repository.restoreFromTrash(id: trashID)
        #expect(try repository.flight(id: trashID)?.recordState == .draft)
        #expect(Array(try repository.revisions(for: trashID).map(\.action).prefix(2)) == ["restored", "trashed"])
    }

    @Test("Migration preserves legacy values and creates a verified backup")
    func migrationPreservesLegacyFieldsAndCreatesVerifiedBackup() throws {
        var phase = "create fixture"
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            let paths = LogbookPaths(backupFolder: root.appendingPathComponent("Backups"), sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"), workingDatabase: root.appendingPathComponent("Legacy.sqlite"))
            do {
                let db = try SQLiteConnection(path: paths.workingDatabase.path)
                try db.execute("CREATE TABLE flights(id INTEGER PRIMARY KEY, locked INTEGER NOT NULL, total_minutes INTEGER NOT NULL, remarks TEXT NOT NULL, modified_at TEXT NOT NULL)")
                try db.execute("INSERT INTO flights VALUES(1, 1, 77, 'Do not change', '2026-01-01T00:00:00Z')")
                try db.execute("PRAGMA user_version = 0")
            }
            let repository = LogbookRepository(paths: paths)
            phase = "read preflight"
            let preflight = try repository.upgradePreflight()
            #expect(preflight.requiresUpgrade)
            phase = "backup and upgrade"
            let backup = try repository.backUpAndUpgrade(using: preflight)
            #expect(FileManager.default.fileExists(atPath: backup.path))
            #expect(try repository.schemaVersion() == LogbookRepository.currentSchemaVersion)
            phase = "read migrated database"
            let migrated = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            let migratedRows = try migrated.rows("SELECT date, locked, total_minutes, remarks, modified_at, record_state FROM flights WHERE id = 1")
            let row = try #require(migratedRows.first)
            #expect(row["date"]?.string == "", "Migration must not invent a missing legacy date")
            #expect(row["locked"]?.int == 1)
            #expect(row["total_minutes"]?.int == 77)
            #expect(row["remarks"]?.string == "Do not change")
            #expect(row["modified_at"]?.string == "2026-01-01T00:00:00Z")
            #expect(row["record_state"]?.string == "finalised")
            #expect(try migrated.integrityCheck().lowercased() == "ok")

            let expectedFlightColumns = Set([
                "id", "source_pk", "date", "departure", "arrival", "route", "aircraft_id", "aircraft_type",
                "flight_number", "operation", "entry_kind", "pilot_function", "total_minutes", "pic_minutes",
                "pic_day_minutes", "pic_night_minutes", "picus_minutes", "picus_day_minutes", "picus_night_minutes",
                "copilot_minutes", "copilot_day_minutes", "copilot_night_minutes", "dual_minutes", "instructor_minutes",
                "night_minutes", "instrument_minutes", "cross_country_minutes", "fstd_minutes", "pilot_flying",
                "day_takeoffs", "night_takeoffs", "total_takeoffs", "day_landings", "night_landings",
                "total_landings", "passenger_count", "distance_nm", "crew_names", "crew_roles", "departure_lat",
                "departure_lon", "arrival_lat", "arrival_lon", "remarks", "signature_name", "signature_reference",
                "locked", "record_state", "amends_flight_id", "superseded_by_flight_id", "modified_at"
            ])
            let migratedColumns = Set(try migrated.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string })
            #expect(migratedColumns == expectedFlightColumns)
            let expectedTables = Set(["flights", "places", "people", "settings", "flight_revisions", "operation_batches"])
            let migratedTables = Set(try migrated.rows("SELECT name FROM sqlite_master WHERE type = 'table'").compactMap { $0["name"]?.string })
            #expect(expectedTables.isSubset(of: migratedTables))

            let firstLegacyRead = try #require(try repository.flight(id: 1))
            let secondLegacyRead = try #require(try repository.flight(id: 1))
            #expect(firstLegacyRead == secondLegacyRead)
            #expect(firstLegacyRead.date == Date(timeIntervalSince1970: 0))

            phase = "exercise current persistence after migration"
            let draftID = try repository.saveDraft(validFlight())
            let draft = try #require(try repository.flight(id: draftID))
            _ = try repository.finalise(draft, acknowledgeWarnings: true)
            #expect(try repository.flight(id: draftID)?.recordState == .finalised)

            let importPlan = try repository.prepareDocumentImport(
                candidates: [FlightEntry(date: fixedDate(), aircraftID: "G-MIGR", totalMinutes: 21, remarks: "Post-migration import")],
                sourceURL: root.appendingPathComponent("Synthetic Migration.pdf")
            )
            phase = "hold sealed import plan across a clock-second boundary"
            Thread.sleep(forTimeInterval: 1.1)
            phase = "apply sealed import plan"
            _ = try repository.applyImport(importPlan)
            #expect(try repository.flights(query: FlightQuery(text: "Post-migration import", recordStates: [.draft])).count == 1)
        } catch {
            Issue.record("Migration phase '\(phase)' failed: \(error)")
            throw error
        }
    }

    @Test("Future schemas are rejected before any database byte is changed")
    func futureSchemaIsRejectedReadOnly() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups"),
            sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"),
            workingDatabase: root.appendingPathComponent("Future.sqlite")
        )
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()
        _ = try repository.saveDraft(validFlight())
        do {
            let database = try SQLiteConnection(path: paths.workingDatabase.path)
            try database.execute("PRAGMA user_version = \(LogbookRepository.currentSchemaVersion + 1)")
            try database.checkpointWAL()
        }

        let encryptedFolder = root.appendingPathComponent("Encrypted", isDirectory: true)
        let encrypted = try EncryptedBackupService.createBackup(
            database: paths.workingDatabase,
            destinationFolder: encryptedFolder,
            passphrase: "Synthetic-Future-Schema"
        )
        let bytesBefore = try Data(contentsOf: paths.workingDatabase)
        let versionBefore = try repository.schemaVersion()
        #expect(versionBefore == LogbookRepository.currentSchemaVersion + 1)

        #expect(throws: LogbookRepositoryError.self) { try repository.bootstrapIfNeeded() }
        #expect(throws: LogbookRepositoryError.self) { try repository.bootstrapIfNeeded(allowUpgrade: true) }
        let preflight = try repository.upgradePreflight()
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.backUpAndUpgrade(using: preflight) }

        let (restoreTarget, restoreRoot) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: restoreRoot) }
        #expect(throws: LogbookRepositoryError.self) {
            _ = try restoreTarget.prepareRestore(from: encrypted.encryptedBackup, passphrase: "Synthetic-Future-Schema")
        }

        #expect(try Data(contentsOf: paths.workingDatabase) == bytesBefore)
        #expect(try repository.schemaVersion() == versionBefore)
        #expect(!FileManager.default.fileExists(atPath: paths.backupFolder.path))
    }

    @Test("Place visits include identifiers absent from places")
    func placeVisitsIncludeCodesMissingFromPlacesTable() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try repository.saveDraft(FlightEntry(date: fixedDate(), departure: "NONE", arrival: "MISS", totalMinutes: 1))
        #expect(Set(try repository.placeVisitSummaries().map(\.identifier)) == ["NONE", "MISS"])
    }

    @Test("Active analytics exclude superseded originals and trashed drafts")
    func activeAnalyticsExcludeHistoricalRecords() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        let originalID = try repository.saveDraft(FlightEntry(
            date: fixedDate(), departure: "OLD1", arrival: "OLD2",
            aircraftID: "G-OLD", aircraftType: "OLD-TYPE", pilotFunction: "Co-pilot",
            totalMinutes: 60, copilotMinutes: 60, totalLandings: 1,
            crewNames: "Original Crew"
        ))
        let original = try #require(try repository.flight(id: originalID))
        _ = try repository.finalise(original, acknowledgeWarnings: true)

        let amendmentID = try repository.beginAmendment(of: originalID)
        var amendment = try #require(try repository.flight(id: amendmentID))
        amendment.departure = "LIVE1"
        amendment.arrival = "LIVE2"
        amendment.aircraftID = "G-ACTIVE"
        amendment.aircraftType = "ACTIVE-TYPE"
        amendment.totalMinutes = 70
        amendment.copilotMinutes = 70
        amendment.totalLandings = 2
        amendment.crewNames = "Active Crew"
        _ = try repository.saveDraft(amendment)
        amendment = try #require(try repository.flight(id: amendmentID))
        _ = try repository.finaliseAmendment(amendment, acknowledgeWarnings: true)

        let trashID = try repository.saveDraft(FlightEntry(
            date: fixedDate(), departure: "BIN1", arrival: "BIN2",
            aircraftID: "G-TRASH", aircraftType: "TRASH-TYPE",
            totalMinutes: 90, totalLandings: 3, crewNames: "Trash Crew"
        ))
        try repository.moveToTrash(id: trashID)

        let summary = try repository.summary()
        #expect(summary.flightCount == 1)
        #expect(summary.totalMinutes == 70)
        #expect(summary.landings == 2)

        let aircraft = try repository.aircraftSummaries()
        #expect(aircraft == [AircraftSummary(aircraftID: "G-ACTIVE", aircraftType: "ACTIVE-TYPE", flightCount: 1, totalMinutes: 70, landings: 2)])

        let types = try repository.typeSummaries()
        #expect(types == [TypeSummary(aircraftType: "ACTIVE-TYPE", flightCount: 1, totalMinutes: 70, copilotDayMinutes: 0, copilotNightMinutes: 0, distanceNM: 0)])

        let people = try repository.personSummaries()
        #expect(people == [PersonSummary(name: "Active Crew", flightCount: 1, totalMinutes: 70)])

        let visits = Dictionary(uniqueKeysWithValues: try repository.placeVisitSummaries().map { ($0.identifier, ($0.departures, $0.arrivals)) })
        #expect(visits.count == 2)
        #expect(visits["LIVE1"]?.0 == 1)
        #expect(visits["LIVE1"]?.1 == 0)
        #expect(visits["LIVE2"]?.0 == 0)
        #expect(visits["LIVE2"]?.1 == 1)

        let suggestions = try repository.suggestions()
        #expect(suggestions.aircraftIDs == ["G-ACTIVE"])
        #expect(suggestions.aircraftTypes == ["ACTIVE-TYPE"])
        #expect(suggestions.people == ["Active Crew"])
    }

    @Test("CAA-format exports exclude drafts")
    func reportExporterExcludesDrafts() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let finalised = validFlight(recordState: .finalised)
        let draft = FlightEntry(date: fixedDate(), departure: "DRAF", arrival: "TEST", remarks: "DRAFT_SENTINEL", recordState: .draft)
        let result = try ReportExporter.exportCAAResources(flights: [finalised, draft], summary: LogbookSummary(), to: root)
        let csv = try String(contentsOf: result.csv, encoding: .utf8)
        #expect(!csv.contains("DRAFT_SENTINEL"))
        #expect(csv.contains("EGLL"))
    }

    @Test("Comparison cannot default to success")
    func comparisonStateCannotDefaultToSuccess() {
        let state = LogTenComparisonState.idle
        if case .loaded = state { Issue.record("Idle comparison must not render as a loaded match") }
    }

    @Test("Migration failures preserve the original legacy database", arguments: [MigrationFailurePoint.beforeTransaction, .duringTransaction, .afterTransaction])
    func migrationFailureRollsBack(_ failurePoint: MigrationFailurePoint) throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LogbookPaths(backupFolder: root.appendingPathComponent("Backups"), sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"), workingDatabase: root.appendingPathComponent("Legacy.sqlite"))
        do {
            let db = try SQLiteConnection(path: paths.workingDatabase.path)
            try db.execute("CREATE TABLE flights(id INTEGER PRIMARY KEY, locked INTEGER NOT NULL, total_minutes INTEGER NOT NULL, remarks TEXT NOT NULL, modified_at TEXT NOT NULL)")
            try db.execute("INSERT INTO flights VALUES(1, 0, 88, 'Rollback sentinel', '2025-12-31T00:00:00Z')")
            try db.execute("PRAGMA user_version = 0")
        }
        let repository = LogbookRepository(paths: paths)
        let preflight = try repository.upgradePreflight()
        var didFail = false
        do { _ = try repository.backUpAndUpgrade(using: preflight, injectingFailureAt: failurePoint) }
        catch { didFail = true }
        #expect(didFail)
        let restored = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        #expect(try restored.rows("PRAGMA user_version").first?.values.first?.int == 0)
        #expect(try restored.rows("SELECT total_minutes, remarks FROM flights").first?["total_minutes"]?.int == 88)
        #expect(try restored.rows("SELECT total_minutes, remarks FROM flights").first?["remarks"]?.string == "Rollback sentinel")
        #expect(!(try restored.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string }).contains("record_state"))
        #expect(try restored.integrityCheck().lowercased() == "ok")
    }

    @Test("Shared FlightQuery combines range, aircraft, aircraft type, role, operation, entry type, state, and text")
    func sharedFlightQueryFiltersAllDimensions() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try repository.saveDraft(FlightEntry(date: fixedDate(), departure: "EGLL", arrival: "EGKK", aircraftID: "G-MATCH", aircraftType: "A320", operation: "MP", entryKind: "Flight", pilotFunction: "PIC", totalMinutes: 60, crewNames: "Query Person", remarks: "QUERY_SENTINEL"))
        _ = try repository.saveDraft(FlightEntry(date: fixedDate(), departure: "EGLL", arrival: "EGKK", aircraftID: "G-OTHER", aircraftType: "A320", operation: "MP", entryKind: "Flight", pilotFunction: "PIC", totalMinutes: 60, remarks: "QUERY_SENTINEL"))
        let query = FlightQuery(
            text: "Query Person",
            startDate: fixedDate().addingTimeInterval(-60),
            endDate: fixedDate().addingTimeInterval(60),
            aircraftIDs: ["G-MATCH"],
            aircraftTypes: ["A320"],
            pilotFunctions: ["PIC"],
            operations: ["MP"],
            entryKinds: ["Flight"],
            recordStates: [.draft]
        )
        let matches = try repository.flights(query: query)
        #expect(matches.count == 1)
        #expect(matches.first?.aircraftID == "G-MATCH")
    }

    @Test("Synthetic 3,000-flight query remains usable")
    func threeThousandFlightPerformance() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LogbookPaths(backupFolder: root.appendingPathComponent("Backups"), sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"), workingDatabase: root.appendingPathComponent("Blackbox.sqlite"))
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        let date = LogbookFormatters.isoFormatter.string(from: fixedDate())
        try db.transaction {
            for index in 0..<3_100 {
                try db.execute("INSERT INTO flights(date, departure, arrival, aircraft_id, aircraft_type, flight_number, operation, entry_kind, pilot_function, total_minutes, pic_minutes, pic_day_minutes, pic_night_minutes, picus_minutes, picus_day_minutes, picus_night_minutes, copilot_minutes, copilot_day_minutes, copilot_night_minutes, dual_minutes, instructor_minutes, night_minutes, instrument_minutes, cross_country_minutes, fstd_minutes, pilot_flying, day_takeoffs, night_takeoffs, total_takeoffs, day_landings, night_landings, total_landings, passenger_count, distance_nm, crew_names, crew_roles, remarks, signature_name, signature_reference, locked, record_state, modified_at) VALUES(?, 'EGLL', 'EGKK', ?, 'A320', '', 'MP', 'Flight', 'Co-pilot', 60, 0, 0, 0, 0, 0, 0, 60, 60, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 0, 180, '', '', ?, '', '', 0, 'draft', ?)", values: [.text(date), .text("G-\(index % 10)"), .text("SYNTH-\(index)"), .text(date)])
            }
        }
        let start = ContinuousClock.now
        let result = try repository.flights(query: FlightQuery(text: "SYNTH-30", aircraftIDs: ["G-0"]))
        let elapsed = ContinuousClock.now - start
        #expect(!result.isEmpty)
        #expect(elapsed < .seconds(2))
    }

    @Test("Fixed 3,100-flight Release performance gates cover import, History, Analysis, and Map")
    func fixedFixtureReleasePerformanceGates() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups"),
            sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"),
            workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
        )
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        let date = LogbookFormatters.isoFormatter.string(from: fixedDate())
        try db.transaction {
            for index in 0..<3_100 {
                try db.execute("""
                INSERT INTO flights(
                    date, departure, arrival, aircraft_id, aircraft_type, flight_number,
                    operation, entry_kind, pilot_function, total_minutes, copilot_minutes,
                    day_landings, total_landings, distance_nm, departure_lat, departure_lon,
                    arrival_lat, arrival_lon, remarks, locked, record_state, modified_at
                ) VALUES(?, 'EGLL', 'EGKK', ?, 'A320', ?, 'MP', 'Flight', 'Co-pilot',
                         60, 60, 1, 1, 180, 51.4700, -0.4543, 51.1481, -0.1903,
                         ?, 0, 'draft', ?)
                """, values: [
                    .text(date), .text("G-\(index % 20)"), .text("PERF-\(index)"),
                    .text("Fixed performance fixture \(index)"), .text(date)
                ])
                let flightID = db.lastInsertRowID()
                try db.execute("""
                INSERT INTO flight_revisions(flight_id, action, origin, before_json, after_json, created_at)
                VALUES(?, 'created', 'performance_fixture', NULL, '{}', ?)
                """, values: [.integer(flightID), .text(date)])
            }
        }

        let historyStart = ContinuousClock.now
        let history = try repository.history(query: HistoryQuery(text: "performance_fixture"))
        let historyElapsed = ContinuousClock.now - historyStart
        #expect(history.count == 3_100)
        #expect(historyElapsed < performanceThreshold(debug: 8, release: 2))

        let analysisFlights = try repository.flights(query: FlightQuery(recordStates: [.draft]))
        let analysisStart = ContinuousClock.now
        let recency = LogbookAnalysis.recencySnapshot(flights: analysisFlights, now: fixedDate().addingTimeInterval(86_400))
        let duplicates = LogbookAnalysis.duplicateGroups(flights: analysisFlights)
        let analysisElapsed = ContinuousClock.now - analysisStart
        #expect(recency.hoursLast90Days == 3_100 * 60)
        #expect(duplicates.isEmpty)
        #expect(analysisElapsed < performanceThreshold(debug: 8, release: 2))

        let mapStart = ContinuousClock.now
        let routes = try repository.mapRoutes(limit: 3_100)
        let mapElapsed = ContinuousClock.now - mapStart
        #expect(routes.count == 3_100)
        #expect(mapElapsed < performanceThreshold(debug: 8, release: 2))

        let importCandidate = FlightEntry(
            date: fixedDate(), departure: "EGLL", arrival: "EGKK", aircraftID: "G-IMPORT",
            aircraftType: "A320", operation: "MP", entryKind: "Flight",
            pilotFunction: "Co-pilot", totalMinutes: 45, copilotMinutes: 45,
            remarks: "Fixed performance import"
        )
        let importSource = root.appendingPathComponent("Performance Import.pdf")
        let planningStart = ContinuousClock.now
        let plan = try repository.prepareDocumentImport(candidates: [importCandidate], sourceURL: importSource)
        let planningElapsed = ContinuousClock.now - planningStart
        #expect(plan.additions.count == 1)
        #expect(planningElapsed < performanceThreshold(debug: 30, release: 8))

        let applicationStart = ContinuousClock.now
        _ = try repository.applyImport(plan)
        let applicationElapsed = ContinuousClock.now - applicationStart
        let importedMatches = try repository.flights(query: FlightQuery(text: "Fixed performance import", recordStates: [.draft]))
        #expect(importedMatches.count == 1)
        #expect(applicationElapsed < performanceThreshold(debug: 45, release: 15))
    }

    @Test("Conservative role suggestions never overwrite entered roles")
    func roleSuggestionsAreConservative() {
        let eligible = FlightEntry(date: fixedDate(), departure: "EGLL", arrival: "EGKK", aircraftID: "G-TEST", pilotFunction: "Co-pilot", totalMinutes: 60)
        let role = FlightSuggestionEngine.suggestions(for: eligible).first { $0.field == .copilotMinutes }
        #expect(role?.numericValue == 60)
        #expect(role?.method.contains("Exact") == true)
        var entered = eligible
        entered.picMinutes = 1
        let unavailable = FlightSuggestionEngine.suggestions(for: entered).first { $0.title == "Role allocation" }
        #expect(unavailable?.isActionable == false)
        #expect(unavailable?.unavailableReason?.contains("non-zero") == true)
    }

    @Test("Selected suggestion batches apply only selected actionable suggestions")
    func selectedSuggestionBatch() {
        let flight = FlightEntry(date: fixedDate(), departure: "EGLL", arrival: "EGKK", aircraftID: "G-TEST", pilotFunction: "Co-pilot", totalMinutes: 60, dayTakeoffs: 1, totalTakeoffs: 0)
        let suggestions = FlightSuggestionEngine.suggestions(for: flight)
        let takeoff = suggestions.first { $0.field == .totalTakeoffs }!
        let role = suggestions.first { $0.field == .copilotMinutes }!
        let batch = SuggestionBatch(suggestions: suggestions, selectedSuggestionIDs: [takeoff.id, role.id])
        let result = FlightSuggestionEngine.applying(batch, to: flight)
        #expect(result.totalTakeoffs == 1)
        #expect(result.copilotMinutes == 60)
        #expect(result.distanceNM == 0)
    }

    @Test("Validation blocks structural errors and retains warnings")
    func structuralValidation() {
        let invalid = FlightEntry(id: 9, date: fixedDate(), aircraftID: "G-TEST", totalMinutes: -1, picMinutes: -2, dayLandings: -1, departureLatitude: 91, amendsFlightID: 9)
        let report = FlightSuggestionEngine.validationReport(for: invalid)
        #expect(report.hasErrors)
        #expect(report.issues.contains { $0.field == "Total time" && $0.severity == .error })
        #expect(report.issues.contains { $0.field == "Departure latitude" && $0.severity == .error })
        #expect(report.issues.contains { $0.field == "Amendment" && $0.severity == .error })
    }

    @Test("Trash, revision diff, and bulk Restore remain recoverable")
    func historyAndBulkRestore() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try repository.saveDraft(FlightEntry(date: fixedDate(), aircraftID: "G-A", remarks: "First"))
        let second = try repository.saveDraft(FlightEntry(date: fixedDate(), aircraftID: "G-B", remarks: "Second"))
        try repository.moveToTrash(id: first)
        try repository.moveToTrash(id: second)
        #expect(Set(try repository.trash().map(\.id)) == [first, second])
        try repository.restoreFromTrash(ids: [first, second])
        #expect(try repository.trash().isEmpty)
        let revision = try #require(try repository.history(query: HistoryQuery(flightID: first)).first)
        #expect(!repository.revisionDiffs(for: revision).isEmpty)
    }

    @Test("Schema 2 operation metadata migration preserves flight facts")
    func operationMetadataMigrationPreservesFacts() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LogbookPaths(backupFolder: root.appendingPathComponent("Backups"), sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"), workingDatabase: root.appendingPathComponent("Schema2.sqlite"))
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()
        let id = try repository.saveDraft(FlightEntry(date: fixedDate(), aircraftID: "G-BYTES", totalMinutes: 47, remarks: "Byte sentinel"))
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try db.execute("PRAGMA user_version = 2")
        let loadedBefore = try repository.flight(id: id)
        let before = try #require(loadedBefore)
        let preflight = try repository.upgradePreflight()
        _ = try repository.backUpAndUpgrade(using: preflight)
        #expect(try repository.flight(id: id) == before)
        #expect(try repository.schemaVersion() == LogbookRepository.currentSchemaVersion)
    }

    @Test("Standard folder bookmarks resolve, become stale, and can be forgotten")
    func standardFolderBookmarkLifecycle() throws {
        let suiteName = "Blackbox.FolderAccessStore.Tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let folder = try tempDirectory()
        let store = FolderAccessStore(defaults: defaults, keyPrefix: "test.bookmark", mode: .standard)

        #expect(store.resolve(.exports) == .missing)
        try store.remember(folder, for: .exports)
        switch store.resolve(.exports) {
        case .available(let resolved):
            #expect(resolved.standardizedFileURL == folder.standardizedFileURL)
        case .missing, .stale:
            Issue.record("A fresh standard bookmark should resolve to its directory")
        }

        try FileManager.default.removeItem(at: folder)
        #expect(store.resolve(.exports) == .stale)
        store.forget(.exports)
        #expect(store.resolve(.exports) == .missing)
    }

    @Test("Amendment relationships are validated against the database")
    func amendmentRelationshipsAreDatabaseBacked() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalID = try repository.saveDraft(validFlight())
        let loadedOriginal = try repository.flight(id: originalID)
        _ = try repository.finalise(try #require(loadedOriginal), acknowledgeWarnings: true)
        let amendmentID = try repository.beginAmendment(of: originalID)
        #expect(throws: (any Error).self) { try repository.beginAmendment(of: originalID) }

        let db = try SQLiteConnection(path: repository.paths.workingDatabase.path)
        try db.execute("UPDATE flights SET record_state = 'superseded', superseded_by_flight_id = 999 WHERE id = ?", values: [.integer(originalID)])
        let loadedAmendment = try repository.flight(id: amendmentID)
        let amendment = try #require(loadedAmendment)
        let report = try repository.validationReport(for: amendment)
        #expect(report.issues.contains { $0.field == "Amendment" && $0.severity == .error })
        #expect(throws: (any Error).self) {
            try repository.finaliseAmendment(amendment, acknowledgeWarnings: true)
        }
        let unchangedAmendment = try repository.flight(id: amendmentID)
        #expect(unchangedAmendment?.recordState == .draft)
    }

    @Test("Schema 4 preflight rejects duplicate active amendments before migration")
    func schemaFourPreflightRejectsDuplicateAmendments() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let originalID = try repository.saveDraft(validFlight())
        let loadedOriginal = try repository.flight(id: originalID)
        _ = try repository.finalise(try #require(loadedOriginal), acknowledgeWarnings: true)
        _ = try repository.beginAmendment(of: originalID)
        let db = try SQLiteConnection(path: repository.paths.workingDatabase.path)
        try db.execute("DROP INDEX idx_flights_one_active_amendment")
        try db.execute("INSERT INTO flights(source_pk, date, total_minutes, locked, record_state, amends_flight_id, modified_at) VALUES(NULL, ?, 1, 0, 'draft', ?, ?)", values: [.text(LogbookFormatters.isoFormatter.string(from: fixedDate())), .integer(originalID), .text(LogbookFormatters.isoFormatter.string(from: fixedDate()))])
        try db.execute("PRAGMA user_version = 3")
        let preflight = try repository.upgradePreflight()
        #expect(!preflight.amendmentIssues.isEmpty)
        #expect(throws: (any Error).self) { try repository.backUpAndUpgrade(using: preflight) }
        #expect(try repository.schemaVersion() == 3)
    }

    @Test("Document candidates use the shared import pipeline and honour every addition field selection")
    func documentImportParityAndFieldSelections() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Synthetic Roster.pdf")
        let candidate = FlightEntry(
            date: fixedDate(), departure: "ZZAA", arrival: "ZZBB", aircraftID: "G-DOC", aircraftType: "A320",
            operation: "", entryKind: "", pilotFunction: "", totalMinutes: 61, picNightMinutes: 7,
            picusNightMinutes: 9, pilotFlying: true, totalTakeoffs: 0, totalLandings: 0,
            remarks: "Exclude me", signatureName: "Synthetic Signer", signatureReference: "DOC-1"
        )
        var plan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        #expect(plan.sourceKind == .document)
        #expect(plan.fieldSelections.contains { $0.field == "Signature reference" })
        for index in plan.fieldSelections.indices where plan.fieldSelections[index].field == "Remarks" {
            plan.fieldSelections[index].decision = .exclude
        }
        _ = try repository.applyImport(plan)
        let importedFlights = try repository.flights(query: FlightQuery(recordStates: Set(FlightRecordState.allCases)))
        let imported = try #require(importedFlights.first)
        #expect(imported.remarks.isEmpty)
        #expect(imported.signatureName == "Synthetic Signer")
        #expect(imported.signatureReference == "DOC-1")
        #expect(imported.pilotFunction.isEmpty)
        #expect(imported.entryKind.isEmpty)
        #expect(imported.totalTakeoffs == 0)
        #expect(imported.totalLandings == 0)
        let documentOperations = try repository.operationBatches()
        #expect(documentOperations.first?.kind == "document_import")
    }

    @Test("Import choices drive staged actions and a no-op plan is rejected")
    func importResolutionActionsAndNoOp() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Synthetic OCR.txt")
        let candidate = FlightEntry(date: fixedDate(), departure: "ZZAA", arrival: "ZZBB", aircraftID: "G-ACT", totalMinutes: 20, remarks: "Source")

        let initial = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        let sourcePK = try #require(initial.additions.first?.sourcePK)
        repository.discardImportPlan(initial)
        var existing = candidate
        existing.sourcePK = sourcePK
        existing.remarks = "Draft before"
        let existingID = try repository.saveDraft(existing)

        var updatePlan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        updatePlan.resolutionActions[sourcePK] = .updateDraft
        _ = try repository.applyImport(updatePlan)
        let updatedExisting = try repository.flight(id: existingID)
        #expect(updatedExisting?.remarks == "Source")

        let noOpPlan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        #expect(noOpPlan.unchangedCount == 1)
        #expect(throws: (any Error).self) { try repository.applyImport(noOpPlan) }
    }

    @Test("Resolved conflict can import a separate draft without changing the conflicted record")
    func resolvedConflictImportsSeparateDraft() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Synthetic Conflict.pdf")
        let candidate = FlightEntry(date: fixedDate(), aircraftID: "G-CONF", totalMinutes: 15, remarks: "Source")
        let seedPlan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        let sourcePK = try #require(seedPlan.additions.first?.sourcePK)
        repository.discardImportPlan(seedPlan)
        var existing = candidate
        existing.sourcePK = sourcePK
        existing.remarks = "Trashed original"
        let existingID = try repository.saveDraft(existing)
        try repository.moveToTrash(id: existingID)

        var plan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        #expect(!plan.isApplicable)
        #expect(plan.conflictSourceIDs == [sourcePK])
        plan.resolutionActions[sourcePK] = .importSeparateDraft
        #expect(plan.isApplicable)
        _ = try repository.applyImport(plan)
        let unchangedConflict = try repository.flight(id: existingID)
        let conflictDrafts = try repository.flights(query: FlightQuery(recordStates: [.draft]))
        #expect(unchangedConflict?.recordState == .trashed)
        #expect(conflictDrafts.count == 1)
    }

    @Test("Import failure boundaries restore flight facts and retain failed operation history", arguments: TransactionFailureStage.allCases)
    func importFailureBoundaries(_ stage: TransactionFailureStage) throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let sentinelID = try repository.saveDraft(FlightEntry(date: fixedDate(), aircraftID: "G-SAFE", totalMinutes: 11, remarks: "Sentinel"))
        let before = try repository.flight(id: sentinelID)
        let plan = try repository.prepareDocumentImport(candidates: [FlightEntry(date: fixedDate(), aircraftID: "G-NEW", totalMinutes: 22)], sourceURL: root.appendingPathComponent("Failure.pdf"))
        do {
            _ = try repository.applyImport(plan, injectingFailureAt: stage)
            Issue.record("The injected import failure did not fail")
        } catch LogbookRepositoryError.operationFailedWithVerifiedRecovery(let operation, _, let recoveryOutcome) {
            #expect(operation == "Import")
            #expect(recoveryOutcome.contains(stage == .afterAtomicSwap ? "restored" : "remained active"))
        } catch {
            Issue.record("Import failure did not report a typed verified-recovery outcome: \(error)")
        }
        let restoredSentinel = try repository.flight(id: sentinelID)
        let remainingFlights = try repository.flights(query: FlightQuery(recordStates: Set(FlightRecordState.allCases)))
        let failedOperations = try repository.operationBatches()
        #expect(restoredSentinel == before)
        #expect(remainingFlights.count == 1)
        #expect(failedOperations.contains { $0.status == "failed" && $0.failureStage == stage.rawValue })
    }

    @Test("Restore failure boundaries preserve the active database and retain recovery history", arguments: TransactionFailureStage.allCases)
    func restoreFailureBoundaries(_ stage: TransactionFailureStage) throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let passphrase = "Synthetic-Restore-Only-2026"
        let originalID = try repository.saveDraft(FlightEntry(date: fixedDate(), aircraftID: "G-ORIG", totalMinutes: 17, remarks: "Original sentinel"))
        let backupFolder = root.appendingPathComponent("Encrypted", isDirectory: true)
        let backup = try EncryptedBackupService.createBackup(database: repository.paths.workingDatabase, destinationFolder: backupFolder, passphrase: passphrase)
        let postBackupID = try repository.saveDraft(FlightEntry(date: fixedDate(), aircraftID: "G-KEEP", totalMinutes: 23, remarks: "Post-backup sentinel"))
        let beforeOriginal = try repository.flight(id: originalID)
        let beforePostBackup = try repository.flight(id: postBackupID)

        let plan = try repository.prepareRestore(from: backup.encryptedBackup, passphrase: passphrase)
        do {
            _ = try repository.applyRestore(plan, injectingFailureAt: stage)
            Issue.record("The injected restore failure did not fail")
        } catch LogbookRepositoryError.operationFailedWithVerifiedRecovery(let operation, _, let recoveryOutcome) {
            #expect(operation == "Restore")
            #expect(recoveryOutcome.contains(stage == .afterAtomicSwap ? "restored" : "remained active"))
        } catch {
            Issue.record("Restore failure did not report a typed verified-recovery outcome: \(error)")
        }
        let restoredOriginal = try repository.flight(id: originalID)
        let restoredPostBackup = try repository.flight(id: postBackupID)
        let restoreOperations = try repository.operationBatches()
        #expect(restoredOriginal == beforeOriginal)
        #expect(restoredPostBackup == beforePostBackup)
        #expect(restoreOperations.contains { operation in
            operation.status == "failed" &&
            operation.failureStage == stage.rawValue &&
            operation.recoveryOutcome?.contains(stage == .afterAtomicSwap ? "restored" : "remained active") == true
        })
        let database = try SQLiteConnection(path: repository.paths.workingDatabase.path, readOnly: true)
        #expect(try database.integrityCheck().lowercased() == "ok")
        #expect(try database.rows("PRAGMA foreign_key_check").isEmpty)
    }

    @Test("Operation history API changes metadata only")
    func recordOperationChangesMetadataOnly() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let id = try repository.saveDraft(validFlight())
        let before = try repository.flight(id: id)
        let batch = OperationBatch(id: "metadata-only", kind: "export", status: "completed", summary: "Synthetic export", completedAt: Date())
        try repository.recordOperation(batch)
        let after = try repository.flight(id: id)
        let operations = try repository.operationBatches()
        #expect(after == before)
        #expect(operations.contains { $0.id == batch.id })
    }

    @Test("Intent writes and bootstrap never upgrade an existing database implicitly")
    func intentWritesRequireExplicitUpgrade() throws {
        let root = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups"),
            sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"),
            workingDatabase: root.appendingPathComponent("Legacy.sqlite")
        )
        do {
            let legacy = try SQLiteConnection(path: paths.workingDatabase.path)
            try legacy.execute("CREATE TABLE flights(id INTEGER PRIMARY KEY, locked INTEGER NOT NULL, total_minutes INTEGER NOT NULL, remarks TEXT NOT NULL, modified_at TEXT NOT NULL)")
            try legacy.execute("INSERT INTO flights VALUES(1, 0, 37, 'Intent sentinel', '2026-01-01T00:00:00Z')")
            try legacy.execute("PRAGMA user_version = 1")
        }
        let bytesBefore = try Data(contentsOf: paths.workingDatabase)
        let repository = LogbookRepository(paths: paths)

        #expect(throws: LogbookRepositoryError.self) { try repository.bootstrapIfNeeded() }
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.saveDraft(validFlight()) }

        let bytesAfter = try Data(contentsOf: paths.workingDatabase)
        let unchanged = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        #expect(bytesAfter == bytesBefore)
        #expect(try unchanged.rows("PRAGMA user_version").first?.values.first?.int == 1)
        #expect(!(try unchanged.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string }).contains("record_state"))
        #expect(try unchanged.rows("SELECT remarks FROM flights WHERE id = 1").first?["remarks"]?.string == "Intent sentinel")
    }

    @Test("Forged import and restore plans cannot nominate cleanup parents")
    func forgedPlansCannotDeleteCallerLocations() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let callerFolder = root.appendingPathComponent("Caller Owned", isDirectory: true)
        try FileManager.default.createDirectory(at: callerFolder, withIntermediateDirectories: true)
        let sentinel = callerFolder.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        let forgedImport = ImportPlan(
            sourceURL: callerFolder.appendingPathComponent("source.sqlite"),
            sourceSnapshotURL: callerFolder.appendingPathComponent("forged.sqlite")
        )
        repository.discardImportPlan(forgedImport)
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.applyImport(forgedImport) }
        #expect(FileManager.default.fileExists(atPath: sentinel.path))

        let forgedRestore = RestorePlan(
            encryptedBackupURL: callerFolder.appendingPathComponent("forged.blackboxbackup"),
            inspectedDatabaseURL: callerFolder.appendingPathComponent("Inspected.sqlite"),
            currentFlightCount: 0,
            restoredFlightCount: 0,
            currentTotalMinutes: 0,
            restoredTotalMinutes: 0,
            schemaVersion: LogbookRepository.currentSchemaVersion,
            integrityMessage: "ok"
        )
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.applyRestore(forgedRestore) }
        #expect(FileManager.default.fileExists(atPath: sentinel.path))
    }

    @Test("Document candidates and restore previews are sealed before apply")
    func previewInputsAreSealed() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }

        var documentPlan = try repository.prepareDocumentImport(
            candidates: [FlightEntry(date: fixedDate(), aircraftID: "G-SEAL", totalMinutes: 25, remarks: "Sealed")],
            sourceURL: root.appendingPathComponent("Synthetic OCR.txt")
        )
        let documentArtifact = try #require(documentPlan.candidateSnapshotURL).deletingLastPathComponent()
        documentPlan.additions[0].remarks = "Tampered after preview"
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.applyImport(documentPlan) }
        #expect(try repository.flights(query: FlightQuery(recordStates: Set(FlightRecordState.allCases))).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: documentArtifact.path))

        let passphrase = "Synthetic-Sealed-Restore"
        let backup = try EncryptedBackupService.createBackup(
            database: repository.paths.workingDatabase,
            destinationFolder: root.appendingPathComponent("Encrypted"),
            passphrase: passphrase
        )
        var restorePlan = try repository.prepareRestore(from: backup.encryptedBackup, passphrase: passphrase)
        let restoreArtifact = restorePlan.inspectedDatabaseURL.deletingLastPathComponent()
        restorePlan.restoredFlightCount += 1
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.applyRestore(restorePlan) }
        #expect(!FileManager.default.fileExists(atPath: restoreArtifact.path))
    }

    @Test("Date exclusion cannot invent a replacement date for an addition")
    func additionDateExclusionIsRejected() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        var plan = try repository.prepareDocumentImport(
            candidates: [FlightEntry(date: fixedDate(), aircraftID: "G-DATE", totalMinutes: 15)],
            sourceURL: root.appendingPathComponent("Synthetic Date.pdf")
        )
        for index in plan.fieldSelections.indices where plan.fieldSelections[index].field == "Date" {
            plan.fieldSelections[index].decision = .exclude
        }
        #expect(throws: LogbookRepositoryError.self) { _ = try repository.applyImport(plan) }
        #expect(try repository.flights(query: FlightQuery(recordStates: Set(FlightRecordState.allCases))).isEmpty)
    }

    @Test("Amendment cycles fail backup verification and restore inspection")
    func amendmentCyclesFailEveryDatabaseVerificationBoundary() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstID = try repository.saveDraft(validFlight())
        let secondID = try repository.saveDraft(validFlight())
        let first = try #require(try repository.flight(id: firstID))
        let second = try #require(try repository.flight(id: secondID))
        _ = try repository.finalise(first, acknowledgeWarnings: true)
        _ = try repository.finalise(second, acknowledgeWarnings: true)
        do {
            let corrupt = try SQLiteConnection(path: repository.paths.workingDatabase.path)
            try corrupt.execute("UPDATE flights SET record_state = 'superseded', locked = 1, amends_flight_id = ?, superseded_by_flight_id = ? WHERE id = ?", values: [.integer(secondID), .integer(secondID), .integer(firstID)])
            try corrupt.execute("UPDATE flights SET record_state = 'superseded', locked = 1, amends_flight_id = ?, superseded_by_flight_id = ? WHERE id = ?", values: [.integer(firstID), .integer(firstID), .integer(secondID)])
        }

        let verification = try repository.verifyBackup(at: repository.paths.workingDatabase)
        #expect(!verification.passed)
        #expect(verification.foreignKeyIssues?.isEmpty == true)
        #expect(verification.amendmentIssues?.contains { $0.localizedCaseInsensitiveContains("cycle") } == true)

        let backup = try EncryptedBackupService.createBackup(
            database: repository.paths.workingDatabase,
            destinationFolder: root.appendingPathComponent("Corrupt Encrypted"),
            passphrase: "Synthetic-Cycle"
        )
        let targetRoot = try tempDirectory()
        defer { try? FileManager.default.removeItem(at: targetRoot) }
        let targetPaths = LogbookPaths(
            backupFolder: targetRoot.appendingPathComponent("Backups"),
            sourceLogTenDatabase: targetRoot.appendingPathComponent("Missing.sql"),
            workingDatabase: targetRoot.appendingPathComponent("Blackbox.sqlite")
        )
        let target = LogbookRepository(paths: targetPaths)
        try target.bootstrapIfNeeded()
        #expect(throws: LogbookRepositoryError.self) {
            _ = try target.prepareRestore(from: backup.encryptedBackup, passphrase: "Synthetic-Cycle")
        }
    }

    @Test("LogTen comparison uses every persisted import field")
    func comparisonUsesCanonicalPersistedFieldManifest() {
        let source = FlightEntry(
            sourcePK: 9001, date: fixedDate(), departure: "EGAA", arrival: "EGBB", route: "DCT TEST",
            aircraftID: "G-FULL", aircraftType: "A320", flightNumber: "SYN9001", operation: "MP",
            entryKind: "Simulator", pilotFunction: "PIC", totalMinutes: 121, picMinutes: 1,
            picDayMinutes: 2, picNightMinutes: 3, picusMinutes: 4, picusDayMinutes: 5,
            picusNightMinutes: 6, copilotMinutes: 7, copilotDayMinutes: 8, copilotNightMinutes: 9,
            dualMinutes: 10, instructorMinutes: 11, nightMinutes: 12, instrumentMinutes: 13,
            crossCountryMinutes: 14, fstdMinutes: 15, pilotFlying: true, dayTakeoffs: 16,
            nightTakeoffs: 17, totalTakeoffs: 18, dayLandings: 19, nightLandings: 20,
            totalLandings: 21, passengerCount: 22, distanceNM: 23.5, crewNames: "Synthetic Crew",
            crewRoles: "Synthetic Crew=Observer", departureLatitude: 24.5, departureLongitude: 25.5,
            arrivalLatitude: 26.5, arrivalLongitude: 27.5, remarks: "Synthetic remarks",
            signatureName: "Synthetic Signer", signatureReference: "SYN-REF"
        )
        let different = FlightEntry(sourcePK: 9001, date: fixedDate().addingTimeInterval(60))
        let fields = Set(LogbookRepository.comparisonIssues(sourcePK: 9001, logTen: source, blackbox: different).map(\.field))
        let expected = Set([
            "Date", "Departure", "Arrival", "Route", "Aircraft", "Type", "Flight number", "Operation", "Entry type", "Function",
            "Total", "PIC", "PIC day", "PIC night", "PICUS", "PICUS day", "PICUS night", "Co-pilot", "Co-pilot day", "Co-pilot night",
            "Dual", "Instructor", "Night", "Instrument", "Cross-country", "FSTD", "Pilot flying",
            "Day takeoffs", "Night takeoffs", "Takeoffs", "Day landings", "Night landings", "Landings", "Passengers", "Distance",
            "Crew", "Crew roles", "Departure latitude", "Departure longitude", "Arrival latitude", "Arrival longitude",
            "Remarks", "Signature name", "Signature reference"
        ])
        #expect(fields == expected)
        #expect(LogbookRepository.comparisonIssues(sourcePK: 9001, logTen: source, blackbox: source).isEmpty)
    }

    @Test("Partial coordinates and FSTD role values cannot be overwritten by suggestions")
    func suggestionRejectionRulesPreserveEnteredFacts() {
        var partial = FlightEntry(date: fixedDate(), departure: "EGLL", arrival: "EGKK", departureLatitude: 51.0)
        let unavailable = FlightSuggestionEngine.suggestions(for: partial).first { $0.field == .departureCoordinates }
        #expect(unavailable?.isActionable == false)
        let forgedCoordinate = FlightSuggestion(
            field: .departureCoordinates,
            title: "Forged",
            explanation: "Synthetic",
            currentValue: "partial",
            proposedValue: "1, 2",
            latitude: 1,
            longitude: 2
        )
        partial = FlightSuggestionEngine.applying(forgedCoordinate, to: partial)
        #expect(partial.departureLatitude == 51.0)
        #expect(partial.departureLongitude == nil)

        let fstdEntered = FlightEntry(date: fixedDate(), pilotFunction: "PIC", totalMinutes: 60, fstdMinutes: 5)
        let role = FlightSuggestionEngine.suggestions(for: fstdEntered).first { $0.title == "Role allocation" }
        #expect(role?.isActionable == false)
        #expect(role?.unavailableReason?.contains("non-zero") == true)
    }

    @Test("Impossible role, simulator, and coordinate combinations are structural errors")
    func expandedStructuralValidation() {
        let impossible = FlightEntry(
            date: fixedDate(), aircraftID: "SIM-1", entryKind: "Simulator", pilotFunction: "PIC",
            totalMinutes: 60, picMinutes: 61, instrumentMinutes: 70, crossCountryMinutes: 1,
            fstdMinutes: 30, pilotFlying: true, departureLatitude: 51
        )
        let report = FlightSuggestionEngine.validationReport(for: impossible)
        #expect(report.hasErrors)
        #expect(report.issues.contains { $0.field == "PIC" && $0.severity == .error })
        #expect(report.issues.contains { $0.field == "Instrument" && $0.severity == .error })
        #expect(report.issues.contains { $0.field == "Simulator" && $0.severity == .error })
        #expect(report.issues.contains { $0.field == "Departure coordinates" })
    }

    @Test("Backup artifacts remain unique within the same timestamp")
    func backupArtifactNamesAreCollisionSafe() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("Encrypted", isDirectory: true)
        let first = try EncryptedBackupService.createBackup(database: repository.paths.workingDatabase, destinationFolder: destination, passphrase: "Synthetic-Unique")
        let second = try EncryptedBackupService.createBackup(database: repository.paths.workingDatabase, destinationFolder: destination, passphrase: "Synthetic-Unique")
        #expect(first.encryptedBackup != second.encryptedBackup)
        #expect(first.manifest != second.manifest)
        #expect(FileManager.default.fileExists(atPath: first.encryptedBackup.path))
        #expect(FileManager.default.fileExists(atPath: second.encryptedBackup.path))
    }

    @Test("Import preview identifies unchanged rows and source-only omissions without removal")
    func importPreviewListsNonMutatingRows() throws {
        let (repository, root) = try makeRepository()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceURL = root.appendingPathComponent("Synthetic Preview.pdf")
        let candidate = FlightEntry(date: fixedDate(), aircraftID: "G-SAME", totalMinutes: 20, remarks: "Same")
        let seedPlan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        let matchingSourcePK = try #require(seedPlan.additions.first?.sourcePK)
        repository.discardImportPlan(seedPlan)
        var existingMatch = candidate
        existingMatch.sourcePK = matchingSourcePK
        let matchingID = try repository.saveDraft(existingMatch)
        let omissionID = try repository.saveDraft(FlightEntry(sourcePK: -777, date: fixedDate(), aircraftID: "G-ONLY", totalMinutes: 30, remarks: "Blackbox only"))

        let plan = try repository.prepareDocumentImport(candidates: [candidate], sourceURL: sourceURL)
        #expect(plan.unchangedCount == 1)
        #expect(plan.unchangedRecords.map(\.flightID) == [matchingID])
        #expect(plan.missingFromSourceCount == 1)
        #expect(plan.sourceOnlyOmissions.map(\.flightID) == [omissionID])
        #expect(try repository.flight(id: omissionID)?.remarks == "Blackbox only")
        repository.discardImportPlan(plan)
    }

    @Test("Empty comparison summaries can never report a genuine match")
    func emptyComparisonCannotMatch() {
        let empty = LogTenComparisonSummary()
        let snapshot = LogTenComparisonSnapshot(sourcePath: "/tmp/empty.sqlite", sourceIsLiveLogTen: false, logTen: empty, blackboxImported: empty, blackboxAll: empty, blackboxOnly: empty, missingInBlackbox: 0, missingInLogTen: 0, issues: [])
        #expect(!snapshot.importedRowsMatch)
        let state = LogTenComparisonState.empty("No source flights")
        if case .loaded = state { Issue.record("An empty source cannot be loaded as a match") }
    }

    private func makeRepository() throws -> (LogbookRepository, URL) {
        let root = try tempDirectory()
        let paths = LogbookPaths(backupFolder: root.appendingPathComponent("Backups"), sourceLogTenDatabase: root.appendingPathComponent("Missing.sql"), workingDatabase: root.appendingPathComponent("Blackbox.sqlite"))
        let repository = LogbookRepository(paths: paths)
        try repository.bootstrapIfNeeded()
        return (repository, root)
    }

    private func validFlight(recordState: FlightRecordState = .draft) -> FlightEntry {
        FlightEntry(date: fixedDate(), departure: "EGLL", arrival: "EGKK", aircraftID: "G-TEST", aircraftType: "A320", operation: "MP", pilotFunction: "Co-pilot", totalMinutes: 60, copilotMinutes: 60, recordState: recordState)
    }

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Blackbox-Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func fixedDate() -> Date {
        ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
    }

    private func performanceThreshold(debug: Double, release: Double) -> Duration {
        #if DEBUG
        .seconds(debug)
        #else
        .seconds(release)
        #endif
    }
}
