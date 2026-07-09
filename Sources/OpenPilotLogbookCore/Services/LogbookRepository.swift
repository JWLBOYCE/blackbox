import Foundation

public final class LogbookRepository {
    public let paths: LogbookPaths

    public init(paths: LogbookPaths = .applicationSupport) {
        self.paths = paths
    }

    public func bootstrapIfNeeded() throws {
        try migrateLegacyDesktopStoreIfNeeded()
        let needsImport = !FileManager.default.fileExists(atPath: paths.workingDatabase.path)
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try createSchema(in: db)
        let isEmpty = try flightCount(in: db) == 0
        let hasSource = (try? resolvedLogTenSource(in: db)) != nil
        if needsImport || isEmpty {
            if hasSource {
                try importLogTenBackup(into: db)
            }
        }
        if hasSource, try setting("enriched_import_v5", in: db) != "true" {
            try enrichFromLogTenBackup(into: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('enriched_import_v5', 'true')")
        }
        if hasSource, try setting("enriched_import_v6", in: db) != "true" {
            try enrichFromLogTenBackup(into: db)
            try backfillEntryKindsAndCrewRoles(in: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('enriched_import_v6', 'true')")
        }
        if hasSource, try setting("logten_time_mapping_v7", in: db) != "true" {
            try enrichFromLogTenBackup(into: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('logten_time_mapping_v7', 'true')")
        }
        if hasSource, try setting("logten_time_mapping_v8", in: db) != "true" {
            try enrichFromLogTenBackup(into: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('logten_time_mapping_v8', 'true')")
        }
        if try setting("sector_notes_v1", in: db) != "true" {
            try backfillSectorNotes(in: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('sector_notes_v1', 'true')")
        }
        if try setting("entry_roles_v3", in: db) != "true" {
            try backfillEntryKindsAndCrewRoles(in: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('entry_roles_v3', 'true')")
        }
        if try setting("pilot_function_v2", in: db) != "true" {
            try backfillPilotFunctions(in: db)
            try backfillEntryKindsAndCrewRoles(in: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('pilot_function_v2', 'true')")
        }
        if try setting("pilot_function_v3", in: db) != "true" {
            try backfillPilotFunctions(in: db)
            try backfillEntryKindsAndCrewRoles(in: db)
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('pilot_function_v3', 'true')")
        }
    }

    public func createSchema(in db: SQLiteConnection) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS flights (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            source_pk INTEGER UNIQUE,
            date TEXT NOT NULL,
            departure TEXT NOT NULL DEFAULT '',
            arrival TEXT NOT NULL DEFAULT '',
            route TEXT NOT NULL DEFAULT '',
            aircraft_id TEXT NOT NULL DEFAULT '',
            aircraft_type TEXT NOT NULL DEFAULT '',
            flight_number TEXT NOT NULL DEFAULT '',
            operation TEXT NOT NULL DEFAULT '',
            entry_kind TEXT NOT NULL DEFAULT 'Flight',
            pilot_function TEXT NOT NULL DEFAULT '',
            total_minutes INTEGER NOT NULL DEFAULT 0,
            pic_minutes INTEGER NOT NULL DEFAULT 0,
            pic_day_minutes INTEGER NOT NULL DEFAULT 0,
            pic_night_minutes INTEGER NOT NULL DEFAULT 0,
            picus_minutes INTEGER NOT NULL DEFAULT 0,
            picus_day_minutes INTEGER NOT NULL DEFAULT 0,
            picus_night_minutes INTEGER NOT NULL DEFAULT 0,
            copilot_minutes INTEGER NOT NULL DEFAULT 0,
            copilot_day_minutes INTEGER NOT NULL DEFAULT 0,
            copilot_night_minutes INTEGER NOT NULL DEFAULT 0,
            dual_minutes INTEGER NOT NULL DEFAULT 0,
            instructor_minutes INTEGER NOT NULL DEFAULT 0,
            night_minutes INTEGER NOT NULL DEFAULT 0,
            instrument_minutes INTEGER NOT NULL DEFAULT 0,
            cross_country_minutes INTEGER NOT NULL DEFAULT 0,
            fstd_minutes INTEGER NOT NULL DEFAULT 0,
            pilot_flying INTEGER NOT NULL DEFAULT 0,
            day_takeoffs INTEGER NOT NULL DEFAULT 0,
            night_takeoffs INTEGER NOT NULL DEFAULT 0,
            total_takeoffs INTEGER NOT NULL DEFAULT 0,
            day_landings INTEGER NOT NULL DEFAULT 0,
            night_landings INTEGER NOT NULL DEFAULT 0,
            total_landings INTEGER NOT NULL DEFAULT 0,
            passenger_count INTEGER NOT NULL DEFAULT 0,
            distance_nm REAL NOT NULL DEFAULT 0,
            crew_names TEXT NOT NULL DEFAULT '',
            crew_roles TEXT NOT NULL DEFAULT '',
            departure_lat REAL,
            departure_lon REAL,
            arrival_lat REAL,
            arrival_lon REAL,
            remarks TEXT NOT NULL DEFAULT '',
            signature_name TEXT NOT NULL DEFAULT '',
            signature_reference TEXT NOT NULL DEFAULT '',
            locked INTEGER NOT NULL DEFAULT 0,
            modified_at TEXT NOT NULL
        )
        """)
        try addColumnIfNeeded("flights", name: "copilot_day_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "copilot_night_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "entry_kind", definition: "TEXT NOT NULL DEFAULT 'Flight'", in: db)
        try addColumnIfNeeded("flights", name: "pic_day_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "pic_night_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "picus_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "picus_day_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "picus_night_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "cross_country_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "crew_roles", definition: "TEXT NOT NULL DEFAULT ''", in: db)
        try addColumnIfNeeded("flights", name: "pilot_flying", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "day_takeoffs", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "night_takeoffs", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "total_takeoffs", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "passenger_count", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "distance_nm", definition: "REAL NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("flights", name: "crew_names", definition: "TEXT NOT NULL DEFAULT ''", in: db)
        try addColumnIfNeeded("flights", name: "departure_lat", definition: "REAL", in: db)
        try addColumnIfNeeded("flights", name: "departure_lon", definition: "REAL", in: db)
        try addColumnIfNeeded("flights", name: "arrival_lat", definition: "REAL", in: db)
        try addColumnIfNeeded("flights", name: "arrival_lon", definition: "REAL", in: db)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_date ON flights(date)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_aircraft ON flights(aircraft_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_departure ON flights(departure)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_arrival ON flights(arrival)")
        try db.execute("""
        CREATE TABLE IF NOT EXISTS places (
            identifier TEXT PRIMARY KEY,
            name TEXT NOT NULL DEFAULT '',
            icao TEXT NOT NULL DEFAULT '',
            iata TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            source TEXT NOT NULL DEFAULT ''
        )
        """)
        try addColumnIfNeeded("places", name: "source", definition: "TEXT NOT NULL DEFAULT ''", in: db)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS people (
            name TEXT PRIMARY KEY,
            flights INTEGER NOT NULL DEFAULT 0
        )
        """)
        try db.execute("""
        CREATE TABLE IF NOT EXISTS settings (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL DEFAULT ''
        )
        """)
    }

    private func addColumnIfNeeded(_ table: String, name: String, definition: String, in db: SQLiteConnection) throws {
        let columns = try db.rows("PRAGMA table_info(\(table))").compactMap { $0["name"]?.string }
        if !columns.contains(name) {
            try db.execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
        }
    }

    private func migrateLegacyDesktopStoreIfNeeded() throws {
        guard paths.workingDatabase == LogbookPaths.applicationSupport.workingDatabase else { return }
        guard !FileManager.default.fileExists(atPath: paths.workingDatabase.path) else { return }
        let legacy = LogbookPaths.desktopBackup.workingDatabase
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        try FileManager.default.createDirectory(at: paths.workingDatabase.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: legacy, to: paths.workingDatabase)
    }

    public func flights(search: String = "") throws -> [FlightEntry] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        let trimmed = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let sql: String
        let values: [SQLiteValue]
        if trimmed.isEmpty {
            sql = "SELECT * FROM flights ORDER BY date DESC, id DESC"
            values = []
        } else {
            sql = """
            SELECT * FROM flights
            WHERE departure LIKE ? OR arrival LIKE ? OR route LIKE ? OR aircraft_id LIKE ? OR aircraft_type LIKE ? OR remarks LIKE ? OR flight_number LIKE ?
            ORDER BY date DESC, id DESC
            """
            let token: SQLiteValue = .text("%\(trimmed)%")
            values = Array(repeating: token, count: 7)
        }
        return try db.rows(sql, values: values).map(Self.flight(from:))
    }

    public func flight(id: Int64) throws -> FlightEntry? {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        return try db.rows("SELECT * FROM flights WHERE id = ?", values: [.integer(id)]).first.map(Self.flight(from:))
    }

    public func save(_ flight: FlightEntry) throws -> Int64 {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        if let id = flight.id {
            try ensureUnlocked(id: id, in: db)
        }
        let flight = try enrichedForSave(flight, db: db)
        let modified = LogbookFormatters.isoFormatter.string(from: Date())
        let values: [SQLiteValue] = [
            flight.sourcePK.map(SQLiteValue.integer) ?? .null,
            .text(LogbookFormatters.isoFormatter.string(from: flight.date)),
            .text(flight.departure), .text(flight.arrival), .text(flight.route),
            .text(flight.aircraftID), .text(flight.aircraftType), .text(flight.flightNumber),
            .text(flight.operation), .text(flight.entryKind), .text(flight.pilotFunction),
            .integer(Int64(flight.totalMinutes)), .integer(Int64(flight.picMinutes)),
            .integer(Int64(flight.picDayMinutes)), .integer(Int64(flight.picNightMinutes)), .integer(Int64(flight.picusMinutes)),
            .integer(Int64(flight.picusDayMinutes)), .integer(Int64(flight.picusNightMinutes)),
            .integer(Int64(flight.copilotMinutes)), .integer(Int64(flight.copilotDayMinutes)), .integer(Int64(flight.copilotNightMinutes)),
            .integer(Int64(flight.dualMinutes)), .integer(Int64(flight.instructorMinutes)), .integer(Int64(flight.nightMinutes)),
            .integer(Int64(flight.instrumentMinutes)), .integer(Int64(flight.crossCountryMinutes)), .integer(Int64(flight.fstdMinutes)),
            .integer(flight.pilotFlying ? 1 : 0),
            .integer(Int64(flight.dayTakeoffs)), .integer(Int64(flight.nightTakeoffs)),
            .integer(Int64(flight.totalTakeoffs)),
            .integer(Int64(flight.dayLandings)), .integer(Int64(flight.nightLandings)),
            .integer(Int64(flight.totalLandings)), .integer(Int64(flight.passengerCount)),
            .real(flight.distanceNM), .text(flight.crewNames), .text(flight.crewRoles),
            flight.departureLatitude.map(SQLiteValue.real) ?? .null,
            flight.departureLongitude.map(SQLiteValue.real) ?? .null,
            flight.arrivalLatitude.map(SQLiteValue.real) ?? .null,
            flight.arrivalLongitude.map(SQLiteValue.real) ?? .null,
            .text(flight.remarks),
            .text(flight.signatureName), .text(flight.signatureReference),
            .integer(flight.locked ? 1 : 0), .text(modified)
        ]
        if let id = flight.id {
            try db.execute("""
            UPDATE flights SET
              source_pk = ?, date = ?, departure = ?, arrival = ?, route = ?,
              aircraft_id = ?, aircraft_type = ?, flight_number = ?, operation = ?, entry_kind = ?, pilot_function = ?,
              total_minutes = ?, pic_minutes = ?, pic_day_minutes = ?, pic_night_minutes = ?, picus_minutes = ?, picus_day_minutes = ?, picus_night_minutes = ?,
              copilot_minutes = ?, copilot_day_minutes = ?, copilot_night_minutes = ?,
              dual_minutes = ?, instructor_minutes = ?, night_minutes = ?, instrument_minutes = ?, cross_country_minutes = ?, fstd_minutes = ?,
              pilot_flying = ?, day_takeoffs = ?, night_takeoffs = ?, total_takeoffs = ?,
              day_landings = ?, night_landings = ?, total_landings = ?, passenger_count = ?, distance_nm = ?,
              crew_names = ?, crew_roles = ?, departure_lat = ?, departure_lon = ?, arrival_lat = ?, arrival_lon = ?,
              remarks = ?, signature_name = ?, signature_reference = ?, locked = ?, modified_at = ?
            WHERE id = ?
            """, values: values + [.integer(id)])
            return id
        } else {
            try db.execute("""
            INSERT INTO flights (
              source_pk, date, departure, arrival, route, aircraft_id, aircraft_type, flight_number, operation, entry_kind, pilot_function,
              total_minutes, pic_minutes, pic_day_minutes, pic_night_minutes, picus_minutes, picus_day_minutes, picus_night_minutes,
              copilot_minutes, copilot_day_minutes, copilot_night_minutes,
              dual_minutes, instructor_minutes, night_minutes, instrument_minutes, cross_country_minutes, fstd_minutes,
              pilot_flying, day_takeoffs, night_takeoffs, total_takeoffs,
              day_landings, night_landings, total_landings, passenger_count, distance_nm, crew_names,
              crew_roles, departure_lat, departure_lon, arrival_lat, arrival_lon,
              remarks, signature_name, signature_reference, locked, modified_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, values: values)
            return db.lastInsertRowID()
        }
    }

    public func replaceWithLogTenDatabase(at sourceURL: URL) throws -> Int {
        guard sourceURL.path != paths.workingDatabase.path else {
            throw NSError(domain: "BlackboxImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Choose the LogTen Pro database, not the Blackbox working database."])
        }

        let source = try SQLiteConnection(path: sourceURL.path, readOnly: true)
        let sourceRows = try logTenFlightRows(from: source)
        guard !sourceRows.isEmpty else {
            throw NSError(domain: "BlackboxImport", code: 2, userInfo: [NSLocalizedDescriptionKey: "No LogTen Pro flights were found in the selected database."])
        }

        try FileManager.default.createDirectory(at: paths.backupFolder, withIntermediateDirectories: true)
        let backupURL = paths.backupFolder.appendingPathComponent("Blackbox-working-backup-\(Self.backupTimestamp()).sqlite")
        if FileManager.default.fileExists(atPath: paths.workingDatabase.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try FileManager.default.copyItem(at: paths.workingDatabase, to: backupURL)
        }

        do {
            let destination = try SQLiteConnection(path: paths.workingDatabase.path)
            try createSchema(in: destination)
            try destination.transaction {
                try destination.execute("DELETE FROM flights")
                try importPlaces(from: source, into: destination)
                for row in sourceRows {
                    let flight = Self.flightFromLogTen(row: row)
                    _ = try saveImported(flight, in: destination)
                }
                try backfillPilotFunctions(in: destination)
                try backfillEntryKindsAndCrewRoles(in: destination)
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('source_backup', ?)", values: [.text(sourceURL.path)])
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('imported_at', ?)", values: [.text(LogbookFormatters.isoFormatter.string(from: Date()))])
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('import_backup', ?)", values: [.text(backupURL.path)])
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('enriched_import_v5', 'true')")
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('enriched_import_v6', 'true')")
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('entry_roles_v3', 'true')")
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('pilot_function_v2', 'true')")
                try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('pilot_function_v3', 'true')")
            }
            return sourceRows.count
        } catch {
            if FileManager.default.fileExists(atPath: backupURL.path) {
                try? FileManager.default.removeItem(at: paths.workingDatabase)
                try? FileManager.default.copyItem(at: backupURL, to: paths.workingDatabase)
            }
            throw error
        }
    }

    public func deleteFlight(id: Int64) throws {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try ensureUnlocked(id: id, in: db)
        try db.execute("DELETE FROM flights WHERE id = ?", values: [.integer(id)])
    }

    public func unlockFlight(id: Int64) throws {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try db.execute(
            "UPDATE flights SET locked = 0, modified_at = ? WHERE id = ?",
            values: [.text(LogbookFormatters.isoFormatter.string(from: Date())), .integer(id)]
        )
    }

    public func lockFlight(id: Int64) throws {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try db.execute(
            "UPDATE flights SET locked = 1, modified_at = ? WHERE id = ?",
            values: [.text(LogbookFormatters.isoFormatter.string(from: Date())), .integer(id)]
        )
    }

    private func ensureUnlocked(id: Int64, in db: SQLiteConnection) throws {
        guard let row = try db.rows("SELECT locked FROM flights WHERE id = ?", values: [.integer(id)]).first else {
            throw NSError(domain: "BlackboxLogbook", code: 20, userInfo: [NSLocalizedDescriptionKey: "The flight entry no longer exists."])
        }
        guard (row["locked"]?.int ?? 0) == 0 else {
            throw NSError(domain: "BlackboxLogbook", code: 21, userInfo: [NSLocalizedDescriptionKey: "This flight entry is locked and cannot be changed or deleted."])
        }
    }

    public func summary() throws -> LogbookSummary {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        let row = try db.rows("""
        SELECT COUNT(*) AS flight_count,
               COALESCE(SUM(MAX(total_minutes - fstd_minutes, 0)), 0) AS total_minutes,
               COALESCE(SUM(pic_minutes), 0) AS pic_minutes,
               COALESCE(SUM(picus_minutes), 0) AS picus_minutes,
               COALESCE(SUM(picus_day_minutes), 0) AS picus_day_minutes,
               COALESCE(SUM(picus_night_minutes), 0) AS picus_night_minutes,
               COALESCE(SUM(copilot_minutes), 0) AS copilot_minutes,
               COALESCE(SUM(copilot_day_minutes), 0) AS copilot_day_minutes,
               COALESCE(SUM(copilot_night_minutes), 0) AS copilot_night_minutes,
               COALESCE(SUM(night_minutes), 0) AS night_minutes,
               COALESCE(SUM(instrument_minutes), 0) AS instrument_minutes,
               COALESCE(SUM(cross_country_minutes), 0) AS cross_country_minutes,
               COALESCE(SUM(fstd_minutes), 0) AS fstd_minutes,
               COALESCE(SUM(total_landings), 0) AS landings,
               COALESCE(SUM(passenger_count), 0) AS passengers,
               COALESCE(SUM(distance_nm), 0) AS distance_nm,
               MAX(date) AS last_date
        FROM flights
        """).first ?? [:]
        return LogbookSummary(
            flightCount: row["flight_count"]?.int ?? 0,
            totalMinutes: row["total_minutes"]?.int ?? 0,
            picMinutes: row["pic_minutes"]?.int ?? 0,
            picusMinutes: row["picus_minutes"]?.int ?? 0,
            picusDayMinutes: row["picus_day_minutes"]?.int ?? 0,
            picusNightMinutes: row["picus_night_minutes"]?.int ?? 0,
            copilotMinutes: row["copilot_minutes"]?.int ?? 0,
            copilotDayMinutes: row["copilot_day_minutes"]?.int ?? 0,
            copilotNightMinutes: row["copilot_night_minutes"]?.int ?? 0,
            nightMinutes: row["night_minutes"]?.int ?? 0,
            instrumentMinutes: row["instrument_minutes"]?.int ?? 0,
            crossCountryMinutes: row["cross_country_minutes"]?.int ?? 0,
            fstdMinutes: row["fstd_minutes"]?.int ?? 0,
            landings: row["landings"]?.int ?? 0,
            passengers: row["passengers"]?.int ?? 0,
            distanceNM: row["distance_nm"]?.double ?? 0,
            lastFlightDate: Self.date(from: row["last_date"]?.string ?? "")
        )
    }

    public func aircraftSummaries() throws -> [AircraftSummary] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        return try db.rows("""
        SELECT aircraft_id, aircraft_type, COUNT(*) AS flight_count,
               COALESCE(SUM(MAX(total_minutes - fstd_minutes, 0)), 0) AS total_minutes,
               COALESCE(SUM(total_landings), 0) AS landings
        FROM flights
        GROUP BY aircraft_id, aircraft_type
        ORDER BY total_minutes DESC
        """).map { row in
            AircraftSummary(
                aircraftID: row["aircraft_id"]?.string ?? "",
                aircraftType: row["aircraft_type"]?.string ?? "",
                flightCount: row["flight_count"]?.int ?? 0,
                totalMinutes: row["total_minutes"]?.int ?? 0,
                landings: row["landings"]?.int ?? 0
            )
        }
    }

    public func typeSummaries() throws -> [TypeSummary] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        return try db.rows("""
        SELECT aircraft_type, COUNT(*) AS flight_count,
               COALESCE(SUM(MAX(total_minutes - fstd_minutes, 0)), 0) AS total_minutes,
               COALESCE(SUM(copilot_day_minutes), 0) AS copilot_day_minutes,
               COALESCE(SUM(copilot_night_minutes), 0) AS copilot_night_minutes,
               COALESCE(SUM(distance_nm), 0) AS distance_nm
        FROM flights
        GROUP BY aircraft_type
        ORDER BY total_minutes DESC
        """).map { row in
            TypeSummary(
                aircraftType: row["aircraft_type"]?.string ?? "",
                flightCount: row["flight_count"]?.int ?? 0,
                totalMinutes: row["total_minutes"]?.int ?? 0,
                copilotDayMinutes: row["copilot_day_minutes"]?.int ?? 0,
                copilotNightMinutes: row["copilot_night_minutes"]?.int ?? 0,
                distanceNM: row["distance_nm"]?.double ?? 0
            )
        }
    }

    public func personSummaries() throws -> [PersonSummary] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        let rows = try db.rows("SELECT crew_names, MAX(total_minutes - fstd_minutes, 0) AS total_minutes FROM flights WHERE crew_names != ''")
        var totals: [String: (count: Int, minutes: Int)] = [:]
        for row in rows {
            let names = FlightEntry.splitCrewNames(row["crew_names"]?.string ?? "")
            for name in names {
                let current = totals[name] ?? (0, 0)
                totals[name] = (current.count + 1, current.minutes + (row["total_minutes"]?.int ?? 0))
            }
        }
        return totals.map { PersonSummary(name: $0.key, flightCount: $0.value.count, totalMinutes: $0.value.minutes) }
            .sorted { $0.flightCount == $1.flightCount ? $0.name < $1.name : $0.flightCount > $1.flightCount }
    }

    public func placeVisitSummaries() throws -> [PlaceVisitSummary] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        let rows = try db.rows("""
        SELECT p.identifier, p.name,
               COALESCE(d.departures, 0) AS departures,
               COALESCE(a.arrivals, 0) AS arrivals
        FROM places p
        LEFT JOIN (SELECT departure AS identifier, COUNT(*) AS departures FROM flights WHERE departure != '' GROUP BY departure) d ON d.identifier = p.identifier
        LEFT JOIN (SELECT arrival AS identifier, COUNT(*) AS arrivals FROM flights WHERE arrival != '' GROUP BY arrival) a ON a.identifier = p.identifier
        WHERE COALESCE(d.departures, 0) + COALESCE(a.arrivals, 0) > 0
        ORDER BY (COALESCE(d.departures, 0) + COALESCE(a.arrivals, 0)) DESC, p.identifier
        """)
        return rows.map {
            PlaceVisitSummary(
                identifier: $0["identifier"]?.string ?? "",
                name: $0["name"]?.string ?? "",
                departures: $0["departures"]?.int ?? 0,
                arrivals: $0["arrivals"]?.int ?? 0
            )
        }
    }

    public func mapRoutes(limit: Int = 800) throws -> [MapRoute] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        return try db.rows("""
        SELECT id, departure, arrival, departure_lat, departure_lon, arrival_lat, arrival_lon, distance_nm
        FROM flights
        WHERE departure_lat IS NOT NULL AND departure_lon IS NOT NULL AND arrival_lat IS NOT NULL AND arrival_lon IS NOT NULL
        ORDER BY date DESC
        LIMIT ?
        """, values: [.integer(Int64(limit))]).compactMap { row in
            guard
                let id = row["id"]?.int64,
                let depLat = row["departure_lat"]?.double,
                let depLon = row["departure_lon"]?.double,
                let arrLat = row["arrival_lat"]?.double,
                let arrLon = row["arrival_lon"]?.double
            else { return nil }
            return MapRoute(
                id: id,
                departure: row["departure"]?.string ?? "",
                arrival: row["arrival"]?.string ?? "",
                departureLatitude: depLat,
                departureLongitude: depLon,
                arrivalLatitude: arrLat,
                arrivalLongitude: arrLon,
                distanceNM: row["distance_nm"]?.double ?? 0
            )
        }
    }

    public func suggestions() throws -> SuggestionBundle {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        func values(_ sql: String) throws -> [String] {
            try db.rows(sql).compactMap { row in
                let value = row["value"]?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return value.isEmpty ? nil : value
            }
        }
        return SuggestionBundle(
            aircraftIDs: try values("SELECT DISTINCT aircraft_id AS value FROM flights WHERE aircraft_id != '' ORDER BY aircraft_id LIMIT 300"),
            aircraftTypes: try values("SELECT DISTINCT aircraft_type AS value FROM flights WHERE aircraft_type != '' ORDER BY aircraft_type LIMIT 300"),
            places: try values("SELECT identifier AS value FROM places WHERE identifier != '' ORDER BY identifier LIMIT 500"),
            people: try personSummaries().prefix(300).map(\.name)
        )
    }

    public func recencySnapshot(now: Date = Date()) throws -> RecencySnapshot {
        try LogbookAnalysis.recencySnapshot(flights: flights(), now: now)
    }

    public func duplicateFlightGroups() throws -> [DuplicateFlightGroup] {
        try LogbookAnalysis.duplicateGroups(flights: flights())
    }

    public func airportOverrides() throws -> [AirportOverride] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        return try db.rows("""
        SELECT identifier, name, latitude, longitude
        FROM places
        WHERE source = 'Manual Override' AND latitude IS NOT NULL AND longitude IS NOT NULL
        ORDER BY identifier
        """).compactMap { row in
            guard
                let identifier = row["identifier"]?.string,
                let latitude = row["latitude"]?.double,
                let longitude = row["longitude"]?.double
            else { return nil }
            return AirportOverride(identifier: identifier, name: row["name"]?.string ?? "", latitude: latitude, longitude: longitude)
        }
    }

    public func saveAirportOverride(_ override: AirportOverride) throws {
        let identifier = override.identifier.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !identifier.isEmpty else {
            throw NSError(domain: "BlackboxAirportOverride", code: 1, userInfo: [NSLocalizedDescriptionKey: "Airport identifier is required."])
        }
        guard (-90...90).contains(override.latitude), (-180...180).contains(override.longitude) else {
            throw NSError(domain: "BlackboxAirportOverride", code: 2, userInfo: [NSLocalizedDescriptionKey: "Airport coordinates are outside valid latitude/longitude ranges."])
        }
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try createSchema(in: db)
        try db.execute("""
        INSERT OR REPLACE INTO places(identifier, name, icao, iata, latitude, longitude, source)
        VALUES (?, ?, ?, ?, ?, ?, 'Manual Override')
        """, values: [
            .text(identifier),
            .text(override.name.trimmingCharacters(in: .whitespacesAndNewlines)),
            .text(identifier.count == 4 ? identifier : ""),
            .text(identifier.count == 3 ? identifier : ""),
            .real(override.latitude),
            .real(override.longitude)
        ])
    }

    private func enrichedForSave(_ input: FlightEntry, db: SQLiteConnection) throws -> FlightEntry {
        var flight = input
        flight.entryKind = flight.entryKind == "Simulator" ? "Simulator" : "Flight"
        flight.signatureName = ""
        flight.signatureReference = ""

        let dep = try place(identifier: flight.departure, db: db)
        let arr = try place(identifier: flight.arrival, db: db)
        let airportDB = AirportCoordinateService.shared
        let depAirport = airportDB.coordinate(for: flight.departure)
        let arrAirport = airportDB.coordinate(for: flight.arrival)
        if flight.departureLatitude == nil { flight.departureLatitude = depAirport?.latitude ?? dep?.latitude }
        if flight.departureLongitude == nil { flight.departureLongitude = depAirport?.longitude ?? dep?.longitude }
        if flight.arrivalLatitude == nil { flight.arrivalLatitude = arrAirport?.latitude ?? arr?.latitude }
        if flight.arrivalLongitude == nil { flight.arrivalLongitude = arrAirport?.longitude ?? arr?.longitude }
        if flight.entryKind == "Simulator" {
            flight.departure = ""
            flight.arrival = ""
            flight.route = ""
            flight.distanceNM = 0
            flight.departureLatitude = nil
            flight.departureLongitude = nil
            flight.arrivalLatitude = nil
            flight.arrivalLongitude = nil
            flight.nightMinutes = 0
            flight.picMinutes = 0
            flight.picDayMinutes = 0
            flight.picNightMinutes = 0
            flight.picusMinutes = 0
            flight.picusDayMinutes = 0
            flight.picusNightMinutes = 0
            flight.copilotMinutes = 0
            flight.copilotDayMinutes = 0
            flight.copilotNightMinutes = 0
            flight.dualMinutes = 0
            flight.instructorMinutes = 0
            flight.instrumentMinutes = 0
            flight.crossCountryMinutes = 0
            flight.fstdMinutes = flight.totalMinutes
            flight.pilotFunction = "FSTD"
            flight.pilotFlying = false
            flight.dayTakeoffs = 0
            flight.nightTakeoffs = 0
            flight.totalTakeoffs = 0
            flight.dayLandings = 0
            flight.nightLandings = 0
            flight.totalLandings = 0
        } else if (flight.sourcePK == nil || flight.distanceNM == 0),
           let depLat = flight.departureLatitude,
           let depLon = flight.departureLongitude,
           let arrLat = flight.arrivalLatitude,
           let arrLon = flight.arrivalLongitude {
            flight.distanceNM = FlightMath.distanceNM(fromLat: depLat, fromLon: depLon, toLat: arrLat, toLon: arrLon)
        }
        if flight.entryKind == "Flight",
           (flight.sourcePK == nil || flight.nightMinutes == 0),
           flight.totalMinutes > 0,
           let depLat = flight.departureLatitude,
           let depLon = flight.departureLongitude,
           let arrLat = flight.arrivalLatitude,
           let arrLon = flight.arrivalLongitude {
            flight.nightMinutes = SolarDayNightCalculator.nightMinutes(
                departure: flight.date,
                durationMinutes: flight.totalMinutes,
                departureLatitude: depLat,
                departureLongitude: depLon,
                arrivalLatitude: arrLat,
                arrivalLongitude: arrLon
            )
        }
        if flight.entryKind == "Flight", flight.sourcePK == nil {
            flight.nightMinutes = SolarDayNightCalculator.roundToNearestFiveMinutes(
                flight.nightMinutes,
                maximum: flight.totalMinutes
            )
        }
        if flight.crewNameList.count >= 2 {
            flight.operation = "MP"
        }
        flight.crewRoles = Self.normalizedCrewRoles(flight.crewRoles, names: flight.crewNameList, pilotFunction: flight.pilotFunction)

        if flight.entryKind == "Flight" {
            if flight.instrumentMinutes == 0 { flight.instrumentMinutes = flight.totalMinutes }
            if flight.crossCountryMinutes == 0 { flight.crossCountryMinutes = flight.totalMinutes }
            if flight.pilotFlying {
                flight.picMinutes = 0
                flight.picDayMinutes = 0
                flight.picNightMinutes = 0
                flight.picusMinutes = flight.totalMinutes
                flight.picusNightMinutes = min(flight.totalMinutes, flight.nightMinutes)
                flight.picusDayMinutes = max(0, flight.totalMinutes - flight.picusNightMinutes)
                flight.copilotMinutes = 0
                flight.copilotDayMinutes = 0
                flight.copilotNightMinutes = 0
                flight.pilotFunction = "PICUS"
            } else {
                flight.picMinutes = 0
                flight.picDayMinutes = 0
                flight.picNightMinutes = 0
                flight.picusMinutes = 0
                flight.picusDayMinutes = 0
                flight.picusNightMinutes = 0
                flight.copilotMinutes = flight.totalMinutes
                flight.copilotNightMinutes = min(flight.totalMinutes, flight.nightMinutes)
                flight.copilotDayMinutes = max(0, flight.totalMinutes - flight.copilotNightMinutes)
                flight.pilotFunction = "Co-pilot"
            }
            if flight.pilotFlying {
                if flight.totalTakeoffs == 0 {
                    let departureIsNight = Self.endpointIsNight(
                        date: flight.date,
                        latitude: flight.departureLatitude,
                        longitude: flight.departureLongitude,
                        fallbackNightMinutes: flight.nightMinutes,
                        totalMinutes: flight.totalMinutes
                    )
                    flight.dayTakeoffs = departureIsNight ? 0 : 1
                    flight.nightTakeoffs = departureIsNight ? 1 : 0
                }
                if flight.totalLandings == 0 {
                    let arrivalIsNight = Self.endpointIsNight(
                        date: flight.date.addingTimeInterval(Double(flight.totalMinutes) * 60),
                        latitude: flight.arrivalLatitude,
                        longitude: flight.arrivalLongitude,
                        fallbackNightMinutes: flight.nightMinutes,
                        totalMinutes: flight.totalMinutes
                    )
                    flight.dayLandings = arrivalIsNight ? 0 : 1
                    flight.nightLandings = arrivalIsNight ? 1 : 0
                }
            }
            flight.totalTakeoffs = flight.dayTakeoffs + flight.nightTakeoffs
            flight.totalLandings = flight.dayLandings + flight.nightLandings
            if !Self.hasSectorNumber(flight.remarks) {
                flight.remarks = try Self.prependingSectorNote(to: flight.remarks, nextSector: nextSectorNumber(in: db))
            }
        }
        return flight
    }

    private static func endpointIsNight(
        date: Date,
        latitude: Double?,
        longitude: Double?,
        fallbackNightMinutes: Int,
        totalMinutes: Int
    ) -> Bool {
        guard let latitude, let longitude else {
            return fallbackNightMinutes >= max(1, totalMinutes / 2)
        }
        return SolarDayNightCalculator.isNight(date: date, latitude: latitude, longitude: longitude)
    }

    private func nextSectorNumber(in db: SQLiteConnection) throws -> Int {
        let rows = try db.rows("SELECT remarks FROM flights WHERE remarks LIKE '%Sector %'")
        let maxSector = rows.compactMap { Self.sectorNumber(in: $0["remarks"]?.string ?? "") }.max() ?? 0
        return maxSector + 1
    }

    private func backfillSectorNotes(in db: SQLiteConnection) throws {
        let rows = try db.rows("""
        SELECT id, remarks FROM flights
        WHERE remarks = 'Imported from roster document'
        ORDER BY date ASC, id ASC
        """)
        for row in rows {
            guard let id = row["id"]?.int64 else { continue }
            let remarks = row["remarks"]?.string ?? ""
            guard !Self.hasSectorNumber(remarks) else { continue }
            let updated = try Self.prependingSectorNote(to: remarks, nextSector: nextSectorNumber(in: db))
            try db.execute("UPDATE flights SET remarks = ? WHERE id = ?", values: [.text(updated), .integer(id)])
        }
    }

    private func backfillEntryKindsAndCrewRoles(in db: SQLiteConnection) throws {
        try db.execute("""
        UPDATE flights
        SET entry_kind = 'Simulator'
        WHERE fstd_minutes > 0 AND departure = '' AND arrival = ''
        """)
        let rows = try db.rows("SELECT id, crew_names, pilot_function, crew_roles FROM flights WHERE crew_names != ''")
        for row in rows {
            guard let id = row["id"]?.int64 else { continue }
            let names = FlightEntry.splitCrewNames(row["crew_names"]?.string ?? "")
            let roles = Self.normalizedCrewRoles("", names: names, pilotFunction: row["pilot_function"]?.string ?? "")
            try db.execute("UPDATE flights SET crew_roles = ? WHERE id = ?", values: [.text(roles), .integer(id)])
        }
    }

    private func backfillPilotFunctions(in db: SQLiteConnection) throws {
        try db.execute("""
        UPDATE flights
        SET pilot_function = CASE
            WHEN pic_minutes > 0 THEN 'PIC'
            WHEN picus_minutes > 0 THEN 'PICUS'
            WHEN copilot_minutes > 0 THEN 'Co-pilot'
            WHEN dual_minutes > 0 THEN 'Dual'
            WHEN instructor_minutes > 0 THEN 'Instructor'
            WHEN fstd_minutes > 0 THEN 'FSTD'
            ELSE pilot_function
        END
        WHERE source_pk IS NOT NULL
        """)
    }

    private static func sectorNumber(in remarks: String) -> Int? {
        let pattern = #"\bSector\s+(\d+)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(remarks.startIndex..<remarks.endIndex, in: remarks)
        guard let match = regex.firstMatch(in: remarks, range: range), match.numberOfRanges > 1,
              let swiftRange = Range(match.range(at: 1), in: remarks)
        else { return nil }
        return Int(remarks[swiftRange])
    }

    private static func hasSectorNumber(_ remarks: String) -> Bool {
        sectorNumber(in: remarks) != nil
    }

    private static func prependingSectorNote(to remarks: String, nextSector: Int) throws -> String {
        let trimmed = remarks.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Imported from roster document" else { return "Sector \(nextSector)" }
        return "Sector \(nextSector) (\(trimmed))"
    }

    private static func normalizedCrewRoles(_ text: String, names: [String], pilotFunction: String) -> String {
        var roles = FlightEntry.parseCrewRoles(text)
        if let first = names.first, roles[first] == nil {
            roles[first] = pilotFunction.isEmpty ? "Pilot" : (pilotFunction == "PIC" ? "Captain" : pilotFunction)
        }
        if pilotFunction == "Co-pilot", names.count >= 2 {
            let captain = names[0]
            if roles[captain] == nil || roles[captain] == "Co-pilot" {
                roles[captain] = "Captain"
            }
            let firstOfficer = names[1]
            if roles[firstOfficer] == nil {
                roles[firstOfficer] = "First Officer"
            }
        }
        for name in names where roles[name] == nil {
            roles[name] = "Other crew"
        }
        return FlightEntry.crewRolesText(from: roles, names: names)
    }

    private func place(identifier: String, db: SQLiteConnection) throws -> (latitude: Double?, longitude: Double?)? {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let row = try db.rows("""
        SELECT latitude, longitude FROM places
        WHERE identifier = ? OR icao = ? OR iata = ?
        LIMIT 1
        """, values: [.text(trimmed), .text(trimmed), .text(trimmed)]).first else { return nil }
        return (row["latitude"]?.double, row["longitude"]?.double)
    }

    public func complianceSnapshot() throws -> ComplianceSnapshot {
        let allFlights = try flights()
        var issues: [ComplianceIssue] = []
        for flight in allFlights {
            let flightID = flight.id ?? 0
            let hasLoggableTime = flight.totalMinutes > 0 || flight.fstdMinutes > 0
            let isPureFSTD = flight.fstdMinutes > 0 && flight.fstdMinutes == flight.totalMinutes
            let checks: [(String, String, String, Bool)] = [
                ("Departure", "CAA/EASA format expects a departure place.", "Enter the departure ICAO/IATA code, or mark the entry as simulator if it is FSTD-only.", isPureFSTD || !flight.departure.isEmpty || !flight.route.isEmpty),
                ("Arrival", "CAA/EASA format expects an arrival place.", "Enter the arrival ICAO/IATA code, or mark the entry as simulator if it is FSTD-only.", isPureFSTD || !flight.arrival.isEmpty || !flight.route.isEmpty),
                ("Aircraft", "Aircraft registration or ID is missing.", "Add the aircraft registration, simulator identifier, or other logbook aircraft ID.", !flight.aircraftID.isEmpty),
                ("Aircraft type", "Aircraft type/class should be available for the aircraft column.", "Add the aircraft type or simulator device type used for the entry.", !flight.aircraftType.isEmpty),
                ("Total time", "Total flight time is zero.", "Enter the elapsed sector or simulator time in HH:MM.", hasLoggableTime),
                ("Function", "Pilot function time should show PIC, PICUS, co-pilot, dual, instructor, or FSTD.", "Select the pilot function or simulator mode so the correct CAA column is populated.", !hasLoggableTime || flight.picMinutes + flight.picusMinutes + flight.copilotMinutes + flight.dualMinutes + flight.instructorMinutes + flight.fstdMinutes > 0 || (flight.sourcePK != nil && !flight.pilotFunction.isEmpty)),
                ("Operation", "Single-pilot or multi-pilot operation should be identified.", "Set SP or MP; entries with two or more crew names should be MP.", !flight.operation.isEmpty)
            ]
            for check in checks where !check.3 {
                issues.append(ComplianceIssue(flightID: flightID, date: flight.date, field: check.0, message: check.1, guidance: check.2))
            }
        }
        return ComplianceSnapshot(issues: issues, checkedFlights: allFlights.count)
    }

    public func logTenComparisonSnapshot() throws -> LogTenComparisonSnapshot {
        let sourceURL = comparisonSourceDatabase()
        let source = try SQLiteConnection(path: sourceURL.path, readOnly: true)
        let logTenFlights = try logTenFlightRows(from: source).map(Self.flightFromLogTen(row:))
        let allBlackboxFlights = try flights()
        let importedBlackboxFlights = allBlackboxFlights.filter { $0.sourcePK != nil }
        let blackboxOnlyFlights = allBlackboxFlights.filter { $0.sourcePK == nil }

        let logTenBySourcePK = Dictionary(uniqueKeysWithValues: logTenFlights.compactMap { flight -> (Int64, FlightEntry)? in
            guard let sourcePK = flight.sourcePK else { return nil }
            return (sourcePK, flight)
        })
        let blackboxBySourcePK = Dictionary(uniqueKeysWithValues: importedBlackboxFlights.compactMap { flight -> (Int64, FlightEntry)? in
            guard let sourcePK = flight.sourcePK else { return nil }
            return (sourcePK, flight)
        })
        let logTenKeys = Set(logTenBySourcePK.keys)
        let blackboxKeys = Set(blackboxBySourcePK.keys)
        var issues: [LogTenComparisonIssue] = []

        for sourcePK in logTenKeys.intersection(blackboxKeys).sorted() {
            guard let logTen = logTenBySourcePK[sourcePK], let blackbox = blackboxBySourcePK[sourcePK] else { continue }
            Self.appendComparisonIssues(sourcePK: sourcePK, logTen: logTen, blackbox: blackbox, to: &issues)
        }

        return LogTenComparisonSnapshot(
            sourcePath: sourceURL.path,
            sourceIsLiveLogTen: sourceURL.path == Self.liveLogTenDatabasePath,
            logTen: Self.comparisonSummary(for: logTenFlights),
            blackboxImported: Self.comparisonSummary(for: importedBlackboxFlights),
            blackboxAll: Self.comparisonSummary(for: allBlackboxFlights),
            blackboxOnly: Self.comparisonSummary(for: blackboxOnlyFlights),
            missingInBlackbox: logTenKeys.subtracting(blackboxKeys).count,
            missingInLogTen: blackboxKeys.subtracting(logTenKeys).count,
            issues: Array(issues.prefix(200))
        )
    }

    private func comparisonSourceDatabase() -> URL {
        if
            let db = try? SQLiteConnection(path: paths.workingDatabase.path, readOnly: true),
            let storedPath = try? setting("source_backup", in: db),
            !storedPath.isEmpty,
            FileManager.default.fileExists(atPath: storedPath)
        {
            return URL(fileURLWithPath: storedPath)
        }
        if paths == .applicationSupport {
            let liveURL = URL(fileURLWithPath: Self.liveLogTenDatabasePath)
            if FileManager.default.fileExists(atPath: liveURL.path) {
                return liveURL
            }
        }
        return paths.sourceLogTenDatabase
    }

    private func resolvedLogTenSource(in db: SQLiteConnection) throws -> URL {
        if FileManager.default.fileExists(atPath: paths.sourceLogTenDatabase.path) {
            return paths.sourceLogTenDatabase
        }
        let storedPath = try setting("source_backup", in: db)
        if !storedPath.isEmpty, FileManager.default.fileExists(atPath: storedPath) {
            return URL(fileURLWithPath: storedPath)
        }
        if paths == .applicationSupport {
            let liveURL = URL(fileURLWithPath: Self.liveLogTenDatabasePath)
            if FileManager.default.fileExists(atPath: liveURL.path) {
                return liveURL
            }
        }
        throw NSError(
            domain: "BlackboxImport",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "No readable LogTen Pro source database was found."]
        )
    }

    private static var liveLogTenDatabasePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.coradine.LogTenPro6/Data/Documents/LogTenProData/LogTenCoreDataStore.sql")
            .path
    }

    private static func backupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

    private static func comparisonSummary(for flights: [FlightEntry]) -> LogTenComparisonSummary {
        LogTenComparisonSummary(
            flightCount: flights.count,
            totalMinutes: flights.reduce(0) { $0 + $1.flyingMinutes },
            picMinutes: flights.reduce(0) { $0 + $1.picMinutes },
            copilotMinutes: flights.reduce(0) { $0 + $1.copilotMinutes },
            copilotDayMinutes: flights.reduce(0) { $0 + $1.copilotDayMinutes },
            copilotNightMinutes: flights.reduce(0) { $0 + $1.copilotNightMinutes },
            nightMinutes: flights.reduce(0) { $0 + $1.nightMinutes },
            landings: flights.reduce(0) { $0 + $1.totalLandings },
            distanceNM: flights.reduce(0) { $0 + $1.distanceNM }
        )
    }

    private static func appendComparisonIssues(
        sourcePK: Int64,
        logTen: FlightEntry,
        blackbox: FlightEntry,
        to issues: inout [LogTenComparisonIssue]
    ) {
        let route = logTen.routeDisplay.isEmpty ? blackbox.routeDisplay : logTen.routeDisplay
        func add(_ field: String, _ logTenValue: String, _ blackboxValue: String) {
            guard logTenValue != blackboxValue else { return }
            issues.append(LogTenComparisonIssue(
                sourcePK: sourcePK,
                date: logTen.date,
                route: route,
                field: field,
                logTenValue: logTenValue,
                blackboxValue: blackboxValue
            ))
        }
        add("Date", LogbookFormatters.isoFormatter.string(from: logTen.date), LogbookFormatters.isoFormatter.string(from: blackbox.date))
        add("Departure", logTen.departure, blackbox.departure)
        add("Arrival", logTen.arrival, blackbox.arrival)
        add("Aircraft", logTen.aircraftID, blackbox.aircraftID)
        add("Type", logTen.aircraftType, blackbox.aircraftType)
        add("Function", logTen.pilotFunction, blackbox.pilotFunction)
        add("Total", LogbookFormatters.hours(logTen.totalMinutes), LogbookFormatters.hours(blackbox.totalMinutes))
        add("PIC", LogbookFormatters.hours(logTen.picMinutes), LogbookFormatters.hours(blackbox.picMinutes))
        add("PICUS", LogbookFormatters.hours(logTen.picusMinutes), LogbookFormatters.hours(blackbox.picusMinutes))
        add("PICUS day", LogbookFormatters.hours(logTen.picusDayMinutes), LogbookFormatters.hours(blackbox.picusDayMinutes))
        add("PICUS night", LogbookFormatters.hours(logTen.picusNightMinutes), LogbookFormatters.hours(blackbox.picusNightMinutes))
        add("Co-pilot", LogbookFormatters.hours(logTen.copilotMinutes), LogbookFormatters.hours(blackbox.copilotMinutes))
        add("Co-pilot day", LogbookFormatters.hours(logTen.copilotDayMinutes), LogbookFormatters.hours(blackbox.copilotDayMinutes))
        add("Co-pilot night", LogbookFormatters.hours(logTen.copilotNightMinutes), LogbookFormatters.hours(blackbox.copilotNightMinutes))
        add("Night", LogbookFormatters.hours(logTen.nightMinutes), LogbookFormatters.hours(blackbox.nightMinutes))
        add("Landings", "\(logTen.totalLandings)", "\(blackbox.totalLandings)")
        if abs(logTen.distanceNM - blackbox.distanceNM) > 0.5 {
            add("Distance", String(format: "%.1f NM", logTen.distanceNM), String(format: "%.1f NM", blackbox.distanceNM))
        }
        add("Crew", logTen.crewNames, blackbox.crewNames)
    }

    private func flightCount(in db: SQLiteConnection) throws -> Int {
        try db.rows("SELECT COUNT(*) AS count FROM flights").first?["count"]?.int ?? 0
    }

    private func setting(_ key: String, in db: SQLiteConnection) throws -> String {
        try db.rows("SELECT value FROM settings WHERE key = ?", values: [.text(key)]).first?["value"]?.string ?? ""
    }

    private func importLogTenBackup(into destination: SQLiteConnection) throws {
        let source = try SQLiteConnection(path: try resolvedLogTenSource(in: destination).path, readOnly: true)
        let sourceRows = try logTenFlightRows(from: source)
        try destination.transaction {
            try destination.execute("DELETE FROM flights")
            try importPlaces(from: source, into: destination)
            for row in sourceRows {
                let flight = Self.flightFromLogTen(row: row)
                _ = try saveImported(flight, in: destination)
            }
            try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('source_backup', ?)", values: [.text(paths.sourceLogTenDatabase.path)])
            try destination.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('imported_at', ?)", values: [.text(LogbookFormatters.isoFormatter.string(from: Date()))])
        }
    }

    private func enrichFromLogTenBackup(into destination: SQLiteConnection) throws {
        let source = try SQLiteConnection(path: try resolvedLogTenSource(in: destination).path, readOnly: true)
        let sourceRows = try logTenFlightRows(from: source)
        try destination.transaction {
            try importPlaces(from: source, into: destination)
            for row in sourceRows {
                let flight = Self.flightFromLogTen(row: row)
                guard let sourcePK = flight.sourcePK else { continue }
                try destination.execute("""
                UPDATE flights SET
                  departure = CASE WHEN departure = '' THEN ? ELSE departure END,
                  arrival = CASE WHEN arrival = '' THEN ? ELSE arrival END,
                  route = CASE WHEN route = '' THEN ? ELSE route END,
                          aircraft_type = CASE WHEN aircraft_type = '' THEN ? ELSE aircraft_type END,
                          entry_kind = ?,
                          pic_minutes = ?,
                          pic_day_minutes = ?,
                          pic_night_minutes = ?,
                          picus_minutes = ?,
                          picus_day_minutes = ?,
                          picus_night_minutes = ?,
                          copilot_minutes = ?,
                          copilot_day_minutes = ?,
                          copilot_night_minutes = ?,
                          instrument_minutes = ?,
                          cross_country_minutes = ?,
                          pilot_function = ?,
                          operation = ?,
                  pilot_flying = ?,
                  day_takeoffs = ?,
                  night_takeoffs = ?,
                  total_takeoffs = ?,
                  day_landings = ?,
                  night_landings = ?,
                  total_landings = ?,
                  passenger_count = ?,
                  distance_nm = ?,
                          crew_names = ?,
                          crew_roles = ?,
                  departure_lat = ?,
                  departure_lon = ?,
                  arrival_lat = ?,
                  arrival_lon = ?
                WHERE source_pk = ?
                """, values: [
                            .text(flight.departure), .text(flight.arrival), .text(flight.route), .text(flight.aircraftType),
                            .text(flight.entryKind),
                            .integer(Int64(flight.picMinutes)),
                            .integer(Int64(flight.picDayMinutes)), .integer(Int64(flight.picNightMinutes)), .integer(Int64(flight.picusMinutes)),
                            .integer(Int64(flight.picusDayMinutes)), .integer(Int64(flight.picusNightMinutes)),
                            .integer(Int64(flight.copilotMinutes)),
                            .integer(Int64(flight.copilotDayMinutes)), .integer(Int64(flight.copilotNightMinutes)),
                            .integer(Int64(flight.instrumentMinutes)),
                            .integer(Int64(flight.crossCountryMinutes)),
                            .text(flight.pilotFunction),
                    .text(flight.operation),
                    .integer(flight.pilotFlying ? 1 : 0),
                    .integer(Int64(flight.dayTakeoffs)), .integer(Int64(flight.nightTakeoffs)), .integer(Int64(flight.totalTakeoffs)),
                    .integer(Int64(flight.dayLandings)), .integer(Int64(flight.nightLandings)), .integer(Int64(flight.totalLandings)),
                            .integer(Int64(flight.passengerCount)), .real(flight.distanceNM), .text(flight.crewNames), .text(flight.crewRoles),
                    flight.departureLatitude.map(SQLiteValue.real) ?? .null,
                    flight.departureLongitude.map(SQLiteValue.real) ?? .null,
                    flight.arrivalLatitude.map(SQLiteValue.real) ?? .null,
                    flight.arrivalLongitude.map(SQLiteValue.real) ?? .null,
                    .integer(sourcePK)
                ])
            }
        }
    }

    private func importPlaces(from source: SQLiteConnection, into destination: SQLiteConnection) throws {
        let overrides = try destination.rows("""
        SELECT identifier, name, icao, iata, latitude, longitude, source
        FROM places
        WHERE source = 'Manual Override'
        """)
        try destination.execute("DELETE FROM places")
        let rows = try source.rows("""
        SELECT COALESCE(NULLIF(ZPLACE_IDENTIFIER, ''), NULLIF(ZPLACE_ICAOID, ''), NULLIF(ZPLACE_IATAID, '')) AS identifier,
               COALESCE(ZPLACE_NAME, '') AS name,
               COALESCE(ZPLACE_ICAOID, '') AS icao,
               COALESCE(ZPLACE_IATAID, '') AS iata,
               ZPLACE_LAT AS latitude,
               ZPLACE_LON AS longitude
        FROM ZPLACE
        WHERE COALESCE(NULLIF(ZPLACE_IDENTIFIER, ''), NULLIF(ZPLACE_ICAOID, ''), NULLIF(ZPLACE_IATAID, '')) IS NOT NULL
        """)
        let airportDB = AirportCoordinateService.shared
        for row in rows {
            let identifier = row["identifier"]?.string ?? ""
            let icao = row["icao"]?.string ?? ""
            let iata = row["iata"]?.string ?? ""
            let airport = airportDB.airport(for: identifier) ?? airportDB.airport(for: icao) ?? airportDB.airport(for: iata)
            try destination.execute("""
            INSERT OR REPLACE INTO places(identifier, name, icao, iata, latitude, longitude, source)
            VALUES (?, ?, ?, ?, ?, ?, 'LogTen')
            """, values: [
                .text(identifier),
                .text((row["name"]?.string ?? "").isEmpty ? airport?.name ?? "" : row["name"]?.string ?? ""),
                .text(icao),
                .text(iata),
                airport.map { SQLiteValue.real($0.latitude) } ?? row["latitude"]?.double.map(SQLiteValue.real) ?? .null,
                airport.map { SQLiteValue.real($0.longitude) } ?? row["longitude"]?.double.map(SQLiteValue.real) ?? .null
            ])
        }
        for row in overrides {
            guard let identifier = row["identifier"]?.string else { continue }
            try destination.execute("""
            INSERT OR REPLACE INTO places(identifier, name, icao, iata, latitude, longitude, source)
            VALUES (?, ?, ?, ?, ?, ?, 'Manual Override')
            """, values: [
                .text(identifier),
                .text(row["name"]?.string ?? ""),
                .text(row["icao"]?.string ?? ""),
                .text(row["iata"]?.string ?? ""),
                row["latitude"]?.double.map(SQLiteValue.real) ?? .null,
                row["longitude"]?.double.map(SQLiteValue.real) ?? .null
            ])
        }
    }

    private func logTenFlightRows(from source: SQLiteConnection) throws -> [[String: SQLiteValue]] {
        let sourceRows = try source.rows("""
        SELECT f.Z_PK AS source_pk,
               f.ZFLIGHT_FLIGHTDATE AS flight_date,
               COALESCE(NULLIF(p1.ZPLACE_IDENTIFIER, ''), NULLIF(p1.ZPLACE_ICAOID, ''), NULLIF(p1.ZPLACE_IATAID, '')) AS departure,
               COALESCE(NULLIF(p2.ZPLACE_IDENTIFIER, ''), NULLIF(p2.ZPLACE_ICAOID, ''), NULLIF(p2.ZPLACE_IATAID, '')) AS arrival,
               COALESCE(f.ZFLIGHT_ROUTE, '') AS route,
               COALESCE(a.ZAIRCRAFT_AIRCRAFTID, '') AS aircraft_id,
               COALESCE(t.ZAIRCRAFTTYPE_TYPE, t.ZAIRCRAFTTYPE_MODEL, '') AS aircraft_type,
               COALESCE(f.ZFLIGHT_FLIGHTNUMBER, '') AS flight_number,
               COALESCE(f.ZFLIGHT_MULTIPILOT, 0) AS multipilot,
                       COALESCE(f.ZFLIGHT_TOTALTIME, 0) AS total_minutes,
                       COALESCE(f.ZFLIGHT_PIC, 0) AS pic_minutes,
                       MAX(COALESCE(f.ZFLIGHT_PIC, 0) - MIN(COALESCE(f.ZFLIGHT_PIC, 0), COALESCE(f.ZFLIGHT_PICNIGHT, 0)), 0) AS pic_day_minutes,
                       MIN(COALESCE(f.ZFLIGHT_PIC, 0), COALESCE(f.ZFLIGHT_PICNIGHT, 0)) AS pic_night_minutes,
                       COALESCE(f.ZFLIGHT_P1US, 0) AS picus_minutes,
                       COALESCE(f.ZFLIGHT_CUSTOMTIME4, 0) AS picus_day_minutes,
                       CASE
                           WHEN COALESCE(f.ZFLIGHT_P1US, 0) > 0
                            AND COALESCE(f.ZFLIGHT_P1US, 0) = COALESCE(f.ZFLIGHT_CUSTOMTIME4, 0)
                            AND COALESCE(f.ZFLIGHT_P1USNIGHT, 0) = COALESCE(f.ZFLIGHT_TOTALTIME, 0)
                           THEN 0
                           ELSE COALESCE(f.ZFLIGHT_P1USNIGHT, 0)
                       END AS picus_night_minutes,
                       COALESCE(f.ZFLIGHT_CUSTOMTIME3, 0) AS copilot_minutes,
                       0 AS copilot_day_minutes,
                       0 AS copilot_night_minutes,
               COALESCE(f.ZFLIGHT_DUALRECEIVED, 0) AS dual_minutes,
               COALESCE(f.ZFLIGHT_SFI, 0) + COALESCE(f.ZFLIGHT_DUALGIVEN, 0) AS instructor_minutes,
                       COALESCE(f.ZFLIGHT_NIGHT, 0) AS night_minutes,
                       COALESCE(f.ZFLIGHT_CUSTOMTIME2, 0) AS instrument_minutes,
                       COALESCE(f.ZFLIGHT_CROSSCOUNTRY, 0) AS cross_country_minutes,
                       COALESCE(f.ZFLIGHT_SIMULATOR, 0) AS fstd_minutes,
               COALESCE(f.ZFLIGHT_PILOTFLYINGCAPACITY, 0) AS pilot_flying,
               COALESCE(f.ZFLIGHT_DAYTAKEOFFS, 0) AS day_takeoffs,
               COALESCE(f.ZFLIGHT_NIGHTTAKEOFFS, 0) AS night_takeoffs,
               COALESCE(f.ZFLIGHT_TOTALTAKEOFFS, 0) AS total_takeoffs,
               COALESCE(f.ZFLIGHT_DAYLANDINGS, 0) AS day_landings,
               COALESCE(f.ZFLIGHT_NIGHTLANDINGS, 0) AS night_landings,
               COALESCE(f.ZFLIGHT_TOTALLANDINGS, 0) AS total_landings,
               COALESCE(f.ZFLIGHT_PAXCOUNT, 0) AS passenger_count,
               COALESCE(f.ZFLIGHT_DISTANCE, 0) AS distance_nm,
               p1.ZPLACE_LAT AS departure_lat,
               p1.ZPLACE_LON AS departure_lon,
               p2.ZPLACE_LAT AS arrival_lat,
               p2.ZPLACE_LON AS arrival_lon,
               COALESCE((
                   SELECT group_concat(name, ' | ') FROM (
                       SELECT DISTINCT name FROM (
                           SELECT CASE
                               WHEN TRIM(COALESCE(p.ZPERSON_FIRSTNAME, '') || ' ' || COALESCE(p.ZPERSON_LASTNAME, '')) != ''
                               THEN TRIM(COALESCE(p.ZPERSON_FIRSTNAME, '') || ' ' || COALESCE(p.ZPERSON_LASTNAME, ''))
                               WHEN INSTR(COALESCE(NULLIF(p.ZPERSON_FULLNAME, ''), p.ZPERSON_NAME, ''), ',') > 0
                               THEN TRIM(SUBSTR(COALESCE(NULLIF(p.ZPERSON_FULLNAME, ''), p.ZPERSON_NAME, ''), INSTR(COALESCE(NULLIF(p.ZPERSON_FULLNAME, ''), p.ZPERSON_NAME, ''), ',') + 1) || ' ' || SUBSTR(COALESCE(NULLIF(p.ZPERSON_FULLNAME, ''), p.ZPERSON_NAME, ''), 1, INSTR(COALESCE(NULLIF(p.ZPERSON_FULLNAME, ''), p.ZPERSON_NAME, ''), ',') - 1))
                               ELSE COALESCE(NULLIF(p.ZPERSON_FULLNAME, ''), NULLIF(p.ZPERSON_NAME, ''), '')
                           END AS name
                           FROM ZFLIGHTCREW c
                           JOIN ZPERSON p ON p.Z_PK IN (
                               c.ZFLIGHTCREW_PIC, c.ZFLIGHTCREW_SIC, c.ZFLIGHTCREW_COMMANDER, c.ZFLIGHTCREW_INSTRUCTOR,
                               c.ZFLIGHTCREW_FLIGHTENGINEER, c.ZFLIGHTCREW_PURSER, c.ZFLIGHTCREW_RELIEF1, c.ZFLIGHTCREW_RELIEF2,
                               c.ZFLIGHTCREW_RELIEF3, c.ZFLIGHTCREW_RELIEF4, c.ZFLIGHTCREW_STUDENT
                           )
                           WHERE c.ZFLIGHTCREW_FLIGHT = f.Z_PK
                       )
                       WHERE name IS NOT NULL AND name != ''
                       ORDER BY name
                   )
               ), '') AS crew_names,
               COALESCE((
                   SELECT COUNT(DISTINCT p.Z_PK)
                   FROM ZFLIGHTCREW c
                   JOIN ZPERSON p ON p.Z_PK IN (
                       c.ZFLIGHTCREW_PIC, c.ZFLIGHTCREW_SIC, c.ZFLIGHTCREW_COMMANDER, c.ZFLIGHTCREW_INSTRUCTOR,
                       c.ZFLIGHTCREW_FLIGHTENGINEER, c.ZFLIGHTCREW_PURSER, c.ZFLIGHTCREW_RELIEF1, c.ZFLIGHTCREW_RELIEF2,
                       c.ZFLIGHTCREW_RELIEF3, c.ZFLIGHTCREW_RELIEF4, c.ZFLIGHTCREW_STUDENT
                   )
                   WHERE c.ZFLIGHTCREW_FLIGHT = f.Z_PK
               ), 0) AS crew_count,
               COALESCE(f.ZFLIGHT_REMARKS, '') AS remarks
        FROM ZFLIGHT f
        LEFT JOIN ZAIRCRAFT a ON a.Z_PK = f.ZFLIGHT_AIRCRAFT
        LEFT JOIN ZAIRCRAFTTYPE t ON t.Z_PK = COALESCE(f.ZFLIGHT_AIRCRAFTTYPE, a.ZAIRCRAFT_AIRCRAFTTYPE)
        LEFT JOIN ZPLACE p1 ON p1.Z_PK = f.ZFLIGHT_FROMPLACE
        LEFT JOIN ZPLACE p2 ON p2.Z_PK = f.ZFLIGHT_TOPLACE
        ORDER BY f.ZFLIGHT_FLIGHTDATE
        """)
        return sourceRows
    }

    private func saveImported(_ flight: FlightEntry, in db: SQLiteConnection) throws -> Int64 {
        try db.execute("""
        INSERT INTO flights (
                  source_pk, date, departure, arrival, route, aircraft_id, aircraft_type, flight_number, operation, entry_kind, pilot_function,
                  total_minutes, pic_minutes, pic_day_minutes, pic_night_minutes, picus_minutes, picus_day_minutes, picus_night_minutes,
                  copilot_minutes, copilot_day_minutes, copilot_night_minutes,
                  dual_minutes, instructor_minutes, night_minutes, instrument_minutes, cross_country_minutes, fstd_minutes,
                  pilot_flying, day_takeoffs, night_takeoffs, total_takeoffs,
                  day_landings, night_landings, total_landings, passenger_count, distance_nm, crew_names,
                  crew_roles, departure_lat, departure_lon, arrival_lat, arrival_lon, remarks, signature_name, signature_reference, locked, modified_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, values: [
            flight.sourcePK.map(SQLiteValue.integer) ?? .null,
            .text(LogbookFormatters.isoFormatter.string(from: flight.date)),
            .text(flight.departure), .text(flight.arrival), .text(flight.route),
            .text(flight.aircraftID), .text(flight.aircraftType), .text(flight.flightNumber),
                    .text(flight.operation), .text(flight.entryKind), .text(flight.pilotFunction),
                    .integer(Int64(flight.totalMinutes)), .integer(Int64(flight.picMinutes)),
                    .integer(Int64(flight.picDayMinutes)), .integer(Int64(flight.picNightMinutes)), .integer(Int64(flight.picusMinutes)),
                    .integer(Int64(flight.picusDayMinutes)), .integer(Int64(flight.picusNightMinutes)),
                    .integer(Int64(flight.copilotMinutes)),
                    .integer(Int64(flight.copilotDayMinutes)), .integer(Int64(flight.copilotNightMinutes)),
                    .integer(Int64(flight.dualMinutes)), .integer(Int64(flight.instructorMinutes)), .integer(Int64(flight.nightMinutes)),
                    .integer(Int64(flight.instrumentMinutes)), .integer(Int64(flight.crossCountryMinutes)), .integer(Int64(flight.fstdMinutes)),
            .integer(flight.pilotFlying ? 1 : 0),
            .integer(Int64(flight.dayTakeoffs)), .integer(Int64(flight.nightTakeoffs)), .integer(Int64(flight.totalTakeoffs)),
            .integer(Int64(flight.dayLandings)), .integer(Int64(flight.nightLandings)), .integer(Int64(flight.totalLandings)),
                    .integer(Int64(flight.passengerCount)), .real(flight.distanceNM), .text(flight.crewNames), .text(flight.crewRoles),
            flight.departureLatitude.map(SQLiteValue.real) ?? .null,
            flight.departureLongitude.map(SQLiteValue.real) ?? .null,
            flight.arrivalLatitude.map(SQLiteValue.real) ?? .null,
            flight.arrivalLongitude.map(SQLiteValue.real) ?? .null,
            .text(flight.remarks),
            .text(""),
            .text(""),
            .integer(0),
            .text(LogbookFormatters.isoFormatter.string(from: Date()))
        ])
        return db.lastInsertRowID()
    }

    private static func flightFromLogTen(row: [String: SQLiteValue]) -> FlightEntry {
        let total = row["total_minutes"]?.int ?? 0
        let pic = row["pic_minutes"]?.int ?? 0
        var picDay = row["pic_day_minutes"]?.int ?? 0
        var picNight = row["pic_night_minutes"]?.int ?? 0
        let copilot = row["copilot_minutes"]?.int ?? 0
        let picus = row["picus_minutes"]?.int ?? 0
        let picusDay = row["picus_day_minutes"]?.int ?? 0
        let picusNight = row["picus_night_minutes"]?.int ?? 0
        let dual = row["dual_minutes"]?.int ?? 0
        let instructor = row["instructor_minutes"]?.int ?? 0
        let fstd = row["fstd_minutes"]?.int ?? 0
        let isSimulator = fstd > 0 && (row["departure"]?.string ?? "").isEmpty && (row["arrival"]?.string ?? "").isEmpty
        let crewNames = row["crew_names"]?.string ?? ""
        let crewCount = max(row["crew_count"]?.int ?? 0, FlightEntry.splitCrewNames(crewNames).count)
        let isMultiPilot = (row["multipilot"]?.int ?? 0) > 0 || crewCount >= 2
        let nightMinutes = row["night_minutes"]?.int ?? 0
        if pic > 0 && picDay == 0 && picNight == 0 {
            picNight = min(pic, nightMinutes)
            picDay = max(0, pic - picNight)
        }
        var copilotDay = row["copilot_day_minutes"]?.int ?? 0
        var copilotNight = row["copilot_night_minutes"]?.int ?? 0
        let pilotFunction: String
        if pic > 0 { pilotFunction = "PIC" }
        else if picus > 0 { pilotFunction = "PICUS" }
        else if copilot > 0 { pilotFunction = "Co-pilot" }
        else if dual > 0 { pilotFunction = "Dual" }
        else if instructor > 0 { pilotFunction = "Instructor" }
        else if fstd > 0 { pilotFunction = "FSTD" }
        else if total > 0 { pilotFunction = isMultiPilot ? "Co-pilot" : "PIC" }
        else { pilotFunction = "" }

        let departure = row["departure"]?.string ?? ""
        let arrival = row["arrival"]?.string ?? ""
        let airportDB = AirportCoordinateService.shared
        let depAirport = airportDB.coordinate(for: departure)
        let arrAirport = airportDB.coordinate(for: arrival)
        let depLat = depAirport?.latitude ?? row["departure_lat"]?.double
        let depLon = depAirport?.longitude ?? row["departure_lon"]?.double
        let arrLat = arrAirport?.latitude ?? row["arrival_lat"]?.double
        let arrLon = arrAirport?.longitude ?? row["arrival_lon"]?.double
        let flightDate = Date(timeIntervalSinceReferenceDate: row["flight_date"]?.double ?? 0)
        if copilot > 0 && copilotDay == 0 && copilotNight == 0 {
            copilotNight = min(copilot, nightMinutes)
            copilotDay = max(0, copilot - copilotNight)
        }
        let pilotFlying = (row["pilot_flying"]?.int ?? 0) > 0
        var dayTakeoffs = row["day_takeoffs"]?.int ?? 0
        var nightTakeoffs = row["night_takeoffs"]?.int ?? 0
        var totalTakeoffs = row["total_takeoffs"]?.int ?? 0
        var dayLandings = row["day_landings"]?.int ?? 0
        var nightLandings = row["night_landings"]?.int ?? 0
        var totalLandings = row["total_landings"]?.int ?? 0
        if totalTakeoffs == 0 { totalTakeoffs = dayTakeoffs + nightTakeoffs }
        if totalLandings == 0 { totalLandings = dayLandings + nightLandings }
        if pilotFlying {
            if totalTakeoffs == 0 {
                if nightMinutes >= max(1, total / 2) { nightTakeoffs = 1 } else { dayTakeoffs = 1 }
                totalTakeoffs = dayTakeoffs + nightTakeoffs
            }
            if totalLandings == 0 {
                if nightMinutes >= max(1, total / 2) { nightLandings = 1 } else { dayLandings = 1 }
                totalLandings = dayLandings + nightLandings
            }
        }

        return FlightEntry(
            sourcePK: row["source_pk"]?.int64,
            date: flightDate,
            departure: departure,
            arrival: arrival,
            route: row["route"]?.string ?? "",
            aircraftID: row["aircraft_id"]?.string ?? "",
            aircraftType: row["aircraft_type"]?.string ?? "",
            flightNumber: row["flight_number"]?.string ?? "",
            operation: isMultiPilot ? "MP" : "SP",
            entryKind: isSimulator ? "Simulator" : "Flight",
            pilotFunction: pilotFunction,
            totalMinutes: total,
            picMinutes: pic,
            picDayMinutes: picDay,
            picNightMinutes: picNight,
            picusMinutes: picus,
            picusDayMinutes: picusDay,
            picusNightMinutes: picusNight,
            copilotMinutes: copilot,
            copilotDayMinutes: copilotDay,
            copilotNightMinutes: copilotNight,
            dualMinutes: dual,
            instructorMinutes: instructor,
            nightMinutes: nightMinutes,
            instrumentMinutes: row["instrument_minutes"]?.int ?? 0,
            crossCountryMinutes: row["cross_country_minutes"]?.int ?? 0,
            fstdMinutes: fstd,
            pilotFlying: pilotFlying,
            dayTakeoffs: dayTakeoffs,
            nightTakeoffs: nightTakeoffs,
            totalTakeoffs: totalTakeoffs,
            dayLandings: dayLandings,
            nightLandings: nightLandings,
            totalLandings: totalLandings,
            passengerCount: row["passenger_count"]?.int ?? 0,
            distanceNM: row["distance_nm"]?.double ?? 0,
            crewNames: crewNames,
            crewRoles: normalizedCrewRoles("", names: FlightEntry.splitCrewNames(crewNames), pilotFunction: pilotFunction),
            departureLatitude: depLat,
            departureLongitude: depLon,
            arrivalLatitude: arrLat,
            arrivalLongitude: arrLon,
            remarks: row["remarks"]?.string ?? ""
        )
    }

    private static func flight(from row: [String: SQLiteValue]) -> FlightEntry {
        FlightEntry(
            id: row["id"]?.int64,
            sourcePK: row["source_pk"]?.int64,
            date: date(from: row["date"]?.string ?? "") ?? Date(),
            departure: row["departure"]?.string ?? "",
            arrival: row["arrival"]?.string ?? "",
            route: row["route"]?.string ?? "",
            aircraftID: row["aircraft_id"]?.string ?? "",
            aircraftType: row["aircraft_type"]?.string ?? "",
            flightNumber: row["flight_number"]?.string ?? "",
            operation: row["operation"]?.string ?? "",
            entryKind: row["entry_kind"]?.string ?? "Flight",
            pilotFunction: row["pilot_function"]?.string ?? "",
            totalMinutes: row["total_minutes"]?.int ?? 0,
            picMinutes: row["pic_minutes"]?.int ?? 0,
            picDayMinutes: row["pic_day_minutes"]?.int ?? 0,
            picNightMinutes: row["pic_night_minutes"]?.int ?? 0,
            picusMinutes: row["picus_minutes"]?.int ?? 0,
            picusDayMinutes: row["picus_day_minutes"]?.int ?? 0,
            picusNightMinutes: row["picus_night_minutes"]?.int ?? 0,
            copilotMinutes: row["copilot_minutes"]?.int ?? 0,
            copilotDayMinutes: row["copilot_day_minutes"]?.int ?? 0,
            copilotNightMinutes: row["copilot_night_minutes"]?.int ?? 0,
            dualMinutes: row["dual_minutes"]?.int ?? 0,
            instructorMinutes: row["instructor_minutes"]?.int ?? 0,
            nightMinutes: row["night_minutes"]?.int ?? 0,
            instrumentMinutes: row["instrument_minutes"]?.int ?? 0,
            crossCountryMinutes: row["cross_country_minutes"]?.int ?? 0,
            fstdMinutes: row["fstd_minutes"]?.int ?? 0,
            pilotFlying: (row["pilot_flying"]?.int ?? 0) != 0,
            dayTakeoffs: row["day_takeoffs"]?.int ?? 0,
            nightTakeoffs: row["night_takeoffs"]?.int ?? 0,
            totalTakeoffs: row["total_takeoffs"]?.int ?? 0,
            dayLandings: row["day_landings"]?.int ?? 0,
            nightLandings: row["night_landings"]?.int ?? 0,
            totalLandings: row["total_landings"]?.int ?? 0,
            passengerCount: row["passenger_count"]?.int ?? 0,
            distanceNM: row["distance_nm"]?.double ?? 0,
            crewNames: row["crew_names"]?.string ?? "",
            crewRoles: row["crew_roles"]?.string ?? "",
            departureLatitude: row["departure_lat"]?.double,
            departureLongitude: row["departure_lon"]?.double,
            arrivalLatitude: row["arrival_lat"]?.double,
            arrivalLongitude: row["arrival_lon"]?.double,
            remarks: row["remarks"]?.string ?? "",
            signatureName: row["signature_name"]?.string ?? "",
            signatureReference: row["signature_reference"]?.string ?? "",
            locked: (row["locked"]?.int ?? 0) != 0
        )
    }

    private static func date(from text: String) -> Date? {
        LogbookFormatters.isoFormatter.date(from: text)
    }
}
