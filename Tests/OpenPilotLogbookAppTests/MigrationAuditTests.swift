import AppKit
import Foundation
import Testing
@testable import OpenPilotLogbook
import OpenPilotLogbookCore

@Suite("Reviewed schema upgrade audit")
@MainActor
struct MigrationAuditTests {
    @Test("Migration history records verified legacy and current totals")
    func migrationRecordsTrustworthyTotals() throws {
        let fixture = try makeLegacyStore()
        defer { fixture.cleanUp() }

        #expect(fixture.store.upgradePreflight?.flightCount == 2)
        // The initial legacy refresh intentionally stops at the review gate,
        // so the ordinary published summary has not been loaded yet.
        #expect(fixture.store.summary.totalMinutes == 0)

        fixture.store.performUpgrade()

        #expect(try fixture.store.repository.schemaVersion() == LogbookRepository.currentSchemaVersion)
        #expect(fixture.store.upgradePreflight == nil)
        #expect(fixture.store.summary.flightCount == 2)
        #expect(fixture.store.summary.totalMinutes == 245)
        let migration = try #require(
            fixture.store.repository.operationBatches().first {
                $0.kind == "migration" && $0.status == "completed"
            }
        )
        #expect(migration.affectedCount == 2)
        #expect(migration.beforeTotalMinutes == 245)
        #expect(migration.afterTotalMinutes == 245)
        #expect(fixture.store.statusMessage.hasPrefix("Upgrade complete."))
        try expectLegacyFactsUnchanged(in: fixture.paths.workingDatabase)
    }

    @Test("Audit append failure does not relabel a completed migration")
    func auditAppendFailureIsReportedSeparately() throws {
        let fixture = try makeLegacyStore { _ in
            throw SyntheticMigrationAuditError.appendRejected
        }
        defer { fixture.cleanUp() }

        fixture.store.performUpgrade()

        #expect(try fixture.store.repository.schemaVersion() == LogbookRepository.currentSchemaVersion)
        #expect(fixture.store.upgradePreflight == nil)
        #expect(fixture.store.summary.flightCount == 2)
        #expect(fixture.store.summary.totalMinutes == 245)
        #expect(fixture.store.statusMessage.hasPrefix("Upgrade complete."))
        #expect(fixture.store.statusMessage.contains("Migration history was not recorded"))
        #expect(!fixture.store.statusMessage.contains("Upgrade failed"))
        #expect(
            try fixture.store.repository.operationBatches().allSatisfy {
                !($0.kind == "migration" && $0.status == "failed")
            }
        )
        try expectLegacyFactsUnchanged(in: fixture.paths.workingDatabase)
    }

    private func makeLegacyStore(
        migrationAuditRecorder: ((OperationBatch) throws -> Void)? = nil
    ) throws -> MigrationStoreFixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("Blackbox-MigrationAuditTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let paths = LogbookPaths(
            backupFolder: root.appendingPathComponent("Backups", isDirectory: true),
            sourceLogTenDatabase: root.appendingPathComponent("Missing-LogTen.sqlite"),
            workingDatabase: root.appendingPathComponent("Blackbox.sqlite")
        )
        do {
            let database = try SQLiteConnection(path: paths.workingDatabase.path)
            try database.execute("""
            CREATE TABLE flights(
                id INTEGER PRIMARY KEY,
                date TEXT NOT NULL,
                total_minutes INTEGER NOT NULL,
                fstd_minutes INTEGER NOT NULL,
                locked INTEGER NOT NULL,
                remarks TEXT NOT NULL,
                modified_at TEXT NOT NULL
            )
            """)
            try database.execute(
                "INSERT INTO flights(id, date, total_minutes, fstd_minutes, locked, remarks, modified_at) VALUES(1, ?, 125, 0, 1, 'Legacy line one', ?)",
                values: [.text("2026-06-28T09:00:00Z"), .text("2026-06-28T11:05:00Z")]
            )
            try database.execute(
                "INSERT INTO flights(id, date, total_minutes, fstd_minutes, locked, remarks, modified_at) VALUES(2, ?, 180, 60, 0, 'Legacy line two', ?)",
                values: [.text("2026-06-29T12:00:00Z"), .text("2026-06-29T15:00:00Z")]
            )
            try database.execute("PRAGMA user_version = 0")
            try database.checkpointWAL()
        }
        let suiteName = "Blackbox.MigrationAuditTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw MigrationAuditFixtureError.couldNotCreateDefaults
        }
        let store = LogbookStore(
            paths: paths,
            folderAccessStore: FolderAccessStore(
                defaults: defaults,
                keyPrefix: "Synthetic.migrationAudit.folderBookmark",
                mode: .standard
            ),
            undoManager: UndoManager(),
            migrationAuditRecorder: migrationAuditRecorder
        )
        return MigrationStoreFixture(
            store: store,
            paths: paths,
            root: root,
            defaults: defaults,
            suiteName: suiteName
        )
    }

    private func expectLegacyFactsUnchanged(in databaseURL: URL) throws {
        let database = try SQLiteConnection(path: databaseURL.path, readOnly: true)
        let rows = try database.rows("""
        SELECT id, date, total_minutes, fstd_minutes, locked, remarks, modified_at
        FROM flights
        ORDER BY id
        """)
        #expect(rows.count == 2)
        #expect(rows[0]["id"]?.int == 1)
        #expect(rows[0]["date"]?.string == "2026-06-28T09:00:00Z")
        #expect(rows[0]["total_minutes"]?.int == 125)
        #expect(rows[0]["fstd_minutes"]?.int == 0)
        #expect(rows[0]["locked"]?.int == 1)
        #expect(rows[0]["remarks"]?.string == "Legacy line one")
        #expect(rows[0]["modified_at"]?.string == "2026-06-28T11:05:00Z")
        #expect(rows[1]["id"]?.int == 2)
        #expect(rows[1]["date"]?.string == "2026-06-29T12:00:00Z")
        #expect(rows[1]["total_minutes"]?.int == 180)
        #expect(rows[1]["fstd_minutes"]?.int == 60)
        #expect(rows[1]["locked"]?.int == 0)
        #expect(rows[1]["remarks"]?.string == "Legacy line two")
        #expect(rows[1]["modified_at"]?.string == "2026-06-29T15:00:00Z")
    }
}

@MainActor
private struct MigrationStoreFixture {
    let store: LogbookStore
    let paths: LogbookPaths
    let root: URL
    let defaults: UserDefaults
    let suiteName: String

    func cleanUp() {
        store.sessionUndoManager.removeAllActions()
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: root)
    }
}

private enum SyntheticMigrationAuditError: LocalizedError {
    case appendRejected

    var errorDescription: String? {
        "Synthetic migration history append rejected"
    }
}

private enum MigrationAuditFixtureError: Error {
    case couldNotCreateDefaults
}
