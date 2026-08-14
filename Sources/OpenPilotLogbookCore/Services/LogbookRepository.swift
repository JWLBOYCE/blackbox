import Foundation
import CryptoKit

public final class LogbookRepository {
    public static let currentSchemaVersion = 4
    public let paths: LogbookPaths
    private let allowsLiveLogTenDiscovery: Bool

    public init(paths: LogbookPaths = .applicationSupport, allowsLiveLogTenDiscovery: Bool = false) {
        self.paths = paths
        self.allowsLiveLogTenDiscovery = allowsLiveLogTenDiscovery
    }

    /// Opens an intent-writing connection only after a read-only schema gate.
    /// This prevents an ordinary Save/Finalise/Trash action from becoming an
    /// unreviewed migration if bootstrap was accidentally skipped.
    private func currentDatabaseForIntentWrite() throws -> SQLiteConnection {
        guard FileManager.default.fileExists(atPath: paths.workingDatabase.path) else {
            throw LogbookRepositoryError.invalidState("Create the Blackbox data store before saving records.")
        }
        let version = try schemaVersion()
        if version < Self.currentSchemaVersion {
            throw LogbookRepositoryError.upgradeRequired(try upgradePreflight())
        }
        guard version == Self.currentSchemaVersion else {
            throw LogbookRepositoryError.invalidState("This database uses schema \(version), which is newer than this Blackbox build supports.")
        }
        return try SQLiteConnection(path: paths.workingDatabase.path)
    }

    public func bootstrapIfNeeded(allowUpgrade: Bool = false) throws {
        let needsImport = !FileManager.default.fileExists(atPath: paths.workingDatabase.path)
        if !needsImport {
            let version = try schemaVersion()
            guard version <= Self.currentSchemaVersion else {
                throw LogbookRepositoryError.invalidState("This database uses schema \(version), which is newer than this Blackbox build supports.")
            }
            if version < Self.currentSchemaVersion {
                let preflight = try upgradePreflight()
                if !allowUpgrade {
                    throw LogbookRepositoryError.upgradeRequired(preflight)
                }
                _ = try backUpAndUpgrade(using: preflight)
            }
        }
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try createSchema(in: db)
        if needsImport {
            try db.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('created_without_implicit_import', 'true')")
        }
    }

    private func createSchema(in db: SQLiteConnection) throws {
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
            record_state TEXT NOT NULL DEFAULT 'draft',
            amends_flight_id INTEGER,
            superseded_by_flight_id INTEGER,
            modified_at TEXT NOT NULL
        )
        """)
        try addCurrentFlightColumnsIfNeeded(in: db)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_date ON flights(date)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_aircraft ON flights(aircraft_id)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_departure ON flights(departure)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_arrival ON flights(arrival)")
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flights_state ON flights(record_state)")
        try db.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_flights_source_pk ON flights(source_pk) WHERE source_pk IS NOT NULL")
        try createAmendmentInvariant(in: db)
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
        try db.execute("""
        CREATE TABLE IF NOT EXISTS flight_revisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            flight_id INTEGER NOT NULL,
            action TEXT NOT NULL,
            origin TEXT NOT NULL,
            operation_batch_id TEXT,
            before_json TEXT,
            after_json TEXT,
            created_at TEXT NOT NULL
        )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flight_revisions_flight ON flight_revisions(flight_id, id)")
        try db.execute("""
        CREATE TABLE IF NOT EXISTS operation_batches (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            summary TEXT NOT NULL DEFAULT '',
            backup_path TEXT,
            created_at TEXT NOT NULL,
            completed_at TEXT,
            affected_count INTEGER NOT NULL DEFAULT 0,
            before_total_minutes INTEGER NOT NULL DEFAULT 0,
            after_total_minutes INTEGER NOT NULL DEFAULT 0,
            verification_json TEXT,
            failure_stage TEXT,
            recovery_outcome TEXT,
            artifact_urls_json TEXT
        )
        """)
        try addOperationMetadataColumns(in: db)
        try db.execute("PRAGMA user_version = \(Self.currentSchemaVersion)")
    }

    private func addColumnIfNeeded(_ table: String, name: String, definition: String, in db: SQLiteConnection) throws {
        let columns = try db.rows("PRAGMA table_info(\(table))").compactMap { $0["name"]?.string }
        if !columns.contains(name) {
            try db.execute("ALTER TABLE \(table) ADD COLUMN \(name) \(definition)")
        }
    }

    /// Adds every column used by current persistence without updating any
    /// pre-existing flight value. SQLite fills only newly introduced columns
    /// with their declared neutral defaults.
    private func addCurrentFlightColumnsIfNeeded(in db: SQLiteConnection) throws {
        let definitions: [(String, String)] = [
            ("source_pk", "INTEGER"),
            ("date", "TEXT NOT NULL DEFAULT ''"),
            ("departure", "TEXT NOT NULL DEFAULT ''"),
            ("arrival", "TEXT NOT NULL DEFAULT ''"),
            ("route", "TEXT NOT NULL DEFAULT ''"),
            ("aircraft_id", "TEXT NOT NULL DEFAULT ''"),
            ("aircraft_type", "TEXT NOT NULL DEFAULT ''"),
            ("flight_number", "TEXT NOT NULL DEFAULT ''"),
            ("operation", "TEXT NOT NULL DEFAULT ''"),
            ("entry_kind", "TEXT NOT NULL DEFAULT 'Flight'"),
            ("pilot_function", "TEXT NOT NULL DEFAULT ''"),
            ("total_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("pic_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("pic_day_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("pic_night_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("picus_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("picus_day_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("picus_night_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("copilot_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("copilot_day_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("copilot_night_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("dual_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("instructor_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("night_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("instrument_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("cross_country_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("fstd_minutes", "INTEGER NOT NULL DEFAULT 0"),
            ("pilot_flying", "INTEGER NOT NULL DEFAULT 0"),
            ("day_takeoffs", "INTEGER NOT NULL DEFAULT 0"),
            ("night_takeoffs", "INTEGER NOT NULL DEFAULT 0"),
            ("total_takeoffs", "INTEGER NOT NULL DEFAULT 0"),
            ("day_landings", "INTEGER NOT NULL DEFAULT 0"),
            ("night_landings", "INTEGER NOT NULL DEFAULT 0"),
            ("total_landings", "INTEGER NOT NULL DEFAULT 0"),
            ("passenger_count", "INTEGER NOT NULL DEFAULT 0"),
            ("distance_nm", "REAL NOT NULL DEFAULT 0"),
            ("crew_names", "TEXT NOT NULL DEFAULT ''"),
            ("crew_roles", "TEXT NOT NULL DEFAULT ''"),
            ("departure_lat", "REAL"),
            ("departure_lon", "REAL"),
            ("arrival_lat", "REAL"),
            ("arrival_lon", "REAL"),
            ("remarks", "TEXT NOT NULL DEFAULT ''"),
            ("signature_name", "TEXT NOT NULL DEFAULT ''"),
            ("signature_reference", "TEXT NOT NULL DEFAULT ''"),
            ("locked", "INTEGER NOT NULL DEFAULT 0"),
            ("record_state", "TEXT NOT NULL DEFAULT 'draft'"),
            ("amends_flight_id", "INTEGER"),
            ("superseded_by_flight_id", "INTEGER"),
            ("modified_at", "TEXT NOT NULL DEFAULT ''")
        ]
        for (name, definition) in definitions {
            try addColumnIfNeeded("flights", name: name, definition: definition, in: db)
        }
    }

    public func schemaVersion() throws -> Int {
        guard FileManager.default.fileExists(atPath: paths.workingDatabase.path) else { return 0 }
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        return try db.rows("PRAGMA user_version").first?.values.first?.int ?? 0
    }

    public func upgradePreflight() throws -> UpgradePreflight {
        let version = try schemaVersion()
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        let count = try flightCount(in: db)
        let digest = try canonicalLegacyDigest(in: db)
        let amendmentIssues = try amendmentPreflightIssues(in: db)
        let backupURL = paths.backupFolder.appendingPathComponent("Blackbox-pre-upgrade-\(Self.backupTimestamp()).sqlite")
        return UpgradePreflight(
            requiresUpgrade: version < Self.currentSchemaVersion,
            currentSchemaVersion: version,
            targetSchemaVersion: Self.currentSchemaVersion,
            flightCount: count,
            legacyDigest: digest,
            proposedBackupURL: backupURL,
            amendmentIssues: amendmentIssues
        )
    }

    @discardableResult
    public func backUpAndUpgrade(using preflight: UpgradePreflight, injectingFailureAt failurePoint: MigrationFailurePoint? = nil) throws -> URL {
        guard preflight.currentSchemaVersion == (try schemaVersion()), preflight.legacyDigest == (try canonicalLegacyDigest()) else {
            throw LogbookRepositoryError.stalePlan
        }
        guard preflight.currentSchemaVersion <= Self.currentSchemaVersion else {
            throw LogbookRepositoryError.invalidState("This database uses schema \(preflight.currentSchemaVersion), which is newer than this Blackbox build supports.")
        }
        guard preflight.requiresUpgrade else { return preflight.proposedBackupURL }
        guard preflight.amendmentIssues.isEmpty else {
            throw LogbookRepositoryError.invalidState("Resolve amendment-link conflicts before upgrading: \(preflight.amendmentIssues.joined(separator: " "))")
        }
        try FileManager.default.createDirectory(at: paths.backupFolder, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: preflight.proposedBackupURL.path) {
            try FileManager.default.removeItem(at: preflight.proposedBackupURL)
        }
        do {
            let source = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            try source.backup(to: preflight.proposedBackupURL.path)
        } catch {
            throw LogbookRepositoryError.integrityCheckFailed("Creating pre-upgrade backup failed: \(error)")
        }
        do {
            let backup = try SQLiteConnection(path: preflight.proposedBackupURL.path, readOnly: true)
            guard try backup.integrityCheck().lowercased() == "ok" else {
                throw LogbookRepositoryError.integrityCheckFailed("The pre-upgrade backup did not pass SQLite integrity_check.")
            }
        } catch {
            throw LogbookRepositoryError.integrityCheckFailed("Opening pre-upgrade backup failed: \(error)")
        }
        do {
            if failurePoint == .beforeTransaction {
                throw LogbookRepositoryError.integrityCheckFailed("Injected failure before migration transaction.")
            }
            let db: SQLiteConnection
            do { db = try SQLiteConnection(path: paths.workingDatabase.path) }
            catch { throw LogbookRepositoryError.integrityCheckFailed("Opening migration transaction failed: \(error)") }
            let preservedColumns = try canonicalLegacyColumns(in: db)
            let beforeDigest = try canonicalDigest(in: db, columns: preservedColumns)
            try db.transaction {
                try addCurrentFlightColumnsIfNeeded(in: db)
                if preflight.currentSchemaVersion < 2 {
                    try db.execute("UPDATE flights SET record_state = CASE WHEN locked = 1 THEN 'finalised' ELSE 'draft' END WHERE record_state IS NULL OR record_state = '' OR record_state = 'draft'")
                }
                try createSchema(in: db)
                if failurePoint == .duringTransaction {
                    throw LogbookRepositoryError.integrityCheckFailed("Injected failure during migration transaction.")
                }
                guard try canonicalDigest(in: db, columns: preservedColumns) == beforeDigest else {
                    throw LogbookRepositoryError.integrityCheckFailed("A legacy flight field changed during migration.")
                }
            }
            if failurePoint == .afterTransaction {
                throw LogbookRepositoryError.integrityCheckFailed("Injected failure after migration transaction.")
            }
            let verified = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            let integrity = try verified.integrityCheck()
            guard integrity.lowercased() == "ok" else { throw LogbookRepositoryError.integrityCheckFailed(integrity) }
            guard try canonicalDigest(in: verified, columns: preservedColumns) == preflight.legacyDigest else {
                throw LogbookRepositoryError.integrityCheckFailed("A legacy flight field changed after migration commit.")
            }
        } catch {
            try restoreMigrationBackup(preflight.proposedBackupURL)
            let restored = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            let restoredSummary = try summary(in: restored)
            let failed = OperationBatch(
                kind: "migration",
                source: "schema-\(preflight.currentSchemaVersion)-to-\(preflight.targetSchemaVersion)",
                status: "failed",
                summary: "Migration rolled back",
                backupPath: preflight.proposedBackupURL.path,
                completedAt: Date(),
                affectedCount: preflight.flightCount,
                beforeTotalMinutes: restoredSummary.totalMinutes,
                afterTotalMinutes: restoredSummary.totalMinutes,
                failureStage: failurePoint?.rawValue ?? "migration",
                recoveryOutcome: "Verified pre-upgrade backup restored",
                artifactURLs: [preflight.proposedBackupURL]
            )
            // A restored historical schema may not yet have operation_batches;
            // retain the flight-free diagnostic artifact for the next healthy
            // post-upgrade launch instead of migrating it implicitly.
            _ = try? OperationAuditStore.store(failed, in: operationAuditFolder)
            throw error
        }
        return preflight.proposedBackupURL
    }

    private func restoreMigrationBackup(_ backupURL: URL) throws {
        let manager = FileManager.default
        let staged = paths.workingDatabase.deletingLastPathComponent()
            .appendingPathComponent(".Blackbox-migration-rollback-\(UUID().uuidString).sqlite")
        try manager.copyItem(at: backupURL, to: staged)
        if manager.fileExists(atPath: paths.workingDatabase.path) {
            _ = try manager.replaceItemAt(paths.workingDatabase, withItemAt: staged, backupItemName: nil, options: [])
        } else {
            try manager.moveItem(at: staged, to: paths.workingDatabase)
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: paths.workingDatabase.path + suffix)
            if manager.fileExists(atPath: sidecar.path) { try manager.removeItem(at: sidecar) }
        }
        let restored = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        guard try restored.integrityCheck().lowercased() == "ok" else {
            throw LogbookRepositoryError.integrityCheckFailed("Migration rollback did not pass SQLite integrity_check.")
        }
    }

    private func createReliabilityTables(in db: SQLiteConnection) throws {
        try db.execute("""
        CREATE TABLE IF NOT EXISTS flight_revisions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            flight_id INTEGER NOT NULL,
            action TEXT NOT NULL,
            origin TEXT NOT NULL,
            operation_batch_id TEXT,
            before_json TEXT,
            after_json TEXT,
            created_at TEXT NOT NULL
        )
        """)
        try db.execute("CREATE INDEX IF NOT EXISTS idx_flight_revisions_flight ON flight_revisions(flight_id, id)")
        try db.execute("""
        CREATE TABLE IF NOT EXISTS operation_batches (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            source TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL,
            summary TEXT NOT NULL DEFAULT '',
            backup_path TEXT,
            created_at TEXT NOT NULL,
            completed_at TEXT,
            affected_count INTEGER NOT NULL DEFAULT 0,
            before_total_minutes INTEGER NOT NULL DEFAULT 0,
            after_total_minutes INTEGER NOT NULL DEFAULT 0,
            verification_json TEXT,
            failure_stage TEXT,
            recovery_outcome TEXT,
            artifact_urls_json TEXT
        )
        """)
    }

    private func addOperationMetadataColumns(in db: SQLiteConnection) throws {
        try addColumnIfNeeded("operation_batches", name: "affected_count", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("operation_batches", name: "before_total_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("operation_batches", name: "after_total_minutes", definition: "INTEGER NOT NULL DEFAULT 0", in: db)
        try addColumnIfNeeded("operation_batches", name: "verification_json", definition: "TEXT", in: db)
        try addColumnIfNeeded("operation_batches", name: "failure_stage", definition: "TEXT", in: db)
        try addColumnIfNeeded("operation_batches", name: "recovery_outcome", definition: "TEXT", in: db)
        try addColumnIfNeeded("operation_batches", name: "artifact_urls_json", definition: "TEXT", in: db)
    }

    private func createAmendmentInvariant(in db: SQLiteConnection) throws {
        try db.execute("""
        CREATE UNIQUE INDEX IF NOT EXISTS idx_flights_one_active_amendment
        ON flights(amends_flight_id)
        WHERE amends_flight_id IS NOT NULL AND record_state IN ('draft', 'finalised')
        """)
    }

    /// A restored database is untrusted input even when its encrypted envelope
    /// is authentic: the person supplying the passphrase may not be the person
    /// who created its SQLite schema. Reject executable schema objects before
    /// migration, then compare the migrated structure with a database created
    /// by this build before the candidate can become active.
    private func rejectExecutableRestoreSchema(in db: SQLiteConnection) throws {
        let objects = try db.rows("SELECT type, name, sql FROM sqlite_master ORDER BY type, name")
        for object in objects {
            let type = object["type"]?.string.lowercased() ?? ""
            let name = object["name"]?.string ?? ""
            let sql = object["sql"]?.string.uppercased() ?? ""
            if type == "trigger" || type == "view" || sql.contains("CREATE VIRTUAL TABLE") {
                throw LogbookRepositoryError.invalidState("The backup contains an unsupported executable SQLite schema object: \(name).")
            }
        }
    }

    private func validateCanonicalRestoreSchema(in db: SQLiteConnection, workspace: URL) throws {
        let canonicalURL = workspace.appendingPathComponent("Canonical-Schema-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: canonicalURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: canonicalURL.path + "-wal"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: canonicalURL.path + "-shm"))
        }
        let canonical = try SQLiteConnection(path: canonicalURL.path)
        try createSchema(in: canonical)
        let expected = try schemaFingerprint(in: canonical)
        let actual = try schemaFingerprint(in: db)
        guard actual == expected else {
            let firstMismatch = zip(expected, actual).first { $0 != $1 }
            let detail: String
            if let firstMismatch {
                detail = " Expected \(firstMismatch.0); found \(firstMismatch.1)."
            } else {
                detail = " Expected \(expected.count) schema entries; found \(actual.count)."
            }
            throw LogbookRepositoryError.invalidState("The backup schema does not match the canonical Blackbox schema.\(detail)")
        }
    }

    private func schemaFingerprint(in db: SQLiteConnection) throws -> [String] {
        let objectRows = try db.rows("""
        SELECT type, name, tbl_name
        FROM sqlite_master
        WHERE name NOT LIKE 'sqlite_%'
        ORDER BY type, name, tbl_name
        """)
        var fingerprint = objectRows.map { row in
            "object|\(row["type"]?.string ?? "")|\(row["name"]?.string ?? "")|\(row["tbl_name"]?.string ?? "")"
        }
        let tableNames = objectRows
            .filter { $0["type"]?.string == "table" }
            .compactMap { $0["name"]?.string }
            .sorted()
        for table in tableNames {
            let quotedTable = table.replacingOccurrences(of: "'", with: "''")
            let columns = try db.rows("PRAGMA table_xinfo('\(quotedTable)')")
                .sorted { ($0["name"]?.string ?? "") < ($1["name"]?.string ?? "") }
            for row in columns {
                fingerprint.append([
                    "column", table,
                    row["name"]?.string ?? "",
                    row["type"]?.string.uppercased() ?? "",
                    row["notnull"]?.string ?? "",
                    row["pk"]?.string ?? "",
                    row["hidden"]?.string ?? ""
                ].joined(separator: "|"))
            }
            let indexes = try db.rows("PRAGMA index_list('\(quotedTable)')")
                .filter { !($0["name"]?.string ?? "").hasPrefix("sqlite_autoindex_") }
                .sorted { ($0["name"]?.string ?? "") < ($1["name"]?.string ?? "") }
            for index in indexes {
                let indexName = index["name"]?.string ?? ""
                fingerprint.append([
                    "index", table, indexName,
                    index["unique"]?.string ?? "",
                    index["origin"]?.string ?? "",
                    index["partial"]?.string ?? ""
                ].joined(separator: "|"))
                let quotedIndex = indexName.replacingOccurrences(of: "'", with: "''")
                for row in try db.rows("PRAGMA index_xinfo('\(quotedIndex)')") {
                    fingerprint.append([
                        "index-column", indexName,
                        row["seqno"]?.string ?? "",
                        row["name"]?.string ?? "",
                        row["desc"]?.string ?? "",
                        row["coll"]?.string ?? "",
                        row["key"]?.string ?? ""
                    ].joined(separator: "|"))
                }
            }
            for row in try db.rows("PRAGMA foreign_key_list('\(quotedTable)')") {
                fingerprint.append([
                    "foreign-key", table,
                    row["id"]?.string ?? "",
                    row["seq"]?.string ?? "",
                    row["table"]?.string ?? "",
                    row["from"]?.string ?? "",
                    row["to"]?.string ?? "",
                    row["on_update"]?.string ?? "",
                    row["on_delete"]?.string ?? "",
                    row["match"]?.string ?? ""
                ].joined(separator: "|"))
            }
        }
        return fingerprint
    }

    private func amendmentPreflightIssues(in db: SQLiteConnection) throws -> [String] {
        let columns = Set(try db.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string })
        guard columns.contains("record_state"), columns.contains("amends_flight_id"), columns.contains("superseded_by_flight_id") else {
            return []
        }

        var issues: [String] = []
        let duplicateRoots = try db.rows("""
        SELECT amends_flight_id, COUNT(*) AS count
        FROM flights
        WHERE amends_flight_id IS NOT NULL AND record_state IN ('draft', 'finalised')
        GROUP BY amends_flight_id
        HAVING COUNT(*) > 1
        ORDER BY amends_flight_id
        """)
        for row in duplicateRoots {
            issues.append("Flight \(row["amends_flight_id"]?.int64 ?? 0) has \(row["count"]?.int ?? 0) active amendments.")
        }

        let invalidDrafts = try db.rows("""
        SELECT child.id AS child_id, child.amends_flight_id AS original_id
        FROM flights child
        LEFT JOIN flights original ON original.id = child.amends_flight_id
        WHERE child.record_state = 'draft' AND child.amends_flight_id IS NOT NULL
          AND (original.id IS NULL OR original.record_state != 'finalised' OR original.superseded_by_flight_id IS NOT NULL)
        ORDER BY child.id
        """)
        for row in invalidDrafts {
            issues.append("Draft amendment \(row["child_id"]?.int64 ?? 0) does not reference an available finalised original \(row["original_id"]?.int64 ?? 0).")
        }

        let invalidFinalised = try db.rows("""
        SELECT child.id AS child_id, child.amends_flight_id AS original_id
        FROM flights child
        LEFT JOIN flights original ON original.id = child.amends_flight_id
        WHERE child.record_state IN ('finalised', 'superseded') AND child.amends_flight_id IS NOT NULL
          AND (original.id IS NULL OR original.record_state != 'superseded' OR original.superseded_by_flight_id != child.id)
        ORDER BY child.id
        """)
        for row in invalidFinalised {
            issues.append("Finalised or superseded amendment \(row["child_id"]?.int64 ?? 0) is not linked from superseded original \(row["original_id"]?.int64 ?? 0).")
        }

        struct LinkRecord {
            var state: String
            var locked: Bool
            var amends: Int64?
            var successor: Int64?
        }
        let linkRows = try db.rows("SELECT id, record_state, locked, amends_flight_id, superseded_by_flight_id FROM flights ORDER BY id")
        let links = Dictionary(uniqueKeysWithValues: linkRows.compactMap { row -> (Int64, LinkRecord)? in
            guard let id = row["id"]?.int64 else { return nil }
            return (id, LinkRecord(
                state: row["record_state"]?.string ?? "",
                locked: (row["locked"]?.int ?? 0) != 0,
                amends: row["amends_flight_id"]?.int64,
                successor: row["superseded_by_flight_id"]?.int64
            ))
        })
        let allowedStates = Set(FlightRecordState.allCases.map(\.rawValue))
        for id in links.keys.sorted() {
            guard let link = links[id] else { continue }
            if !allowedStates.contains(link.state) {
                issues.append("Flight \(id) has unknown record state '\(link.state)'.")
            }
            if let originalID = link.amends {
                if originalID == id { issues.append("Flight \(id) amends itself.") }
                if links[originalID] == nil { issues.append("Flight \(id) amends missing flight \(originalID).") }
            }
            if let successorID = link.successor {
                if successorID == id { issues.append("Flight \(id) supersedes itself.") }
                guard let successor = links[successorID] else {
                    issues.append("Flight \(id) points to missing successor \(successorID).")
                    continue
                }
                if successor.amends != id {
                    issues.append("Flight \(id)'s successor \(successorID) does not link back to it.")
                }
                if successor.state != FlightRecordState.finalised.rawValue && successor.state != FlightRecordState.superseded.rawValue {
                    issues.append("Flight \(id)'s successor \(successorID) is not finalised or superseded.")
                }
            }
            switch FlightRecordState(rawValue: link.state) {
            case .draft, .trashed:
                if link.locked { issues.append("Flight \(id) is \(link.state) but remains locked.") }
                if link.successor != nil { issues.append("Flight \(id) is \(link.state) but identifies a successor.") }
            case .finalised:
                if !link.locked { issues.append("Finalised flight \(id) is not locked.") }
                if link.successor != nil { issues.append("Finalised flight \(id) identifies a successor without being superseded.") }
            case .superseded:
                if !link.locked { issues.append("Superseded flight \(id) is not locked.") }
                if link.successor == nil { issues.append("Superseded flight \(id) has no successor.") }
            case nil:
                break
            }
        }

        // Follow the one-way amendment ancestry independently of the reciprocal
        // successor backlink. A normal amendment pair is not a cycle; a corrupt
        // A-amends-B / B-amends-A graph is.
        var reportedCycles = Set<String>()
        for start in links.keys.sorted() {
            var path: [Int64] = []
            var pathIndex: [Int64: Int] = [:]
            var current: Int64? = start
            while let node = current, let link = links[node] {
                if let index = pathIndex[node] {
                    let cycle = Array(path[index...])
                    let key = cycle.sorted().map(String.init).joined(separator: ",")
                    if reportedCycles.insert(key).inserted {
                        issues.append("Amendment linkage cycle detected across flights \(cycle.map(String.init).joined(separator: " -> ")).")
                    }
                    break
                }
                pathIndex[node] = path.count
                path.append(node)
                current = link.amends
            }
        }
        return issues
    }

    private func canonicalLegacyDigest() throws -> String {
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        return try canonicalLegacyDigest(in: db)
    }

    private func canonicalLegacyDigest(in db: SQLiteConnection) throws -> String {
        try canonicalDigest(in: db, columns: canonicalLegacyColumns(in: db))
    }

    private func canonicalLegacyColumns(in db: SQLiteConnection) throws -> [String] {
        let columns = try db.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string }
        let excluded = Set(["record_state", "amends_flight_id", "superseded_by_flight_id"])
        return columns.filter { !excluded.contains($0) }
    }

    private func canonicalDigest(in db: SQLiteConnection, columns: [String]) throws -> String {
        guard !columns.isEmpty else { return Self.sha256(Data()) }
        let rows = try db.rows("SELECT \(columns.joined(separator: ", ")) FROM flights ORDER BY id")
        var data = Data()
        for row in rows {
            for column in columns {
                data.append(Data(column.utf8)); data.append(0)
                switch row[column] ?? .null {
                case .null: data.append(Data("null".utf8))
                case .integer(let value): data.append(Data("i:\(value)".utf8))
                case .real(let value): data.append(Data("r:\(value.bitPattern)".utf8))
                case .text(let value): data.append(Data("t:\(value)".utf8))
                }
                data.append(0xff)
            }
        }
        return Self.sha256(data)
    }

    private func canonicalFlightDigest(in db: SQLiteConnection) throws -> String {
        let columns = try db.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string }
        guard columns.contains("record_state") else { return try canonicalLegacyDigest(in: db) }
        let entries = try db.rows("SELECT * FROM flights ORDER BY id").map(Self.flight(from:))
        return try Self.flightEntriesDigest(entries)
    }

    private func schemaVersion(in db: SQLiteConnection) throws -> Int {
        try db.rows("PRAGMA user_version").first?.values.first?.int ?? 0
    }

    private static func flightEntryDigest(_ flight: FlightEntry) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(flight)).map { String(format: "%02x", $0) }.joined()
    }

    private static func flightEntriesDigest(_ flights: [FlightEntry]) throws -> String {
        let components = try flights.map(flightEntryDigest).sorted()
        return SHA256.hash(data: Data(components.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private struct SealedImportChange: Codable {
        var sourcePK: Int64
        var existing: FlightEntry
        var proposed: FlightEntry
        var changedFields: [String]
    }

    private struct SealedFieldDescriptor: Codable {
        var sourcePK: Int64
        var field: String
        var blackboxValue: String
        var sourceValue: String
    }

    private struct SealedImportPlanContent: Codable {
        var sourcePath: String
        var additions: [FlightEntry]
        var changes: [SealedImportChange]
        var unchangedCount: Int
        var unchangedRecords: [ImportRecordIdentity]
        var duplicateSourceIDs: [Int64]
        var conflicts: [String]
        var conflictSourceIDs: [Int64]
        var missingFromSourceCount: Int
        var sourceOnlyOmissions: [ImportRecordIdentity]
        var fieldDescriptors: [SealedFieldDescriptor]
        var resultingActions: [String: String]
        var sourceKind: ImportSourceKind
        var baselineFlightDigest: String
        var sourceSnapshotDigest: String
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func importPlanContentDigest(_ plan: ImportPlan) throws -> String {
        let content = SealedImportPlanContent(
            sourcePath: plan.sourceURL.standardizedFileURL.path,
            additions: plan.additions,
            changes: plan.changes.map {
                SealedImportChange(sourcePK: $0.sourcePK, existing: $0.existing, proposed: $0.proposed, changedFields: $0.changedFields)
            },
            unchangedCount: plan.unchangedCount,
            unchangedRecords: plan.unchangedRecords,
            duplicateSourceIDs: plan.duplicateSourceIDs,
            conflicts: plan.conflicts,
            conflictSourceIDs: plan.conflictSourceIDs,
            missingFromSourceCount: plan.missingFromSourceCount,
            sourceOnlyOmissions: plan.sourceOnlyOmissions,
            fieldDescriptors: plan.fieldSelections.map {
                SealedFieldDescriptor(sourcePK: $0.sourcePK, field: $0.field, blackboxValue: $0.blackboxValue, sourceValue: $0.sourceValue)
            },
            resultingActions: Dictionary(uniqueKeysWithValues: plan.resultingActions.map { (String($0.key), $0.value.rawValue) }),
            sourceKind: plan.sourceKind,
            baselineFlightDigest: plan.baselineFlightDigest,
            sourceSnapshotDigest: plan.sourceSnapshotDigest
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return sha256(try encoder.encode(content))
    }

    private struct SealedRestorePlanContent: Codable {
        var encryptedBackupPath: String
        var inspectedDatabasePath: String
        var currentFlightCount: Int
        var restoredFlightCount: Int
        var currentTotalMinutes: Int
        var restoredTotalMinutes: Int
        var schemaVersion: Int
        var integrityMessage: String
        var inspectedDigest: String
        var currentFlightDigest: String
        var restoredFlightDigest: String
    }

    private static func restorePlanContentDigest(_ plan: RestorePlan) throws -> String {
        let content = SealedRestorePlanContent(
            encryptedBackupPath: plan.encryptedBackupURL.standardizedFileURL.path,
            inspectedDatabasePath: plan.inspectedDatabaseURL.standardizedFileURL.path,
            currentFlightCount: plan.currentFlightCount,
            restoredFlightCount: plan.restoredFlightCount,
            currentTotalMinutes: plan.currentTotalMinutes,
            restoredTotalMinutes: plan.restoredTotalMinutes,
            schemaVersion: plan.schemaVersion,
            integrityMessage: plan.integrityMessage,
            inspectedDigest: plan.inspectedDigest,
            currentFlightDigest: plan.currentFlightDigest,
            restoredFlightDigest: plan.restoredFlightDigest
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return sha256(try encoder.encode(content))
    }

    private static func importArtifactRoot(for token: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-ImportPlan-\(token.uuidString)", isDirectory: true)
            .standardizedFileURL
    }

    private static func restoreArtifactRoot(for token: UUID) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-Restore-\(token.uuidString)", isDirectory: true)
            .standardizedFileURL
    }

    private func validatedImportArtifactRoot(for plan: ImportPlan) throws -> URL {
        guard let token = plan.artifactToken,
              let candidateURL = plan.candidateSnapshotURL else {
            throw LogbookRepositoryError.stalePlan
        }
        let root = Self.importArtifactRoot(for: token)
        guard candidateURL.standardizedFileURL == root.appendingPathComponent("Candidates.json").standardizedFileURL else {
            throw LogbookRepositoryError.stalePlan
        }
        if let sourceSnapshotURL = plan.sourceSnapshotURL {
            guard sourceSnapshotURL.standardizedFileURL == root.appendingPathComponent("LogTen-Source.sqlite").standardizedFileURL else {
                throw LogbookRepositoryError.stalePlan
            }
        }
        return root
    }

    private func validatedRestoreArtifactRoot(for plan: RestorePlan) throws -> URL {
        guard let token = plan.artifactToken else { throw LogbookRepositoryError.stalePlan }
        let root = Self.restoreArtifactRoot(for: token)
        guard plan.inspectedDatabaseURL.standardizedFileURL == root.appendingPathComponent("Inspected.sqlite").standardizedFileURL else {
            throw LogbookRepositoryError.stalePlan
        }
        return root
    }

    private static func writeCandidateSnapshot(_ flights: [FlightEntry], to url: URL) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(flights)
        try data.write(to: url, options: [.atomic])
        return sha256(data)
    }

    private func verifiedCandidateSnapshot(for plan: ImportPlan) throws -> [FlightEntry] {
        _ = try validatedImportArtifactRoot(for: plan)
        guard let url = plan.candidateSnapshotURL,
              FileManager.default.fileExists(atPath: url.path) else {
            throw LogbookRepositoryError.stalePlan
        }
        let data = try Data(contentsOf: url)
        guard !plan.candidateSnapshotFileDigest.isEmpty,
              Self.sha256(data) == plan.candidateSnapshotFileDigest else {
            throw LogbookRepositoryError.stalePlan
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let candidates = try decoder.decode([FlightEntry].self, from: data)
        guard try Self.flightEntriesDigest(candidates) == plan.sourceSnapshotDigest,
              !plan.sealedPlanDigest.isEmpty,
              try Self.importPlanContentDigest(plan) == plan.sealedPlanDigest else {
            throw LogbookRepositoryError.stalePlan
        }
        return candidates
    }

    private struct ImportExpectedManifest {
        var flightCount: Int
        var totalMinutes: Int
        var revisionCount: Int
        var affectedCount: Int
        var flightDigest: String
    }

    private func expectedImportManifest(for plan: ImportPlan, in db: SQLiteConnection) throws -> ImportExpectedManifest {
        var expected = try db.rows("SELECT * FROM flights ORDER BY id").map(Self.flight(from:))
        let hasSequenceTable = try db.rows(
            "SELECT 1 AS present FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_sequence' LIMIT 1"
        ).first != nil
        let storedSequence = hasSequenceTable
            ? try db.rows("SELECT seq FROM sqlite_sequence WHERE name = 'flights'").first?["seq"]?.int64
            : nil
        let sequence = storedSequence ?? expected.compactMap(\.id).max() ?? 0
        var nextID = sequence + 1
        var revisionCount = 0
        var affectedCount = 0

        for proposed in plan.additions {
            guard Self.additionHasIncludedField(proposed, selections: plan.fieldSelections) else { continue }
            var flight = try Self.applyingAdditionSelections(to: proposed, selections: plan.fieldSelections)
            guard let sourcePK = flight.sourcePK else { continue }
            let action = plan.resolutionActions[sourcePK] ?? plan.resultingActions[sourcePK]
            if plan.duplicateDecisions[sourcePK] == .exclude || action == .linkAndSkip || action == .ignore { continue }
            guard action == .createDraft || action == .importSeparateDraft else {
                throw LogbookRepositoryError.invalidState("The preview contains an invalid action for source \(sourcePK).")
            }
            flight.id = nextID
            nextID += 1
            flight.recordState = .draft
            flight.locked = false
            flight.amendsFlightID = nil
            flight.supersededByFlightID = nil
            expected.append(flight)
            revisionCount += 1
            affectedCount += 1
        }

        for change in plan.changes {
            guard let id = change.existing.id,
                  let index = expected.firstIndex(where: { $0.id == id }) else { continue }
            let action = plan.resolutionActions[change.sourcePK] ?? plan.resultingActions[change.sourcePK]
            if plan.duplicateDecisions[change.sourcePK] == .exclude || action == .linkAndSkip || action == .ignore { continue }
            var flight = Self.applyingFieldSelections(for: change, selections: plan.fieldSelections)
            if flight == change.existing { continue }
            if action == .importSeparateDraft {
                flight.id = nextID
                nextID += 1
                flight.sourcePK = nil
                flight.recordState = .draft
                flight.locked = false
                flight.amendsFlightID = nil
                flight.supersededByFlightID = nil
                expected.append(flight)
            } else if change.existing.recordState == .finalised {
                guard action == .createAmendment else {
                    throw LogbookRepositoryError.invalidState("A finalised import match can only create an amendment.")
                }
                flight.id = nextID
                nextID += 1
                flight.sourcePK = nil
                flight.recordState = .draft
                flight.locked = false
                flight.amendsFlightID = id
                flight.supersededByFlightID = nil
                expected.append(flight)
            } else {
                guard change.existing.recordState == .draft,
                      action == .updateDraft else {
                    throw LogbookRepositoryError.invalidState("Only a draft import match can be updated in place.")
                }
                flight.id = id
                flight.recordState = .draft
                flight.locked = false
                flight.amendsFlightID = change.existing.amendsFlightID
                flight.supersededByFlightID = nil
                expected[index] = flight
            }
            revisionCount += 1
            affectedCount += 1
        }

        let active = expected.filter { $0.recordState == .draft || $0.recordState == .finalised }
        return ImportExpectedManifest(
            flightCount: active.count,
            totalMinutes: active.reduce(0) { $0 + $1.flyingMinutes },
            revisionCount: revisionCount,
            affectedCount: affectedCount,
            flightDigest: try Self.flightEntriesDigest(expected)
        )
    }

    private static func documentSourceIdentifier(sourceURL: URL, ordinal: Int, flight: FlightEntry) throws -> Int64 {
        var literal = flight
        literal.id = nil
        literal.sourcePK = nil
        literal.recordState = .draft
        literal.locked = false
        literal.amendsFlightID = nil
        literal.supersededByFlightID = nil
        let seed = "\(sourceURL.standardizedFileURL.path)\u{0}\(ordinal)\u{0}\(try flightEntryDigest(literal))"
        let digest = SHA256.hash(data: Data(seed.utf8))
        let positive = digest.prefix(8).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) } & UInt64(Int64.max)
        return -Int64(max(positive, 1))
    }

    private static func importRecordIdentity(for flight: FlightEntry) -> ImportRecordIdentity {
        ImportRecordIdentity(
            flightID: flight.id,
            sourcePK: flight.sourcePK,
            date: flight.date,
            route: flight.routeDisplay,
            aircraftID: flight.aircraftID,
            flightNumber: flight.flightNumber,
            recordState: flight.recordState
        )
    }

    private func makeVerifiedSnapshot(from sourceURL: URL, to destinationURL: URL) throws {
        let manager = FileManager.default
        if manager.fileExists(atPath: destinationURL.path) {
            try manager.removeItem(at: destinationURL)
        }
        try manager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            let source = try SQLiteConnection(path: sourceURL.path, readOnly: true)
            try source.backup(to: destinationURL.path)
        }
        let snapshot = try SQLiteConnection(path: destinationURL.path, readOnly: true)
        let integrity = try snapshot.integrityCheck()
        let foreignKeyIssues = try foreignKeyIssueDescriptions(in: snapshot)
        let amendmentIssues = try amendmentPreflightIssues(in: snapshot)
        guard integrity.lowercased() == "ok", foreignKeyIssues.isEmpty, amendmentIssues.isEmpty else {
            let relationshipDetails = (foreignKeyIssues + amendmentIssues).joined(separator: " ")
            let suffix = relationshipDetails.isEmpty ? "" : " \(relationshipDetails)"
            throw LogbookRepositoryError.integrityCheckFailed("The self-contained database snapshot failed integrity or relationship verification.\(suffix)")
        }
    }

    private func removeDatabaseSidecars(for databaseURL: URL) throws {
        let manager = FileManager.default
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: databaseURL.path + suffix)
            if manager.fileExists(atPath: sidecar.path) {
                try manager.removeItem(at: sidecar)
            }
        }
    }

    private func checkpointWorkingDatabase() throws {
        guard FileManager.default.fileExists(atPath: paths.workingDatabase.path) else { return }
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        try db.checkpointWAL()
    }

    private func activateDatabase(at candidateURL: URL) throws {
        let manager = FileManager.default
        try checkpointWorkingDatabase()
        try removeDatabaseSidecars(for: paths.workingDatabase)
        if manager.fileExists(atPath: paths.workingDatabase.path) {
            _ = try manager.replaceItemAt(paths.workingDatabase, withItemAt: candidateURL, backupItemName: nil, options: [])
        } else {
            try manager.moveItem(at: candidateURL, to: paths.workingDatabase)
        }
        try removeDatabaseSidecars(for: paths.workingDatabase)
        let active = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        guard try active.integrityCheck().lowercased() == "ok" else {
            throw LogbookRepositoryError.integrityCheckFailed("The atomically activated database did not pass integrity_check.")
        }
    }

    private func restoreDatabase(from recoveryURL: URL) throws {
        let rollbackURL = paths.workingDatabase.deletingLastPathComponent()
            .appendingPathComponent(".Blackbox-rollback-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: rollbackURL) }
        let recovery = try SQLiteConnection(path: recoveryURL.path, readOnly: true)
        let expectedDigest = try canonicalFlightDigest(in: recovery)
        try makeVerifiedSnapshot(from: recoveryURL, to: rollbackURL)
        try activateDatabase(at: rollbackURL)
        let restored = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        guard try canonicalFlightDigest(in: restored) == expectedDigest else {
            throw LogbookRepositoryError.integrityCheckFailed("Recovery restored a database whose flight digest differs from the verified recovery point.")
        }
    }

    private func operationVerification(
        in db: SQLiteConnection,
        batchID: String,
        expectedFlightCount: Int,
        expectedTotalMinutes: Int,
        expectedRevisionCount: Int,
        expectedFlightDigest: String
    ) throws -> OperationVerification {
        let integrity = try db.integrityCheck()
        let foreignKeyIssues = try foreignKeyIssueDescriptions(in: db)
        let amendmentIssues = try amendmentPreflightIssues(in: db)
        let actualSummary = try summary(in: db)
        let actualRevisionCount = try db.rows(
            "SELECT COUNT(*) AS count FROM flight_revisions WHERE operation_batch_id = ?",
            values: [.text(batchID)]
        ).first?["count"]?.int ?? 0
        return OperationVerification(
            integrityCheck: integrity,
            schemaVersion: try schemaVersion(in: db),
            expectedSchemaVersion: Self.currentSchemaVersion,
            expectedFlightCount: expectedFlightCount,
            actualFlightCount: actualSummary.flightCount,
            expectedTotalMinutes: expectedTotalMinutes,
            actualTotalMinutes: actualSummary.totalMinutes,
            revisionCoverageComplete: foreignKeyIssues.isEmpty && amendmentIssues.isEmpty && actualRevisionCount == expectedRevisionCount,
            expectedRevisionCount: expectedRevisionCount,
            actualRevisionCount: actualRevisionCount,
            expectedFlightDigest: expectedFlightDigest,
            actualFlightDigest: try canonicalFlightDigest(in: db),
            foreignKeyIssues: foreignKeyIssues,
            amendmentIssues: amendmentIssues
        )
    }

    private func foreignKeyIssueDescriptions(in db: SQLiteConnection) throws -> [String] {
        try db.rows("PRAGMA foreign_key_check").map { row in
            let table = row["table"]?.string ?? "unknown"
            let rowID = row["rowid"]?.int64.map { String($0) } ?? "unknown"
            let parent = row["parent"]?.string ?? "unknown"
            return "\(table) row \(rowID) references missing \(parent)"
        }
    }

    public func flights(search: String = "") throws -> [FlightEntry] {
        try flights(query: FlightQuery(text: search))
    }

    public func flights(query: FlightQuery) throws -> [FlightEntry] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        var clauses: [String] = []
        var values: [SQLiteValue] = []
        let trimmed = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            clauses.append("(departure LIKE ? OR arrival LIKE ? OR route LIKE ? OR aircraft_id LIKE ? OR aircraft_type LIKE ? OR remarks LIKE ? OR flight_number LIKE ? OR pilot_function LIKE ? OR crew_names LIKE ?)")
            values += Array(repeating: .text("%\(trimmed)%"), count: 9)
        }
        if let startDate = query.startDate {
            clauses.append("date >= ?")
            values.append(.text(LogbookFormatters.isoFormatter.string(from: startDate)))
        }
        if let endDate = query.endDate {
            clauses.append("date <= ?")
            values.append(.text(LogbookFormatters.isoFormatter.string(from: endDate)))
        }
        func appendSet(_ column: String, _ set: Set<String>) {
            guard !set.isEmpty else { return }
            clauses.append("\(column) IN (\(Array(repeating: "?", count: set.count).joined(separator: ", ")))")
            values += set.sorted().map(SQLiteValue.text)
        }
        appendSet("aircraft_id", query.aircraftIDs)
        appendSet("aircraft_type", query.aircraftTypes)
        appendSet("pilot_function", query.pilotFunctions)
        appendSet("operation", query.operations)
        appendSet("entry_kind", query.entryKinds)
        appendSet("record_state", Set(query.recordStates.map(\.rawValue)))
        let predicate = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
        let sql = "SELECT * FROM flights \(predicate) ORDER BY date DESC, id DESC"
        return try db.rows(sql, values: values).map(Self.flight(from:))
    }

    public func flight(id: Int64) throws -> FlightEntry? {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        return try db.rows("SELECT * FROM flights WHERE id = ?", values: [.integer(id)]).first.map(Self.flight(from:))
    }

    /// Combines value-level checks with amendment relationships read from the
    /// database. Persistence callers should use this report before finalising;
    /// the static suggestion engine intentionally has no database access.
    public func validationReport(for flight: FlightEntry) throws -> FlightValidationReport {
        var report = FlightSuggestionEngine.validationReport(for: flight)
        guard let originalID = flight.amendsFlightID else {
            if flight.recordState == .draft, flight.supersededByFlightID != nil {
                report.issues.append(.init(
                    field: "Amendment",
                    message: "A draft cannot identify a superseding flight.",
                    guidance: "Create an amendment from the finalised original instead.",
                    severity: .error
                ))
            }
            return report
        }
        guard let amendmentID = flight.id else {
            report.issues.append(.init(
                field: "Amendment",
                message: "The amendment has not been created by the repository.",
                guidance: "Use Create Amendment on the finalised original.",
                severity: .error
            ))
            return report
        }

        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        do {
            let storedOriginalID = try db.rows(
                "SELECT amends_flight_id FROM flights WHERE id = ?",
                values: [.integer(amendmentID)]
            ).first?["amends_flight_id"]?.int64
            guard storedOriginalID == originalID else {
                throw LogbookRepositoryError.invalidState("The stored amendment link does not match this draft.")
            }
            try ensureAvailableOriginalForAmendment(originalID: originalID, amendmentID: amendmentID, in: db)
        } catch {
            report.issues.append(.init(
                field: "Amendment",
                message: error.localizedDescription,
                guidance: "Return to the finalised original and create a current amendment.",
                severity: .error
            ))
        }
        return report
    }

    @available(*, deprecated, message: "Use saveDraft(_:origin:operationBatchID:) so persistence intent is explicit.")
    public func save(_ flight: FlightEntry) throws -> Int64 {
        try saveDraft(flight)
    }

    public func saveDraft(_ input: FlightEntry, origin: String = "manual", operationBatchID: String? = nil) throws -> Int64 {
        var flight = input
        flight.recordState = .draft
        flight.locked = false
        guard flight.supersededByFlightID == nil else {
            throw LogbookRepositoryError.invalidState("A draft cannot identify a superseding flight.")
        }
        guard flight.id != nil || flight.amendsFlightID == nil else {
            throw LogbookRepositoryError.invalidState("Create amendments from their finalised original instead of assigning an amendment link directly.")
        }
        let db = try currentDatabaseForIntentWrite()
        var savedID: Int64 = 0
        try db.transaction {
            let before = try flight.id.flatMap { try flightRowJSON(id: $0, in: db) }
            if let id = flight.id {
                try ensureEditableDraft(id: id, in: db)
                let storedOriginalID = try db.rows("SELECT amends_flight_id FROM flights WHERE id = ?", values: [.integer(id)]).first?["amends_flight_id"]?.int64
                guard storedOriginalID == flight.amendsFlightID else {
                    throw LogbookRepositoryError.invalidState("An amendment link cannot be changed after the amendment draft is created.")
                }
                if let originalID = storedOriginalID {
                    try ensureAvailableOriginalForAmendment(originalID: originalID, amendmentID: id, in: db)
                }
                try update(flight, id: id, in: db)
                savedID = id
            } else {
                savedID = try insert(flight, in: db)
                flight.id = savedID
            }
            try appendRevision(flightID: savedID, action: before == nil ? "created" : "saved", origin: origin, operationBatchID: operationBatchID, beforeJSON: before, afterJSON: try flightRowJSON(id: savedID, in: db), in: db)
        }
        return savedID
    }

    public func finalise(_ input: FlightEntry, acknowledgeWarnings: Bool, origin: String = "manual") throws -> Int64 {
        guard input.amendsFlightID == nil else {
            throw LogbookRepositoryError.invalidState("Finalise amendments with the amendment-specific action so the original is preserved and superseded atomically.")
        }
        let report = try validationReport(for: input)
        guard !report.hasErrors else { throw LogbookRepositoryError.invalidState("Resolve errors before finalising this entry.") }
        guard report.issues.isEmpty || acknowledgeWarnings else { throw LogbookRepositoryError.warningsRequireAcknowledgement(report) }

        var flight = input
        flight.recordState = .finalised
        flight.locked = true
        let db = try currentDatabaseForIntentWrite()
        var savedID: Int64 = 0
        try db.transaction {
            let before = try flight.id.flatMap { try flightRowJSON(id: $0, in: db) }
            if let id = flight.id {
                try ensureEditableDraft(id: id, in: db)
                try update(flight, id: id, in: db)
                savedID = id
            } else {
                savedID = try insert(flight, in: db)
                flight.id = savedID
            }
            try appendRevision(flightID: savedID, action: "finalised", origin: origin, operationBatchID: nil, beforeJSON: before, afterJSON: try flightRowJSON(id: savedID, in: db), in: db)
        }
        return savedID
    }

    public func beginAmendment(of flightID: Int64, origin: String = "manual") throws -> Int64 {
        let db = try currentDatabaseForIntentWrite()
        var amendmentID: Int64 = 0
        try db.transaction {
            guard var original = try db.rows("SELECT * FROM flights WHERE id = ?", values: [.integer(flightID)]).first.map(Self.flight(from:)) else {
                throw LogbookRepositoryError.invalidState("The original flight no longer exists.")
            }
            try ensureAvailableOriginalForAmendment(originalID: flightID, amendmentID: nil, in: db)
            original.id = nil
            original.sourcePK = nil
            original.locked = false
            original.recordState = .draft
            original.amendsFlightID = flightID
            original.supersededByFlightID = nil
            amendmentID = try insert(original, in: db)
            try appendRevision(flightID: amendmentID, action: "amendment_created", origin: origin, operationBatchID: nil, beforeJSON: nil, afterJSON: try flightRowJSON(id: amendmentID, in: db), in: db)
        }
        return amendmentID
    }

    public func finaliseAmendment(_ amendment: FlightEntry, acknowledgeWarnings: Bool, origin: String = "manual") throws -> Int64 {
        guard let originalID = amendment.amendsFlightID else {
            return try finalise(amendment, acknowledgeWarnings: acknowledgeWarnings, origin: origin)
        }
        let report = try validationReport(for: amendment)
        guard !report.hasErrors else { throw LogbookRepositoryError.invalidState("Resolve errors before finalising this amendment.") }
        guard report.issues.isEmpty || acknowledgeWarnings else { throw LogbookRepositoryError.warningsRequireAcknowledgement(report) }

        var final = amendment
        final.recordState = .finalised
        final.locked = true
        let db = try currentDatabaseForIntentWrite()
        var amendmentID: Int64 = 0
        try db.transaction {
            guard let id = final.id else { throw LogbookRepositoryError.invalidState("Save the amendment draft before finalising it.") }
            try ensureEditableDraft(id: id, in: db)
            let storedOriginalID = try db.rows("SELECT amends_flight_id FROM flights WHERE id = ?", values: [.integer(id)]).first?["amends_flight_id"]?.int64
            guard storedOriginalID == originalID else {
                throw LogbookRepositoryError.invalidState("The amendment no longer links to the original flight shown in the editor.")
            }
            try ensureAvailableOriginalForAmendment(originalID: originalID, amendmentID: id, in: db)
            let amendmentBefore = try flightRowJSON(id: id, in: db)
            try update(final, id: id, in: db)
            amendmentID = id
            let originalBefore = try flightRowJSON(id: originalID, in: db)
            try db.execute("UPDATE flights SET record_state = 'superseded', locked = 1, superseded_by_flight_id = ?, modified_at = ? WHERE id = ? AND record_state = 'finalised' AND superseded_by_flight_id IS NULL", values: [.integer(id), .text(Self.nowText()), .integer(originalID)])
            guard db.changes == 1 else {
                throw LogbookRepositoryError.invalidState("The original flight changed while the amendment was being finalised. No changes were committed.")
            }
            try appendRevision(flightID: originalID, action: "superseded", origin: origin, operationBatchID: nil, beforeJSON: originalBefore, afterJSON: try flightRowJSON(id: originalID, in: db), in: db)
            try appendRevision(flightID: id, action: "amendment_finalised", origin: origin, operationBatchID: nil, beforeJSON: amendmentBefore, afterJSON: try flightRowJSON(id: id, in: db), in: db)
        }
        return amendmentID
    }

    public func moveToTrash(id: Int64, origin: String = "manual") throws {
        let db = try currentDatabaseForIntentWrite()
        try db.transaction {
            try ensureEditableDraft(id: id, in: db)
            let before = try flightRowJSON(id: id, in: db)
            try db.execute("UPDATE flights SET record_state = 'trashed', locked = 0, modified_at = ? WHERE id = ?", values: [.text(Self.nowText()), .integer(id)])
            try appendRevision(flightID: id, action: "trashed", origin: origin, operationBatchID: nil, beforeJSON: before, afterJSON: try flightRowJSON(id: id, in: db), in: db)
        }
    }

    public func restoreFromTrash(id: Int64, origin: String = "manual") throws {
        let db = try currentDatabaseForIntentWrite()
        try db.transaction {
            guard let row = try db.rows("SELECT record_state, amends_flight_id FROM flights WHERE id = ?", values: [.integer(id)]).first,
                  row["record_state"]?.string == FlightRecordState.trashed.rawValue else {
                throw LogbookRepositoryError.invalidState("Only a trashed draft can be restored.")
            }
            if let originalID = row["amends_flight_id"]?.int64 {
                try ensureAvailableOriginalForAmendment(originalID: originalID, amendmentID: id, in: db)
            }
            let before = try flightRowJSON(id: id, in: db)
            try db.execute("UPDATE flights SET record_state = 'draft', modified_at = ? WHERE id = ?", values: [.text(Self.nowText()), .integer(id)])
            try appendRevision(flightID: id, action: "restored", origin: origin, operationBatchID: nil, beforeJSON: before, afterJSON: try flightRowJSON(id: id, in: db), in: db)
        }
    }

    public func restoreFromTrash(ids: Set<Int64>, origin: String = "manual") throws {
        guard !ids.isEmpty else { return }
        let db = try currentDatabaseForIntentWrite()
        try db.transaction {
            for id in ids {
                guard let row = try db.rows("SELECT record_state, amends_flight_id FROM flights WHERE id = ?", values: [.integer(id)]).first,
                      row["record_state"]?.string == FlightRecordState.trashed.rawValue else {
                    throw LogbookRepositoryError.invalidState("Every selected record must be a trashed draft.")
                }
                if let originalID = row["amends_flight_id"]?.int64 {
                    try ensureAvailableOriginalForAmendment(originalID: originalID, amendmentID: id, in: db)
                }
                let before = try flightRowJSON(id: id, in: db)
                try db.execute("UPDATE flights SET record_state = 'draft', modified_at = ? WHERE id = ?", values: [.text(Self.nowText()), .integer(id)])
                try appendRevision(flightID: id, action: "restored", origin: origin, operationBatchID: nil, beforeJSON: before, afterJSON: try flightRowJSON(id: id, in: db), in: db)
            }
        }
    }

    public func trash(query: HistoryQuery = HistoryQuery()) throws -> [TrashItem] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        let rows = try db.rows("SELECT * FROM flights WHERE record_state = 'trashed' ORDER BY modified_at DESC")
        return try rows.compactMap { row in
            let flight = Self.flight(from: row)
            guard let id = flight.id else { return nil }
            let revision = try db.rows("SELECT origin, created_at FROM flight_revisions WHERE flight_id = ? AND action = 'trashed' ORDER BY id DESC LIMIT 1", values: [.integer(id)]).first
            let item = TrashItem(id: id, flight: flight, trashedAt: Self.date(from: revision?["created_at"]?.string ?? ""), origin: revision?["origin"]?.string ?? "")
            guard query.text.isEmpty || [flight.routeDisplay, flight.aircraftID, flight.flightNumber, flight.remarks].joined(separator: " ").localizedCaseInsensitiveContains(query.text) else { return nil }
            return item
        }
    }

    public func history(query: HistoryQuery = HistoryQuery()) throws -> [FlightRevision] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        var sql = "SELECT * FROM flight_revisions"
        var values: [SQLiteValue] = []
        if let flightID = query.flightID { sql += " WHERE flight_id = ?"; values.append(.integer(flightID)) }
        sql += " ORDER BY id DESC"
        return try db.rows(sql, values: values).compactMap { row in
            let revision = FlightRevision(id: row["id"]?.int64, flightID: row["flight_id"]?.int64 ?? 0, action: row["action"]?.string ?? "", origin: row["origin"]?.string ?? "", operationBatchID: Self.optionalText(row["operation_batch_id"]), beforeJSON: Self.optionalText(row["before_json"]), afterJSON: Self.optionalText(row["after_json"]), createdAt: Self.date(from: row["created_at"]?.string ?? "") ?? Date())
            guard query.text.isEmpty || [revision.action, revision.origin, revision.beforeJSON ?? "", revision.afterJSON ?? ""].joined(separator: " ").localizedCaseInsensitiveContains(query.text) else { return nil }
            return revision
        }
    }

    public func revisionDiffs(for revision: FlightRevision) -> [FlightRevisionDiff] {
        func object(_ json: String?) -> [String: Any] { guard let json, let data = json.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }; return value }
        let before = object(revision.beforeJSON), after = object(revision.afterJSON)
        return Set(before.keys).union(after.keys).sorted().compactMap { key in
            let lhs = before[key].map { String(describing: $0) }, rhs = after[key].map { String(describing: $0) }
            return lhs == rhs ? nil : FlightRevisionDiff(field: key, beforeValue: lhs, afterValue: rhs)
        }
    }

    public func revisions(for flightID: Int64) throws -> [FlightRevision] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        return try db.rows("SELECT * FROM flight_revisions WHERE flight_id = ? ORDER BY id DESC", values: [.integer(flightID)]).map { row in
            FlightRevision(
                id: row["id"]?.int64,
                flightID: row["flight_id"]?.int64 ?? flightID,
                action: row["action"]?.string ?? "",
                origin: row["origin"]?.string ?? "",
                operationBatchID: Self.optionalText(row["operation_batch_id"]),
                beforeJSON: Self.optionalText(row["before_json"]),
                afterJSON: Self.optionalText(row["after_json"]),
                createdAt: Self.date(from: row["created_at"]?.string ?? "") ?? Date()
            )
        }
    }

    public func prepareImport(from sourceURL: URL) throws -> ImportPlan {
        guard sourceURL.standardizedFileURL.path != paths.workingDatabase.standardizedFileURL.path else {
            throw LogbookRepositoryError.invalidState("Choose the LogTen Pro database, not the Blackbox working database.")
        }
        let artifactToken = UUID()
        let folder = Self.importArtifactRoot(for: artifactToken)
        let snapshotURL = folder.appendingPathComponent("LogTen-Source.sqlite")
        let candidateURL = folder.appendingPathComponent("Candidates.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let selectedSource = try SQLiteConnection(path: sourceURL.path, readOnly: true)
            try selectedSource.backup(to: snapshotURL.path)
            let snapshot = try SQLiteConnection(path: snapshotURL.path, readOnly: true)
            guard try snapshot.integrityCheck().lowercased() == "ok" else {
                throw LogbookRepositoryError.integrityCheckFailed("The private LogTen import snapshot did not pass integrity_check.")
            }
            let proposed = try logTenFlightRows(from: snapshot).map(Self.flightFromLogTen(row:))
            guard !proposed.isEmpty else {
                throw LogbookRepositoryError.invalidState("No LogTen Pro flights were found in the selected database.")
            }
            var plan = try prepareImportPlan(proposed: proposed, sourceURL: sourceURL, sourceSnapshotURL: snapshotURL, sourceKind: .logTen)
            plan.artifactToken = artifactToken
            plan.candidateSnapshotURL = candidateURL
            plan.candidateSnapshotFileDigest = try Self.writeCandidateSnapshot(proposed, to: candidateURL)
            plan.sealedPlanDigest = try Self.importPlanContentDigest(plan)
            return plan
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Routes already-parsed document/OCR candidates through the same preview,
    /// selection, amendment, revision, staging, and verification pipeline as a
    /// LogTen import. Identifiers are deterministic and deliberately negative,
    /// keeping them separate from LogTen Core Data primary keys.
    public func prepareDocumentImport(candidates: [FlightEntry], sourceURL: URL) throws -> ImportPlan {
        guard !candidates.isEmpty else {
            throw LogbookRepositoryError.invalidState("No document flight candidates were found.")
        }
        let artifactToken = UUID()
        let folder = Self.importArtifactRoot(for: artifactToken)
        let candidateURL = folder.appendingPathComponent("Candidates.json")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let proposed = try candidates.enumerated().map { offset, candidate -> FlightEntry in
                var flight = candidate
                flight.id = nil
                flight.sourcePK = try Self.documentSourceIdentifier(sourceURL: sourceURL, ordinal: offset, flight: candidate)
                flight.recordState = .draft
                flight.locked = false
                flight.amendsFlightID = nil
                flight.supersededByFlightID = nil
                return flight
            }
            var plan = try prepareImportPlan(proposed: proposed, sourceURL: sourceURL, sourceSnapshotURL: nil, sourceKind: .document)
            plan.artifactToken = artifactToken
            plan.candidateSnapshotURL = candidateURL
            plan.candidateSnapshotFileDigest = try Self.writeCandidateSnapshot(proposed, to: candidateURL)
            plan.sealedPlanDigest = try Self.importPlanContentDigest(plan)
            return plan
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    public func discardImportPlan(_ plan: ImportPlan) {
        guard let root = try? validatedImportArtifactRoot(for: plan) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    public func discardRestorePlan(_ plan: RestorePlan) {
        guard let root = try? validatedRestoreArtifactRoot(for: plan) else { return }
        try? FileManager.default.removeItem(at: root)
    }

    private func prepareImportPlan(proposed: [FlightEntry], sourceURL: URL, sourceSnapshotURL: URL?, sourceKind: ImportSourceKind) throws -> ImportPlan {
        let grouped = Dictionary(grouping: proposed.compactMap { flight -> (Int64, FlightEntry)? in
            flight.sourcePK.map { ($0, flight) }
        }, by: { $0.0 })
        let duplicates = grouped.filter { $0.value.count > 1 }.keys.sorted()
        let canonicalProposed = grouped.keys.sorted().compactMap { grouped[$0]?.first?.1 }
        let existing = try flights(query: FlightQuery(recordStates: Set(FlightRecordState.allCases)))
        let existingBySource = Dictionary(uniqueKeysWithValues: existing.compactMap { flight in flight.sourcePK.map { ($0, flight) } })
        var additions: [FlightEntry] = []
        var changes: [ImportChange] = []
        var unchangedRecords: [ImportRecordIdentity] = []
        var conflicts: [String] = []
        var conflictSourceIDs: Set<Int64> = []
        for sourcePK in duplicates {
            let values = grouped[sourcePK]?.map(\.1) ?? []
            if Set(try values.map(Self.flightEntryDigest)).count > 1 {
                conflicts.append("Source \(sourcePK) contains different records with the same identifier.")
                conflictSourceIDs.insert(sourcePK)
            }
        }
        for flight in canonicalProposed {
            guard let sourcePK = flight.sourcePK else { continue }
            guard let current = existingBySource[sourcePK] else { additions.append(flight); continue }
            let fields = Self.changedImportFields(current: current, proposed: flight)
            if fields.isEmpty { unchangedRecords.append(Self.importRecordIdentity(for: current)) }
            else if current.recordState == .superseded || current.recordState == .trashed {
                conflicts.append("Source \(sourcePK) matches a \(current.recordState.displayName.lowercased()) Blackbox record.")
                conflictSourceIDs.insert(sourcePK)
                changes.append(ImportChange(sourcePK: sourcePK, existing: current, proposed: flight, changedFields: fields))
            } else { changes.append(ImportChange(sourcePK: sourcePK, existing: current, proposed: flight, changedFields: fields)) }
        }
        let sourceKeys = Set(canonicalProposed.compactMap(\.sourcePK))
        let relevantExistingKeys = existingBySource.keys.filter { sourceKind == .logTen ? $0 >= 0 : $0 < 0 }
        let sourceOnlyOmissions = relevantExistingKeys
            .filter { !sourceKeys.contains($0) }
            .sorted()
            .compactMap { existingBySource[$0] }
            .map(Self.importRecordIdentity(for:))
        let additionSelections = additions.flatMap { flight -> [ImportFieldSelection] in
            guard let sourcePK = flight.sourcePK else { return [] }
            return Self.importableFields.map { field in
                ImportFieldSelection(sourcePK: sourcePK, field: field, blackboxValue: "", sourceValue: Self.importDisplayValue(field: field, flight: flight))
            }
        }
        let changeSelections = changes.flatMap { change in
            change.changedFields.map { field in
                ImportFieldSelection(sourcePK: change.sourcePK, field: field, blackboxValue: Self.importDisplayValue(field: field, flight: change.existing), sourceValue: Self.importDisplayValue(field: field, flight: change.proposed))
            }
        }
        var actions: [Int64: ImportResultingAction] = [:]
        for flight in additions { if let sourcePK = flight.sourcePK { actions[sourcePK] = .createDraft } }
        for change in changes {
            switch change.existing.recordState {
            case .draft: actions[change.sourcePK] = .updateDraft
            case .finalised: actions[change.sourcePK] = .createAmendment
            case .superseded, .trashed: actions[change.sourcePK] = .ignore
            }
        }
        let active = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        return ImportPlan(
            sourceURL: sourceURL,
            sourceSnapshotURL: sourceSnapshotURL,
            additions: additions,
            changes: changes,
            unchangedCount: unchangedRecords.count,
            unchangedRecords: unchangedRecords,
            duplicateSourceIDs: duplicates,
            conflicts: conflicts,
            conflictSourceIDs: conflictSourceIDs.sorted(),
            missingFromSourceCount: sourceOnlyOmissions.count,
            sourceOnlyOmissions: sourceOnlyOmissions,
            fieldSelections: additionSelections + changeSelections,
            resultingActions: actions,
            sourceKind: sourceKind,
            baselineFlightDigest: try canonicalFlightDigest(in: active),
            sourceSnapshotDigest: try Self.flightEntriesDigest(proposed)
        )
    }

    @discardableResult
    public func applyImport(_ plan: ImportPlan, injectingFailureAt failureStage: TransactionFailureStage? = nil) throws -> ImportPlan {
        let artifactRoot = try validatedImportArtifactRoot(for: plan)
        defer { discardImportPlan(plan) }
        let sealedCandidates = try verifiedCandidateSnapshot(for: plan)
        guard plan.isApplicable else { throw LogbookRepositoryError.invalidState("Resolve duplicate source identifiers and conflicts before importing.") }
        let baseline: (version: Int, digest: String, summary: LogbookSummary, expected: ImportExpectedManifest) = try {
            let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            return (
                try schemaVersion(in: db),
                try canonicalFlightDigest(in: db),
                try summary(in: db),
                try expectedImportManifest(for: plan, in: db)
            )
        }()
        guard baseline.version == Self.currentSchemaVersion,
              plan.baselineFlightDigest == baseline.digest else {
            throw LogbookRepositoryError.stalePlan
        }
        guard baseline.expected.affectedCount > 0 else {
            throw LogbookRepositoryError.invalidState("This import has no selected additions or field changes to apply.")
        }
        if plan.sourceKind == .logTen {
            guard let snapshotURL = plan.sourceSnapshotURL,
                  FileManager.default.fileExists(atPath: snapshotURL.path) else {
                throw LogbookRepositoryError.stalePlan
            }
            let source = try SQLiteConnection(path: snapshotURL.path, readOnly: true)
            let proposed = try logTenFlightRows(from: source).map(Self.flightFromLogTen(row:))
            guard try Self.flightEntriesDigest(proposed) == plan.sourceSnapshotDigest,
                  try Self.flightEntriesDigest(proposed) == Self.flightEntriesDigest(sealedCandidates),
                  snapshotURL.deletingLastPathComponent().standardizedFileURL == artifactRoot else {
                throw LogbookRepositoryError.stalePlan
            }
        }

        try FileManager.default.createDirectory(at: paths.backupFolder, withIntermediateDirectories: true)
        let backupURL = paths.backupFolder.appendingPathComponent("Blackbox-pre-import-\(Self.backupTimestamp()).sqlite")
        let beforeSummary = baseline.summary
        var batch = OperationBatch(
            kind: plan.sourceKind.operationKind,
            source: plan.sourceURL.path,
            status: "applying",
            summary: "\(plan.additions.count) additions, \(plan.changes.count) changes",
            backupPath: backupURL.path,
            beforeTotalMinutes: beforeSummary.totalMinutes,
            artifactURLs: [backupURL]
        )
        let workFolder = paths.workingDatabase.deletingLastPathComponent()
            .appendingPathComponent(".Blackbox-import-\(UUID().uuidString)", isDirectory: true)
        let stagedURL = workFolder.appendingPathComponent("Staged.sqlite")
        let activationURL = workFolder.appendingPathComponent("Activation.sqlite")
        var activated = false
        var failureBoundary: TransactionFailureStage = .backupCreation
        defer { try? FileManager.default.removeItem(at: workFolder) }

        do {
            if failureStage == .backupCreation {
                throw LogbookRepositoryError.integrityCheckFailed("Injected import backup failure.")
            }
            try makeVerifiedSnapshot(from: paths.workingDatabase, to: backupURL)
            failureBoundary = .staging
            if failureStage == .staging {
                throw LogbookRepositoryError.integrityCheckFailed("Injected import staging failure.")
            }
            try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
            try makeVerifiedSnapshot(from: backupURL, to: stagedURL)

            failureBoundary = .transaction
            let staged = try SQLiteConnection(path: stagedURL.path)
            try staged.transaction {
                try write(batch: batch, in: staged)
                if failureStage == .transaction {
                    throw LogbookRepositoryError.integrityCheckFailed("Injected import transaction failure.")
                }
                for proposed in plan.additions {
                    guard Self.additionHasIncludedField(proposed, selections: plan.fieldSelections) else { continue }
                    var flight = try Self.applyingAdditionSelections(to: proposed, selections: plan.fieldSelections)
                    guard let sourcePK = flight.sourcePK else { continue }
                    let action = plan.resolutionActions[sourcePK] ?? plan.resultingActions[sourcePK]
                    if plan.duplicateDecisions[sourcePK] == .exclude || action == .linkAndSkip || action == .ignore { continue }
                    guard action == .createDraft || action == .importSeparateDraft else {
                        throw LogbookRepositoryError.invalidState("The preview contains an invalid action for source \(sourcePK).")
                    }
                    flight.recordState = .draft
                    flight.locked = false
                    flight.amendsFlightID = nil
                    flight.supersededByFlightID = nil
                    let id = try insert(flight, in: staged)
                    try appendRevision(flightID: id, action: "imported", origin: plan.sourceKind.revisionOrigin, operationBatchID: batch.id, beforeJSON: nil, afterJSON: try flightRowJSON(id: id, in: staged), in: staged)
                }
                for change in plan.changes {
                    guard let id = change.existing.id else { continue }
                    let action = plan.resolutionActions[change.sourcePK] ?? plan.resultingActions[change.sourcePK]
                    if plan.duplicateDecisions[change.sourcePK] == .exclude || action == .linkAndSkip || action == .ignore { continue }
                    var flight = Self.applyingFieldSelections(for: change, selections: plan.fieldSelections)
                    if flight == change.existing { continue }
                    if action == .importSeparateDraft {
                        flight.id = nil
                        flight.sourcePK = nil
                        flight.recordState = .draft
                        flight.locked = false
                        flight.amendsFlightID = nil
                        flight.supersededByFlightID = nil
                        let separateID = try insert(flight, in: staged)
                        try appendRevision(flightID: separateID, action: "imported_separate_draft", origin: plan.sourceKind.revisionOrigin, operationBatchID: batch.id, beforeJSON: nil, afterJSON: try flightRowJSON(id: separateID, in: staged), in: staged)
                    } else if change.existing.recordState == .finalised {
                        guard action == .createAmendment else {
                            throw LogbookRepositoryError.invalidState("A finalised import match can only create an amendment.")
                        }
                        try ensureAvailableOriginalForAmendment(originalID: id, amendmentID: nil, in: staged)
                        flight.id = nil
                        flight.sourcePK = nil
                        flight.recordState = .draft
                        flight.locked = false
                        flight.amendsFlightID = id
                        flight.supersededByFlightID = nil
                        let amendmentID = try insert(flight, in: staged)
                        try appendRevision(flightID: amendmentID, action: "import_amendment_created", origin: plan.sourceKind.revisionOrigin, operationBatchID: batch.id, beforeJSON: nil, afterJSON: try flightRowJSON(id: amendmentID, in: staged), in: staged)
                    } else {
                        guard change.existing.recordState == .draft,
                              action == .updateDraft else {
                            throw LogbookRepositoryError.invalidState("Only a draft import match can be updated in place.")
                        }
                        let before = try flightRowJSON(id: id, in: staged)
                        flight.id = id
                        flight.recordState = .draft
                        flight.locked = false
                        flight.amendsFlightID = change.existing.amendsFlightID
                        flight.supersededByFlightID = nil
                        try update(flight, id: id, in: staged)
                        try appendRevision(flightID: id, action: "import_updated", origin: plan.sourceKind.revisionOrigin, operationBatchID: batch.id, beforeJSON: before, afterJSON: try flightRowJSON(id: id, in: staged), in: staged)
                    }
                }
                if plan.sourceKind == .logTen {
                    try staged.execute("INSERT OR REPLACE INTO settings(key, value) VALUES('source_backup', ?)", values: [.text(plan.sourceURL.path)])
                }
            }

            failureBoundary = .postTransactionVerification
            if failureStage == .postTransactionVerification {
                throw LogbookRepositoryError.integrityCheckFailed("Injected post-import verification failure.")
            }
            var verification = try operationVerification(
                in: staged,
                batchID: batch.id,
                expectedFlightCount: baseline.expected.flightCount,
                expectedTotalMinutes: baseline.expected.totalMinutes,
                expectedRevisionCount: baseline.expected.revisionCount,
                expectedFlightDigest: baseline.expected.flightDigest
            )
            guard verification.passed else {
                throw LogbookRepositoryError.integrityCheckFailed("The staged import did not match its independently calculated counts, totals, revisions, schema, and flight digest.")
            }
            batch.status = "completed"
            batch.completedAt = Date()
            batch.affectedCount = baseline.expected.affectedCount
            batch.afterTotalMinutes = baseline.expected.totalMinutes
            batch.verification = verification
            batch.recoveryOutcome = "Verified recovery point retained"
            try staged.transaction { try write(batch: batch, in: staged) }

            try makeVerifiedSnapshot(from: stagedURL, to: activationURL)
            let activation = try SQLiteConnection(path: activationURL.path, readOnly: true)
            verification = try operationVerification(
                in: activation,
                batchID: batch.id,
                expectedFlightCount: baseline.expected.flightCount,
                expectedTotalMinutes: baseline.expected.totalMinutes,
                expectedRevisionCount: baseline.expected.revisionCount,
                expectedFlightDigest: baseline.expected.flightDigest
            )
            guard verification.passed else {
                throw LogbookRepositoryError.integrityCheckFailed("The self-contained import candidate failed independent verification.")
            }
            failureBoundary = .beforeAtomicSwap
            if failureStage == .atomicSwap || failureStage == .beforeAtomicSwap {
                throw LogbookRepositoryError.integrityCheckFailed("Injected import atomic-swap failure.")
            }
            activated = true
            try activateDatabase(at: activationURL)
            failureBoundary = .afterAtomicSwap
            if failureStage == .afterAtomicSwap {
                throw LogbookRepositoryError.integrityCheckFailed("Injected import post-swap failure.")
            }

            let active = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            verification = try operationVerification(
                in: active,
                batchID: batch.id,
                expectedFlightCount: baseline.expected.flightCount,
                expectedTotalMinutes: baseline.expected.totalMinutes,
                expectedRevisionCount: baseline.expected.revisionCount,
                expectedFlightDigest: baseline.expected.flightDigest
            )
            guard verification.passed else {
                throw LogbookRepositoryError.integrityCheckFailed("The activated import database failed verification.")
            }
            batch.verification = verification
            try recordOperation(batch)
        } catch let operationError {
            var recovery = "Original database remained active"
            var recoveryError: Error?
            if activated {
                do {
                    try restoreDatabase(from: backupURL)
                    recovery = "Verified recovery backup restored"
                } catch {
                    recoveryError = error
                    recovery = "Recovery failed: \(error.localizedDescription)"
                }
            }
            retainFailedOperation(
                from: batch,
                stage: failureStage ?? failureBoundary,
                recovery: recovery,
                persistToDatabase: recoveryError == nil
            )
            if let recoveryError {
                throw LogbookRepositoryError.recoveryFailed(
                    operation: "Import",
                    operationMessage: operationError.localizedDescription,
                    recoveryMessage: recoveryError.localizedDescription
                )
            }
            throw LogbookRepositoryError.operationFailedWithVerifiedRecovery(
                operation: "Import",
                operationMessage: operationError.localizedDescription,
                recoveryOutcome: recovery
            )
        }
        return plan
    }

    private var operationAuditFolder: URL {
        paths.backupFolder.appendingPathComponent("Failed Operation Audits", isDirectory: true)
    }

    private func retainFailedOperation(
        from batch: OperationBatch,
        stage: TransactionFailureStage,
        recovery: String,
        persistToDatabase: Bool = true
    ) {
        var failed = batch
        failed.status = "failed"
        failed.failureStage = stage.rawValue
        failed.recoveryOutcome = recovery
        failed.completedAt = Date()
        if persistToDatabase {
            do {
                try recordOperation(failed)
                return
            } catch {
                // Fall through to the flight-free diagnostic artifact.
            }
        }
        _ = try? OperationAuditStore.store(failed, in: operationAuditFolder)
    }

    /// Imports any flight-free failure diagnostics left when the database was
    /// unavailable, then archives them outside the pending queue.
    public func recoverPendingOperationAudits() throws -> Int {
        let pending = try OperationAuditStore.pending(in: operationAuditFolder)
        for item in pending {
            try recordOperation(item.batch)
            _ = try OperationAuditStore.markImported(item.url)
        }
        return pending.count
    }

    /// Records operation metadata only. This intent-specific API never inserts,
    /// updates, deletes, normalises, or migrates a flight row.
    public func recordOperation(_ batch: OperationBatch) throws {
        let db = try SQLiteConnection(path: paths.workingDatabase.path)
        guard try schemaVersion(in: db) == Self.currentSchemaVersion else {
            throw LogbookRepositoryError.invalidState("Operation history can be recorded only after the reviewed database upgrade.")
        }
        try db.transaction { try write(batch: batch, in: db) }
    }

    private static let persistedColumns = [
        "source_pk", "date", "departure", "arrival", "route", "aircraft_id", "aircraft_type", "flight_number", "operation", "entry_kind", "pilot_function",
        "total_minutes", "pic_minutes", "pic_day_minutes", "pic_night_minutes", "picus_minutes", "picus_day_minutes", "picus_night_minutes",
        "copilot_minutes", "copilot_day_minutes", "copilot_night_minutes", "dual_minutes", "instructor_minutes", "night_minutes", "instrument_minutes", "cross_country_minutes", "fstd_minutes",
        "pilot_flying", "day_takeoffs", "night_takeoffs", "total_takeoffs", "day_landings", "night_landings", "total_landings", "passenger_count", "distance_nm",
        "crew_names", "crew_roles", "departure_lat", "departure_lon", "arrival_lat", "arrival_lon", "remarks", "signature_name", "signature_reference", "locked",
        "record_state", "amends_flight_id", "superseded_by_flight_id", "modified_at"
    ]

    private func persistedValues(for flight: FlightEntry) -> [SQLiteValue] {
        [
            flight.sourcePK.map(SQLiteValue.integer) ?? .null,
            .text(LogbookFormatters.isoFormatter.string(from: flight.date)),
            .text(flight.departure), .text(flight.arrival), .text(flight.route), .text(flight.aircraftID), .text(flight.aircraftType), .text(flight.flightNumber),
            .text(flight.operation), .text(flight.entryKind), .text(flight.pilotFunction),
            .integer(Int64(flight.totalMinutes)), .integer(Int64(flight.picMinutes)), .integer(Int64(flight.picDayMinutes)), .integer(Int64(flight.picNightMinutes)),
            .integer(Int64(flight.picusMinutes)), .integer(Int64(flight.picusDayMinutes)), .integer(Int64(flight.picusNightMinutes)),
            .integer(Int64(flight.copilotMinutes)), .integer(Int64(flight.copilotDayMinutes)), .integer(Int64(flight.copilotNightMinutes)),
            .integer(Int64(flight.dualMinutes)), .integer(Int64(flight.instructorMinutes)), .integer(Int64(flight.nightMinutes)), .integer(Int64(flight.instrumentMinutes)),
            .integer(Int64(flight.crossCountryMinutes)), .integer(Int64(flight.fstdMinutes)), .integer(flight.pilotFlying ? 1 : 0),
            .integer(Int64(flight.dayTakeoffs)), .integer(Int64(flight.nightTakeoffs)), .integer(Int64(flight.totalTakeoffs)),
            .integer(Int64(flight.dayLandings)), .integer(Int64(flight.nightLandings)), .integer(Int64(flight.totalLandings)),
            .integer(Int64(flight.passengerCount)), .real(flight.distanceNM), .text(flight.crewNames), .text(flight.crewRoles),
            flight.departureLatitude.map(SQLiteValue.real) ?? .null, flight.departureLongitude.map(SQLiteValue.real) ?? .null,
            flight.arrivalLatitude.map(SQLiteValue.real) ?? .null, flight.arrivalLongitude.map(SQLiteValue.real) ?? .null,
            .text(flight.remarks), .text(flight.signatureName), .text(flight.signatureReference), .integer(flight.recordState == .finalised || flight.recordState == .superseded ? 1 : 0),
            .text(flight.recordState.rawValue), flight.amendsFlightID.map(SQLiteValue.integer) ?? .null, flight.supersededByFlightID.map(SQLiteValue.integer) ?? .null,
            .text(Self.nowText())
        ]
    }

    private func insert(_ flight: FlightEntry, in db: SQLiteConnection) throws -> Int64 {
        let columns = Self.persistedColumns.joined(separator: ", ")
        let values = persistedValues(for: flight)
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        try db.execute("INSERT INTO flights (\(columns)) VALUES (\(placeholders))", values: values)
        return db.lastInsertRowID()
    }

    private func update(_ flight: FlightEntry, id: Int64, in db: SQLiteConnection) throws {
        let assignments = Self.persistedColumns.map { "\($0) = ?" }.joined(separator: ", ")
        try db.execute("UPDATE flights SET \(assignments) WHERE id = ?", values: persistedValues(for: flight) + [.integer(id)])
        guard db.changes == 1 else {
            throw LogbookRepositoryError.invalidState("The flight entry changed or disappeared before it could be saved.")
        }
    }

    private func ensureEditableDraft(id: Int64, in db: SQLiteConnection) throws {
        guard let row = try db.rows("SELECT record_state FROM flights WHERE id = ?", values: [.integer(id)]).first else {
            throw LogbookRepositoryError.invalidState("The flight entry no longer exists.")
        }
        guard row["record_state"]?.string == FlightRecordState.draft.rawValue else {
            throw LogbookRepositoryError.immutableRecord
        }
    }

    private func ensureAvailableOriginalForAmendment(originalID: Int64, amendmentID: Int64?, in db: SQLiteConnection) throws {
        guard let original = try db.rows(
            "SELECT record_state, superseded_by_flight_id FROM flights WHERE id = ?",
            values: [.integer(originalID)]
        ).first else {
            throw LogbookRepositoryError.invalidState("The original flight no longer exists.")
        }
        guard original["record_state"]?.string == FlightRecordState.finalised.rawValue,
              original["superseded_by_flight_id"]?.int64 == nil else {
            throw LogbookRepositoryError.invalidState("Only an available finalised flight can be amended.")
        }

        var values: [SQLiteValue] = [.integer(originalID)]
        var exclusion = ""
        if let amendmentID {
            exclusion = " AND id != ?"
            values.append(.integer(amendmentID))
        }
        let activeSiblingCount = try db.rows("""
        SELECT COUNT(*) AS count FROM flights
        WHERE amends_flight_id = ? AND record_state IN ('draft', 'finalised')\(exclusion)
        """, values: values).first?["count"]?.int ?? 0
        guard activeSiblingCount == 0 else {
            throw LogbookRepositoryError.invalidState("This finalised flight already has an active amendment.")
        }
    }

    private func flightRowJSON(id: Int64, in db: SQLiteConnection) throws -> String? {
        guard let flight = try db.rows("SELECT * FROM flights WHERE id = ?", values: [.integer(id)]).first.map(Self.flight(from:)) else { return nil }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(flight), encoding: .utf8)
    }

    private func appendRevision(flightID: Int64, action: String, origin: String, operationBatchID: String?, beforeJSON: String?, afterJSON: String?, in db: SQLiteConnection) throws {
        try db.execute("""
        INSERT INTO flight_revisions(flight_id, action, origin, operation_batch_id, before_json, after_json, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?)
        """, values: [
            .integer(flightID), .text(action), .text(origin), operationBatchID.map(SQLiteValue.text) ?? .null,
            beforeJSON.map(SQLiteValue.text) ?? .null, afterJSON.map(SQLiteValue.text) ?? .null, .text(Self.nowText())
        ])
    }

    private func write(batch: OperationBatch, in db: SQLiteConnection) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let verificationJSON = batch.verification.flatMap { try? encoder.encode($0) }.flatMap { String(data: $0, encoding: .utf8) }
        let artifactsJSON = (try? encoder.encode(batch.artifactURLs)).flatMap { String(data: $0, encoding: .utf8) }
        try db.execute("""
        INSERT OR REPLACE INTO operation_batches(id, kind, source, status, summary, backup_path, created_at, completed_at, affected_count, before_total_minutes, after_total_minutes, verification_json, failure_stage, recovery_outcome, artifact_urls_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, values: [
            .text(batch.id), .text(batch.kind), .text(batch.source), .text(batch.status), .text(batch.summary),
            batch.backupPath.map(SQLiteValue.text) ?? .null, .text(LogbookFormatters.isoFormatter.string(from: batch.createdAt)),
            batch.completedAt.map { .text(LogbookFormatters.isoFormatter.string(from: $0)) } ?? .null,
            .integer(Int64(batch.affectedCount)), .integer(Int64(batch.beforeTotalMinutes)), .integer(Int64(batch.afterTotalMinutes)),
            verificationJSON.map(SQLiteValue.text) ?? .null, batch.failureStage.map(SQLiteValue.text) ?? .null,
            batch.recoveryOutcome.map(SQLiteValue.text) ?? .null, artifactsJSON.map(SQLiteValue.text) ?? .null
        ])
    }

    public func operationBatches() throws -> [OperationBatch] {
        let db = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try db.rows("SELECT * FROM operation_batches ORDER BY created_at DESC").map { row in
            let verification = Self.optionalText(row["verification_json"]).flatMap { try? decoder.decode(OperationVerification.self, from: Data($0.utf8)) }
            let artifacts = Self.optionalText(row["artifact_urls_json"]).flatMap { try? decoder.decode([URL].self, from: Data($0.utf8)) } ?? []
            return OperationBatch(
                id: row["id"]?.string ?? "",
                kind: row["kind"]?.string ?? "",
                source: row["source"]?.string ?? "",
                status: row["status"]?.string ?? "",
                summary: row["summary"]?.string ?? "",
                backupPath: Self.optionalText(row["backup_path"]),
                createdAt: Self.date(from: row["created_at"]?.string ?? "") ?? Date(),
                completedAt: Self.date(from: row["completed_at"]?.string ?? ""),
                affectedCount: row["affected_count"]?.int ?? 0,
                beforeTotalMinutes: row["before_total_minutes"]?.int ?? 0,
                afterTotalMinutes: row["after_total_minutes"]?.int ?? 0,
                verification: verification,
                failureStage: Self.optionalText(row["failure_stage"]),
                recoveryOutcome: Self.optionalText(row["recovery_outcome"]),
                artifactURLs: artifacts
            )
        }
    }

    public func operations(query: HistoryQuery = HistoryQuery()) throws -> [OperationBatch] {
        try operationBatches().filter { batch in
            (query.text.isEmpty || [batch.kind, batch.source, batch.summary, batch.status].joined(separator: " ").localizedCaseInsensitiveContains(query.text)) &&
            (query.operationKinds.isEmpty || query.operationKinds.contains(batch.kind)) &&
            (query.statuses.isEmpty || query.statuses.contains(batch.status))
        }
    }

    public func verifyBackup(at url: URL) throws -> OperationVerification {
        let db = try SQLiteConnection(path: url.path, readOnly: true)
        let integrity = try db.integrityCheck()
        let foreignKeyIssues = try foreignKeyIssueDescriptions(in: db)
        let amendmentIssues = try amendmentPreflightIssues(in: db)
        let summary = try summary(in: db)
        let version = try schemaVersion(in: db)
        let digest = try canonicalFlightDigest(in: db)
        return OperationVerification(
            integrityCheck: integrity,
            schemaVersion: version,
            expectedSchemaVersion: version,
            expectedFlightCount: summary.flightCount,
            actualFlightCount: summary.flightCount,
            expectedTotalMinutes: summary.totalMinutes,
            actualTotalMinutes: summary.totalMinutes,
            revisionCoverageComplete: foreignKeyIssues.isEmpty && amendmentIssues.isEmpty,
            expectedFlightDigest: digest,
            actualFlightDigest: digest,
            foreignKeyIssues: foreignKeyIssues,
            amendmentIssues: amendmentIssues
        )
    }

    public func verifyEncryptedBackup(at url: URL, passphrase: String) throws -> OperationVerification {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Blackbox-Verify-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let decryptedURL = folder.appendingPathComponent("Verified.sqlite")
        try EncryptedBackupService.decryptBackup(encryptedBackup: url, destinationDatabase: decryptedURL, passphrase: passphrase)
        return try verifyBackup(at: decryptedURL)
    }

    @discardableResult
    public func rehearseRestore(from encryptedBackupURL: URL, passphrase: String) throws -> OperationVerification {
        let plan = try prepareRestore(from: encryptedBackupURL, passphrase: passphrase)
        let artifactRoot = try validatedRestoreArtifactRoot(for: plan)
        defer { try? FileManager.default.removeItem(at: artifactRoot) }
        return try verifyBackup(at: plan.inspectedDatabaseURL)
    }

    public func prepareSuggestionBatch(for flight: FlightEntry, selectedSuggestionIDs: Set<String> = []) -> SuggestionBatch {
        FlightSuggestionEngine.prepareBatch(for: flight, selectedSuggestionIDs: selectedSuggestionIDs)
    }

    public func applySuggestionBatch(_ batch: SuggestionBatch, to flight: FlightEntry) -> FlightEntry {
        FlightSuggestionEngine.applying(batch, to: flight)
    }

    public func prepareRestore(from encryptedBackupURL: URL, passphrase: String) throws -> RestorePlan {
        let artifactToken = UUID()
        let folder = Self.restoreArtifactRoot(for: artifactToken)
        try FileManager.default.createDirectory(
            at: folder,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let inspectedURL = folder.appendingPathComponent("Inspected.sqlite")
        do {
            try EncryptedBackupService.decryptBackup(encryptedBackup: encryptedBackupURL, destinationDatabase: inspectedURL, passphrase: passphrase)
            let originalVersion: Int = try {
                let decrypted = try SQLiteConnection(path: inspectedURL.path, readOnly: true)
                try rejectExecutableRestoreSchema(in: decrypted)
                return try schemaVersion(in: decrypted)
            }()
            guard originalVersion <= Self.currentSchemaVersion else {
                throw LogbookRepositoryError.invalidState("This backup uses a newer Blackbox schema and cannot be restored by this version.")
            }
            if originalVersion < Self.currentSchemaVersion {
                let inspectedPaths = LogbookPaths(
                    backupFolder: folder.appendingPathComponent("Migration Backups", isDirectory: true),
                    sourceLogTenDatabase: folder.appendingPathComponent("No LogTen Source.sqlite"),
                    workingDatabase: inspectedURL
                )
                try LogbookRepository(paths: inspectedPaths).bootstrapIfNeeded(allowUpgrade: true)
            }
            let inspected = try SQLiteConnection(path: inspectedURL.path, readOnly: true)
            try rejectExecutableRestoreSchema(in: inspected)
            try validateCanonicalRestoreSchema(in: inspected, workspace: folder)
            let integrity = try inspected.integrityCheck()
            guard integrity.lowercased() == "ok" else { throw LogbookRepositoryError.integrityCheckFailed(integrity) }
            let foreignKeyIssues = try foreignKeyIssueDescriptions(in: inspected)
            let amendmentIssues = try amendmentPreflightIssues(in: inspected)
            guard foreignKeyIssues.isEmpty, amendmentIssues.isEmpty else {
                let details = (foreignKeyIssues + amendmentIssues).joined(separator: " ")
                throw LogbookRepositoryError.integrityCheckFailed("The backup contains invalid record relationships. \(details)")
            }
            let columns = try inspected.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string }
            guard columns.contains("id"), columns.contains("total_minutes") else {
                throw LogbookRepositoryError.invalidState("The decrypted file is not a compatible Blackbox database.")
            }
            let restored = try summary(in: inspected)
            let restoredFlightDigest = try canonicalFlightDigest(in: inspected)
            let currentSnapshot: (summary: LogbookSummary, digest: String) = try {
                let current = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
                return (try summary(in: current), try canonicalFlightDigest(in: current))
            }()
            let version = try schemaVersion(in: inspected)
            var plan = RestorePlan(
                encryptedBackupURL: encryptedBackupURL,
                inspectedDatabaseURL: inspectedURL,
                currentFlightCount: currentSnapshot.summary.flightCount,
                restoredFlightCount: restored.flightCount,
                currentTotalMinutes: currentSnapshot.summary.totalMinutes,
                restoredTotalMinutes: restored.totalMinutes,
                schemaVersion: version,
                integrityMessage: integrity,
                inspectedDigest: try Self.fileDigest(planURL: inspectedURL),
                currentFlightDigest: currentSnapshot.digest,
                restoredFlightDigest: restoredFlightDigest
            )
            plan.artifactToken = artifactToken
            plan.sealedPlanDigest = try Self.restorePlanContentDigest(plan)
            return plan
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    @discardableResult
    public func applyRestore(_ plan: RestorePlan, injectingFailureAt failureStage: TransactionFailureStage? = nil) throws -> URL {
        let artifactRoot = try validatedRestoreArtifactRoot(for: plan)
        defer { try? FileManager.default.removeItem(at: artifactRoot) }
        guard plan.schemaVersion == Self.currentSchemaVersion else {
            throw LogbookRepositoryError.invalidState("Only a backup upgraded to the current Blackbox schema can be applied.")
        }
        guard !plan.sealedPlanDigest.isEmpty,
              try Self.restorePlanContentDigest(plan) == plan.sealedPlanDigest else {
            throw LogbookRepositoryError.stalePlan
        }
        guard FileManager.default.fileExists(atPath: plan.inspectedDatabaseURL.path) else { throw LogbookRepositoryError.stalePlan }
        let currentInspectedDigest = try Self.fileDigest(planURL: plan.inspectedDatabaseURL)
        guard !plan.inspectedDigest.isEmpty, currentInspectedDigest == plan.inspectedDigest else { throw LogbookRepositoryError.stalePlan }
        let inspectedSnapshot: (digest: String, integrity: String, summary: LogbookSummary, version: Int, foreignKeys: [String], amendments: [String]) = try {
            let inspected = try SQLiteConnection(path: plan.inspectedDatabaseURL.path, readOnly: true)
            try rejectExecutableRestoreSchema(in: inspected)
            try validateCanonicalRestoreSchema(in: inspected, workspace: artifactRoot)
            return (
                try canonicalFlightDigest(in: inspected),
                try inspected.integrityCheck(),
                try summary(in: inspected),
                try schemaVersion(in: inspected),
                try foreignKeyIssueDescriptions(in: inspected),
                try amendmentPreflightIssues(in: inspected)
            )
        }()
        guard inspectedSnapshot.integrity.lowercased() == "ok",
              inspectedSnapshot.foreignKeys.isEmpty,
              inspectedSnapshot.amendments.isEmpty,
              inspectedSnapshot.version == plan.schemaVersion,
              inspectedSnapshot.summary.flightCount == plan.restoredFlightCount,
              inspectedSnapshot.summary.totalMinutes == plan.restoredTotalMinutes,
              !plan.restoredFlightDigest.isEmpty,
              inspectedSnapshot.digest == plan.restoredFlightDigest else {
            throw LogbookRepositoryError.stalePlan
        }
        let currentSnapshot: (digest: String, summary: LogbookSummary) = try {
            let current = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            return (try canonicalFlightDigest(in: current), try summary(in: current))
        }()
        guard !plan.currentFlightDigest.isEmpty, currentSnapshot.digest == plan.currentFlightDigest else {
            throw LogbookRepositoryError.stalePlan
        }
        try FileManager.default.createDirectory(at: paths.backupFolder, withIntermediateDirectories: true)
        let restorePoint = paths.backupFolder.appendingPathComponent("Blackbox-pre-restore-\(Self.backupTimestamp()).sqlite")
        let workFolder = paths.workingDatabase.deletingLastPathComponent()
            .appendingPathComponent(".Blackbox-restore-\(UUID().uuidString)", isDirectory: true)
        let stagedURL = workFolder.appendingPathComponent("Staged.sqlite")
        let activationURL = workFolder.appendingPathComponent("Activation.sqlite")
        var batch = OperationBatch(
            kind: "restore",
            source: plan.encryptedBackupURL.path,
            status: "applying",
            summary: "Verified restore",
            backupPath: restorePoint.path,
            affectedCount: plan.restoredFlightCount,
            beforeTotalMinutes: currentSnapshot.summary.totalMinutes,
            afterTotalMinutes: plan.restoredTotalMinutes,
            artifactURLs: [restorePoint]
        )
        var activated = false
        var failureBoundary: TransactionFailureStage = .backupCreation
        defer { try? FileManager.default.removeItem(at: workFolder) }
        do {
            if failureStage == .backupCreation {
                throw LogbookRepositoryError.integrityCheckFailed("Injected restore backup failure.")
            }
            try makeVerifiedSnapshot(from: paths.workingDatabase, to: restorePoint)
            failureBoundary = .staging
            if failureStage == .staging {
                throw LogbookRepositoryError.integrityCheckFailed("Injected restore staging failure.")
            }
            try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
            try makeVerifiedSnapshot(from: plan.inspectedDatabaseURL, to: stagedURL)
            failureBoundary = .transaction
            if failureStage == .transaction {
                throw LogbookRepositoryError.integrityCheckFailed("Injected restore transaction failure.")
            }

            let stagedPaths = LogbookPaths(
                backupFolder: workFolder.appendingPathComponent("Migration Backups", isDirectory: true),
                sourceLogTenDatabase: workFolder.appendingPathComponent("No LogTen Source.sqlite"),
                workingDatabase: stagedURL
            )
            let stagedRepository = LogbookRepository(paths: stagedPaths)
            try stagedRepository.bootstrapIfNeeded(allowUpgrade: true)
            let staged = try SQLiteConnection(path: stagedURL.path)
            failureBoundary = .postTransactionVerification
            if failureStage == .postTransactionVerification {
                throw LogbookRepositoryError.integrityCheckFailed("Injected restored-database verification failure.")
            }
            var verification = try operationVerification(
                in: staged,
                batchID: batch.id,
                expectedFlightCount: plan.restoredFlightCount,
                expectedTotalMinutes: plan.restoredTotalMinutes,
                expectedRevisionCount: 0,
                expectedFlightDigest: plan.restoredFlightDigest
            )
            guard verification.passed else {
                throw LogbookRepositoryError.integrityCheckFailed("The staged restore did not match the previewed row count and totals after migration.")
            }
            batch.status = "completed"
            batch.completedAt = Date()
            batch.verification = verification
            batch.recoveryOutcome = "Verified recovery point retained"
            try staged.transaction { try write(batch: batch, in: staged) }

            try makeVerifiedSnapshot(from: stagedURL, to: activationURL)
            let activation = try SQLiteConnection(path: activationURL.path, readOnly: true)
            verification = try operationVerification(
                in: activation,
                batchID: batch.id,
                expectedFlightCount: plan.restoredFlightCount,
                expectedTotalMinutes: plan.restoredTotalMinutes,
                expectedRevisionCount: 0,
                expectedFlightDigest: plan.restoredFlightDigest
            )
            guard verification.passed else {
                throw LogbookRepositoryError.integrityCheckFailed("The self-contained restore candidate failed independent verification.")
            }
            failureBoundary = .beforeAtomicSwap
            if failureStage == .atomicSwap || failureStage == .beforeAtomicSwap {
                throw LogbookRepositoryError.integrityCheckFailed("Injected restore atomic-swap failure.")
            }
            activated = true
            try activateDatabase(at: activationURL)
            failureBoundary = .afterAtomicSwap
            if failureStage == .afterAtomicSwap {
                throw LogbookRepositoryError.integrityCheckFailed("Injected restore post-swap failure.")
            }
            let active = try SQLiteConnection(path: paths.workingDatabase.path, readOnly: true)
            verification = try operationVerification(
                in: active,
                batchID: batch.id,
                expectedFlightCount: plan.restoredFlightCount,
                expectedTotalMinutes: plan.restoredTotalMinutes,
                expectedRevisionCount: 0,
                expectedFlightDigest: plan.restoredFlightDigest
            )
            guard verification.passed else {
                throw LogbookRepositoryError.integrityCheckFailed("The activated restore database failed verification.")
            }
            batch.verification = verification
            try recordOperation(batch)
        } catch let operationError {
            var recovery = "Original database remained active"
            var recoveryError: Error?
            if activated {
                do {
                    try restoreDatabase(from: restorePoint)
                    recovery = "Verified recovery point restored"
                } catch {
                    recoveryError = error
                    recovery = "Recovery failed: \(error.localizedDescription)"
                }
            }
            retainFailedOperation(
                from: batch,
                stage: failureStage ?? failureBoundary,
                recovery: recovery,
                persistToDatabase: recoveryError == nil
            )
            if let recoveryError {
                throw LogbookRepositoryError.recoveryFailed(
                    operation: "Restore",
                    operationMessage: operationError.localizedDescription,
                    recoveryMessage: recoveryError.localizedDescription
                )
            }
            throw LogbookRepositoryError.operationFailedWithVerifiedRecovery(
                operation: "Restore",
                operationMessage: operationError.localizedDescription,
                recoveryOutcome: recovery
            )
        }
        return restorePoint
    }

    private func summary(in db: SQLiteConnection) throws -> LogbookSummary {
        let columns = try db.rows("PRAGMA table_info(flights)").compactMap { $0["name"]?.string }
        let filter = columns.contains("record_state") ? " WHERE record_state IN ('draft', 'finalised')" : ""
        let row = try db.rows("SELECT COUNT(*) AS flight_count, COALESCE(SUM(MAX(total_minutes - fstd_minutes, 0)), 0) AS total_minutes FROM flights\(filter)").first ?? [:]
        return LogbookSummary(flightCount: row["flight_count"]?.int ?? 0, totalMinutes: row["total_minutes"]?.int ?? 0)
    }

    private static func changedImportFields(current: FlightEntry, proposed: FlightEntry) -> [String] {
        var fields: [String] = []
        func compare<T: Equatable>(_ label: String, _ lhs: T, _ rhs: T) { if lhs != rhs { fields.append(label) } }
        compare("Date", current.date, proposed.date); compare("Departure", current.departure, proposed.departure); compare("Arrival", current.arrival, proposed.arrival)
        compare("Route", current.route, proposed.route); compare("Aircraft", current.aircraftID, proposed.aircraftID); compare("Type", current.aircraftType, proposed.aircraftType)
        compare("Flight number", current.flightNumber, proposed.flightNumber); compare("Operation", current.operation, proposed.operation); compare("Entry type", current.entryKind, proposed.entryKind); compare("Function", current.pilotFunction, proposed.pilotFunction)
        compare("Total", current.totalMinutes, proposed.totalMinutes); compare("PIC", current.picMinutes, proposed.picMinutes); compare("PIC day", current.picDayMinutes, proposed.picDayMinutes); compare("PIC night", current.picNightMinutes, proposed.picNightMinutes)
        compare("PICUS", current.picusMinutes, proposed.picusMinutes); compare("PICUS day", current.picusDayMinutes, proposed.picusDayMinutes); compare("PICUS night", current.picusNightMinutes, proposed.picusNightMinutes)
        compare("Co-pilot", current.copilotMinutes, proposed.copilotMinutes); compare("Co-pilot day", current.copilotDayMinutes, proposed.copilotDayMinutes); compare("Co-pilot night", current.copilotNightMinutes, proposed.copilotNightMinutes); compare("Dual", current.dualMinutes, proposed.dualMinutes); compare("Instructor", current.instructorMinutes, proposed.instructorMinutes)
        compare("Night", current.nightMinutes, proposed.nightMinutes); compare("Instrument", current.instrumentMinutes, proposed.instrumentMinutes); compare("Cross-country", current.crossCountryMinutes, proposed.crossCountryMinutes)
        compare("FSTD", current.fstdMinutes, proposed.fstdMinutes); compare("Pilot flying", current.pilotFlying, proposed.pilotFlying)
        compare("Day takeoffs", current.dayTakeoffs, proposed.dayTakeoffs); compare("Night takeoffs", current.nightTakeoffs, proposed.nightTakeoffs); compare("Takeoffs", current.totalTakeoffs, proposed.totalTakeoffs)
        compare("Day landings", current.dayLandings, proposed.dayLandings); compare("Night landings", current.nightLandings, proposed.nightLandings); compare("Landings", current.totalLandings, proposed.totalLandings)
        compare("Passengers", current.passengerCount, proposed.passengerCount); compare("Distance", current.distanceNM, proposed.distanceNM)
        compare("Crew", current.crewNames, proposed.crewNames); compare("Crew roles", current.crewRoles, proposed.crewRoles)
        compare("Departure latitude", current.departureLatitude, proposed.departureLatitude); compare("Departure longitude", current.departureLongitude, proposed.departureLongitude)
        compare("Arrival latitude", current.arrivalLatitude, proposed.arrivalLatitude); compare("Arrival longitude", current.arrivalLongitude, proposed.arrivalLongitude)
        compare("Remarks", current.remarks, proposed.remarks); compare("Signature name", current.signatureName, proposed.signatureName); compare("Signature reference", current.signatureReference, proposed.signatureReference)
        return fields
    }

    private static let importableFields = [
        "Date", "Departure", "Arrival", "Route", "Aircraft", "Type", "Flight number", "Operation", "Entry type", "Function",
        "Total", "PIC", "PIC day", "PIC night", "PICUS", "PICUS day", "PICUS night", "Co-pilot", "Co-pilot day", "Co-pilot night",
        "Dual", "Instructor", "Night", "Instrument", "Cross-country", "FSTD", "Pilot flying",
        "Day takeoffs", "Night takeoffs", "Takeoffs", "Day landings", "Night landings", "Landings", "Passengers", "Distance",
        "Crew", "Crew roles", "Departure latitude", "Departure longitude", "Arrival latitude", "Arrival longitude",
        "Remarks", "Signature name", "Signature reference"
    ]

    private static func applyingAdditionSelections(to proposed: FlightEntry, selections: [ImportFieldSelection]) throws -> FlightEntry {
        guard let sourcePK = proposed.sourcePK else { return proposed }
        let excluded = Set(selections.filter { $0.sourcePK == sourcePK && $0.decision == .exclude }.map(\.field))
        guard !excluded.isEmpty else { return proposed }
        guard !excluded.contains("Date") else {
            throw LogbookRepositoryError.invalidState("A new imported draft requires its source date. Exclude the entire record instead of replacing the date with an invented value.")
        }
        let empty = FlightEntry(date: proposed.date, operation: "", entryKind: "", recordState: .draft)
        let includedSelections = importableFields.filter { !excluded.contains($0) }.map {
            ImportFieldSelection(sourcePK: sourcePK, field: $0, blackboxValue: "", sourceValue: "", decision: .include)
        }
        var base = empty
        base.sourcePK = proposed.sourcePK
        let change = ImportChange(sourcePK: sourcePK, existing: base, proposed: proposed, changedFields: importableFields)
        return applyingFieldSelections(for: change, selections: includedSelections)
    }

    private static func additionHasIncludedField(_ flight: FlightEntry, selections: [ImportFieldSelection]) -> Bool {
        guard let sourcePK = flight.sourcePK else { return false }
        let relevant = selections.filter { $0.sourcePK == sourcePK }
        return relevant.isEmpty || relevant.contains { $0.decision == .include }
    }

    private static func applyingFieldSelections(for change: ImportChange, selections: [ImportFieldSelection]) -> FlightEntry {
        let included = Set(selections.filter { $0.sourcePK == change.sourcePK && $0.decision == .include }.map(\.field))
        var result = change.existing
        let proposed = change.proposed
        if included.contains("Date") { result.date = proposed.date }
        if included.contains("Departure") { result.departure = proposed.departure }
        if included.contains("Arrival") { result.arrival = proposed.arrival }
        if included.contains("Route") { result.route = proposed.route }
        if included.contains("Aircraft") { result.aircraftID = proposed.aircraftID }
        if included.contains("Type") { result.aircraftType = proposed.aircraftType }
        if included.contains("Flight number") { result.flightNumber = proposed.flightNumber }
        if included.contains("Operation") { result.operation = proposed.operation }
        if included.contains("Entry type") { result.entryKind = proposed.entryKind }
        if included.contains("Function") { result.pilotFunction = proposed.pilotFunction }
        if included.contains("Total") { result.totalMinutes = proposed.totalMinutes }
        if included.contains("PIC") { result.picMinutes = proposed.picMinutes }
        if included.contains("PIC day") { result.picDayMinutes = proposed.picDayMinutes }
        if included.contains("PIC night") { result.picNightMinutes = proposed.picNightMinutes }
        if included.contains("PICUS") { result.picusMinutes = proposed.picusMinutes }
        if included.contains("PICUS day") { result.picusDayMinutes = proposed.picusDayMinutes }
        if included.contains("PICUS night") { result.picusNightMinutes = proposed.picusNightMinutes }
        if included.contains("Co-pilot") { result.copilotMinutes = proposed.copilotMinutes }
        if included.contains("Co-pilot day") { result.copilotDayMinutes = proposed.copilotDayMinutes }
        if included.contains("Co-pilot night") { result.copilotNightMinutes = proposed.copilotNightMinutes }
        if included.contains("Dual") { result.dualMinutes = proposed.dualMinutes }
        if included.contains("Instructor") { result.instructorMinutes = proposed.instructorMinutes }
        if included.contains("Night") { result.nightMinutes = proposed.nightMinutes }
        if included.contains("Instrument") { result.instrumentMinutes = proposed.instrumentMinutes }
        if included.contains("Cross-country") { result.crossCountryMinutes = proposed.crossCountryMinutes }
        if included.contains("FSTD") { result.fstdMinutes = proposed.fstdMinutes }
        if included.contains("Pilot flying") { result.pilotFlying = proposed.pilotFlying }
        if included.contains("Day takeoffs") { result.dayTakeoffs = proposed.dayTakeoffs }
        if included.contains("Night takeoffs") { result.nightTakeoffs = proposed.nightTakeoffs }
        if included.contains("Takeoffs") { result.totalTakeoffs = proposed.totalTakeoffs }
        if included.contains("Day landings") { result.dayLandings = proposed.dayLandings }
        if included.contains("Night landings") { result.nightLandings = proposed.nightLandings }
        if included.contains("Landings") { result.totalLandings = proposed.totalLandings }
        if included.contains("Passengers") { result.passengerCount = proposed.passengerCount }
        if included.contains("Distance") { result.distanceNM = proposed.distanceNM }
        if included.contains("Crew") { result.crewNames = proposed.crewNames }
        if included.contains("Crew roles") { result.crewRoles = proposed.crewRoles }
        if included.contains("Departure latitude") { result.departureLatitude = proposed.departureLatitude }
        if included.contains("Departure longitude") { result.departureLongitude = proposed.departureLongitude }
        if included.contains("Arrival latitude") { result.arrivalLatitude = proposed.arrivalLatitude }
        if included.contains("Arrival longitude") { result.arrivalLongitude = proposed.arrivalLongitude }
        if included.contains("Remarks") { result.remarks = proposed.remarks }
        if included.contains("Signature name") { result.signatureName = proposed.signatureName }
        if included.contains("Signature reference") { result.signatureReference = proposed.signatureReference }
        return result
    }

    private static func importDisplayValue(field: String, flight: FlightEntry) -> String {
        switch field {
        case "Date": return LogbookFormatters.isoFormatter.string(from: flight.date)
        case "Departure": return flight.departure
        case "Arrival": return flight.arrival
        case "Route": return flight.route
        case "Aircraft": return flight.aircraftID
        case "Type": return flight.aircraftType
        case "Flight number": return flight.flightNumber
        case "Operation": return flight.operation
        case "Entry type": return flight.entryKind
        case "Function": return flight.pilotFunction
        case "Total": return "\(flight.totalMinutes)"
        case "PIC": return "\(flight.picMinutes)"
        case "PIC day": return "\(flight.picDayMinutes)"
        case "PIC night": return "\(flight.picNightMinutes)"
        case "PICUS": return "\(flight.picusMinutes)"
        case "PICUS day": return "\(flight.picusDayMinutes)"
        case "PICUS night": return "\(flight.picusNightMinutes)"
        case "Co-pilot": return "\(flight.copilotMinutes)"
        case "Co-pilot day": return "\(flight.copilotDayMinutes)"
        case "Co-pilot night": return "\(flight.copilotNightMinutes)"
        case "Dual": return "\(flight.dualMinutes)"
        case "Instructor": return "\(flight.instructorMinutes)"
        case "Night": return "\(flight.nightMinutes)"
        case "Instrument": return "\(flight.instrumentMinutes)"
        case "Cross-country": return "\(flight.crossCountryMinutes)"
        case "FSTD": return "\(flight.fstdMinutes)"
        case "Pilot flying": return flight.pilotFlying ? "Yes" : "No"
        case "Day takeoffs": return "\(flight.dayTakeoffs)"
        case "Night takeoffs": return "\(flight.nightTakeoffs)"
        case "Takeoffs": return "\(flight.totalTakeoffs)"
        case "Day landings": return "\(flight.dayLandings)"
        case "Night landings": return "\(flight.nightLandings)"
        case "Landings": return "\(flight.totalLandings)"
        case "Passengers": return "\(flight.passengerCount)"
        case "Distance": return String(format: "%.6f", flight.distanceNM)
        case "Crew": return flight.crewNames
        case "Crew roles": return flight.crewRoles
        case "Departure latitude": return flight.departureLatitude.map { String(format: "%.8f", $0) } ?? ""
        case "Departure longitude": return flight.departureLongitude.map { String(format: "%.8f", $0) } ?? ""
        case "Arrival latitude": return flight.arrivalLatitude.map { String(format: "%.8f", $0) } ?? ""
        case "Arrival longitude": return flight.arrivalLongitude.map { String(format: "%.8f", $0) } ?? ""
        case "Remarks": return flight.remarks
        case "Signature name": return flight.signatureName
        case "Signature reference": return flight.signatureReference
        default: return ""
        }
    }

    private static func optionalText(_ value: SQLiteValue?) -> String? {
        guard let value, case .text(let text) = value else { return nil }
        return text
    }

    private static func nowText() -> String {
        LogbookFormatters.isoFormatter.string(from: Date())
    }

    private static func fileDigest(planURL: URL) throws -> String {
        let data = try Data(contentsOf: planURL, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
        WHERE record_state IN ('draft', 'finalised')
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
        WHERE record_state IN ('draft', 'finalised')
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
        WHERE record_state IN ('draft', 'finalised')
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
        let rows = try db.rows("SELECT crew_names, MAX(total_minutes - fstd_minutes, 0) AS total_minutes FROM flights WHERE crew_names != '' AND record_state IN ('draft', 'finalised')")
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
        WITH flight_places AS (
            SELECT departure AS identifier FROM flights WHERE departure != '' AND record_state IN ('draft', 'finalised')
            UNION
            SELECT arrival AS identifier FROM flights WHERE arrival != '' AND record_state IN ('draft', 'finalised')
        )
        SELECT fp.identifier, COALESCE(p.name, '') AS name,
               COALESCE(d.departures, 0) AS departures,
               COALESCE(a.arrivals, 0) AS arrivals
        FROM flight_places fp
        LEFT JOIN places p ON p.identifier = fp.identifier
        LEFT JOIN (SELECT departure AS identifier, COUNT(*) AS departures FROM flights WHERE departure != '' AND record_state IN ('draft', 'finalised') GROUP BY departure) d ON d.identifier = fp.identifier
        LEFT JOIN (SELECT arrival AS identifier, COUNT(*) AS arrivals FROM flights WHERE arrival != '' AND record_state IN ('draft', 'finalised') GROUP BY arrival) a ON a.identifier = fp.identifier
        ORDER BY (COALESCE(d.departures, 0) + COALESCE(a.arrivals, 0)) DESC, fp.identifier
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
        SELECT id, date, aircraft_id, aircraft_type, entry_kind, departure, arrival, departure_lat, departure_lon, arrival_lat, arrival_lon, distance_nm
        FROM flights
        WHERE departure_lat IS NOT NULL AND departure_lon IS NOT NULL AND arrival_lat IS NOT NULL AND arrival_lon IS NOT NULL
          AND record_state IN ('draft', 'finalised')
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
                date: Self.date(from: row["date"]?.string ?? "") ?? Date.distantPast,
                aircraftID: row["aircraft_id"]?.string ?? "",
                aircraftType: row["aircraft_type"]?.string ?? "",
                entryKind: row["entry_kind"]?.string ?? "Flight",
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
            aircraftIDs: try values("SELECT DISTINCT aircraft_id AS value FROM flights WHERE aircraft_id != '' AND record_state IN ('draft', 'finalised') ORDER BY aircraft_id LIMIT 300"),
            aircraftTypes: try values("SELECT DISTINCT aircraft_type AS value FROM flights WHERE aircraft_type != '' AND record_state IN ('draft', 'finalised') ORDER BY aircraft_type LIMIT 300"),
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
        let db = try currentDatabaseForIntentWrite()
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
        let allFlights = try flights(query: FlightQuery(recordStates: [.finalised]))
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
        guard !logTenFlights.isEmpty else {
            throw LogbookRepositoryError.emptyComparisonSource("The selected LogTen source opened successfully but contains no flights, so it cannot be reported as a match.")
        }
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
            issues.append(contentsOf: Self.comparisonIssues(sourcePK: sourcePK, logTen: logTen, blackbox: blackbox))
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

    public func logTenComparisonState() -> LogTenComparisonState {
        let sourceURL = comparisonSourceDatabase()
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .unavailable("No LogTen comparison source is available at \(sourceURL.path).")
        }
        do {
            return .loaded(try logTenComparisonSnapshot())
        } catch LogbookRepositoryError.emptyComparisonSource(let message) {
            return .empty(message)
        } catch {
            return .failed("The LogTen comparison source could not be opened and compared: \(error.localizedDescription)")
        }
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
        if allowsLiveLogTenDiscovery {
            let liveURL = URL(fileURLWithPath: Self.liveLogTenDatabasePath)
            if FileManager.default.fileExists(atPath: liveURL.path) {
                return liveURL
            }
        }
        return paths.sourceLogTenDatabase
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
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return "\(formatter.string(from: Date()))-\(UUID().uuidString)"
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

    /// Uses the same canonical persisted-field manifest as import planning. A
    /// comparison match therefore cannot ignore a source-backed field that an
    /// import would otherwise propose changing.
    static func comparisonIssues(
        sourcePK: Int64,
        logTen: FlightEntry,
        blackbox: FlightEntry
    ) -> [LogTenComparisonIssue] {
        let route = logTen.routeDisplay.isEmpty ? blackbox.routeDisplay : logTen.routeDisplay
        return changedImportFields(current: blackbox, proposed: logTen).map { field in
            LogTenComparisonIssue(
                sourcePK: sourcePK,
                date: logTen.date,
                route: route,
                field: field,
                logTenValue: importDisplayValue(field: field, flight: logTen),
                blackboxValue: importDisplayValue(field: field, flight: blackbox)
            )
        }
    }

    private func flightCount(in db: SQLiteConnection) throws -> Int {
        try db.rows("SELECT COUNT(*) AS count FROM flights").first?["count"]?.int ?? 0
    }

    private func setting(_ key: String, in db: SQLiteConnection) throws -> String {
        try db.rows("SELECT value FROM settings WHERE key = ?", values: [.text(key)]).first?["value"]?.string ?? ""
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
                       0 AS pic_day_minutes,
                       COALESCE(f.ZFLIGHT_PICNIGHT, 0) AS pic_night_minutes,
                       COALESCE(f.ZFLIGHT_P1US, 0) AS picus_minutes,
                       COALESCE(f.ZFLIGHT_CUSTOMTIME4, 0) AS picus_day_minutes,
                       COALESCE(f.ZFLIGHT_P1USNIGHT, 0) AS picus_night_minutes,
                       COALESCE(f.ZFLIGHT_CUSTOMTIME3, 0) AS copilot_minutes,
                       0 AS copilot_day_minutes,
                       0 AS copilot_night_minutes,
               COALESCE(f.ZFLIGHT_DUALRECEIVED, 0) AS dual_minutes,
               COALESCE(f.ZFLIGHT_DUALGIVEN, 0) AS instructor_minutes,
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

    private static func flightFromLogTen(row: [String: SQLiteValue]) -> FlightEntry {
        let departure = row["departure"]?.string ?? ""
        let arrival = row["arrival"]?.string ?? ""
        let flightDate = Date(timeIntervalSinceReferenceDate: row["flight_date"]?.double ?? 0)

        return FlightEntry(
            sourcePK: row["source_pk"]?.int64,
            date: flightDate,
            departure: departure,
            arrival: arrival,
            route: row["route"]?.string ?? "",
            aircraftID: row["aircraft_id"]?.string ?? "",
            aircraftType: row["aircraft_type"]?.string ?? "",
            flightNumber: row["flight_number"]?.string ?? "",
            operation: (row["multipilot"]?.int ?? 0) > 0 ? "MP" : "SP",
            entryKind: "",
            pilotFunction: "",
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
            pilotFlying: (row["pilot_flying"]?.int ?? 0) > 0,
            dayTakeoffs: row["day_takeoffs"]?.int ?? 0,
            nightTakeoffs: row["night_takeoffs"]?.int ?? 0,
            totalTakeoffs: row["total_takeoffs"]?.int ?? 0,
            dayLandings: row["day_landings"]?.int ?? 0,
            nightLandings: row["night_landings"]?.int ?? 0,
            totalLandings: row["total_landings"]?.int ?? 0,
            passengerCount: row["passenger_count"]?.int ?? 0,
            distanceNM: row["distance_nm"]?.double ?? 0,
            crewNames: row["crew_names"]?.string ?? "",
            crewRoles: "",
            departureLatitude: row["departure_lat"]?.double,
            departureLongitude: row["departure_lon"]?.double,
            arrivalLatitude: row["arrival_lat"]?.double,
            arrivalLongitude: row["arrival_lon"]?.double,
            remarks: row["remarks"]?.string ?? ""
        )
    }

    private static func flight(from row: [String: SQLiteValue]) -> FlightEntry {
        FlightEntry(
            id: row["id"]?.int64,
            sourcePK: row["source_pk"]?.int64,
            // Historical minimal schemas may acquire a blank date column during
            // additive migration. Never turn that missing fact into the current
            // clock time: repeated reads must produce the same manifest digest,
            // while the persisted blank remains untouched until explicitly edited.
            date: date(from: row["date"]?.string ?? "") ?? Date(timeIntervalSince1970: 0),
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
            locked: (row["locked"]?.int ?? 0) != 0,
            recordState: FlightRecordState(rawValue: row["record_state"]?.string ?? "") ?? ((row["locked"]?.int ?? 0) != 0 ? .finalised : .draft),
            amendsFlightID: row["amends_flight_id"]?.int64,
            supersededByFlightID: row["superseded_by_flight_id"]?.int64
        )
    }

    private static func date(from text: String) -> Date? {
        LogbookFormatters.isoFormatter.date(from: text)
    }
}
