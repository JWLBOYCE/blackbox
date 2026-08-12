import Foundation
import SQLite3

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)
    case backup(String)

    public var description: String {
        switch self {
        case .open(let message), .prepare(let message), .step(let message), .bind(let message), .backup(let message):
            return message
        }
    }
}

public enum SQLiteValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)

    public var int: Int {
        if case .integer(let value) = self { return Int(value) }
        if case .real(let value) = self { return Int(value) }
        return 0
    }

    public var int64: Int64? {
        if case .integer(let value) = self { return value }
        if case .real(let value) = self { return Int64(value) }
        return nil
    }

    public var double: Double? {
        if case .real(let value) = self { return value }
        if case .integer(let value) = self { return Double(value) }
        return nil
    }

    public var string: String {
        if case .text(let value) = self { return value }
        if case .integer(let value) = self { return String(value) }
        if case .real(let value) = self { return String(value) }
        return ""
    }
}

public final class SQLiteConnection {
    private var db: OpaquePointer?

    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        if sqlite3_open_v2(path, &db, flags, nil) != SQLITE_OK {
            throw SQLiteError.open("\(SQLiteConnection.lastMessage(db)) [\(path)]")
        }
        if !readOnly {
            do {
                try execute("PRAGMA foreign_keys = ON")
                try execute("PRAGMA journal_mode = WAL")
            } catch {
                throw SQLiteError.open("Could not configure SQLite database [\(path)]: \(error)")
            }
        }
    }

    deinit {
        sqlite3_close(db)
    }

    public func execute(_ sql: String, values: [SQLiteValue] = []) throws {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(Self.lastMessage(db))
        }
        try bind(values, to: statement)
        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE || result == SQLITE_ROW else {
            throw SQLiteError.step(Self.lastMessage(db))
        }
    }

    public func rows(_ sql: String, values: [SQLiteValue] = []) throws -> [[String: SQLiteValue]] {
        var statement: OpaquePointer?
        defer { sqlite3_finalize(statement) }
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteError.prepare(Self.lastMessage(db))
        }
        try bind(values, to: statement)
        var output: [[String: SQLiteValue]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw SQLiteError.step(Self.lastMessage(db)) }
            let count = sqlite3_column_count(statement)
            var row: [String: SQLiteValue] = [:]
            for index in 0..<count {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER:
                    row[name] = .integer(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT:
                    row[name] = .real(sqlite3_column_double(statement, index))
                case SQLITE_TEXT:
                    row[name] = .text(String(cString: sqlite3_column_text(statement, index)))
                default:
                    row[name] = .null
                }
            }
            output.append(row)
        }
        return output
    }

    public func lastInsertRowID() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    public var changes: Int {
        Int(sqlite3_changes(db))
    }

    public func checkpointWAL() throws {
        let result = try rows("PRAGMA wal_checkpoint(TRUNCATE)").first ?? [:]
        guard (result["busy"]?.int ?? 0) == 0 else {
            throw SQLiteError.step("SQLite WAL checkpoint could not acquire the database lock")
        }
    }

    public func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    public func backup(to destinationPath: String) throws {
        var destination: OpaquePointer?
        guard sqlite3_open_v2(destinationPath, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            defer { sqlite3_close(destination) }
            throw SQLiteError.backup("\(Self.lastMessage(destination)) [\(destinationPath)]")
        }
        defer { sqlite3_close(destination) }
        guard let backup = sqlite3_backup_init(destination, "main", db, "main") else {
            throw SQLiteError.backup("\(Self.lastMessage(destination)) while initialising backup [\(destinationPath)]")
        }
        let result = sqlite3_backup_step(backup, -1)
        let finishResult = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finishResult == SQLITE_OK else {
            throw SQLiteError.backup("\(Self.lastMessage(destination)) while copying backup [\(destinationPath)]")
        }
        // A copied database must be self-contained. Leaving the destination in
        // WAL mode can make a read-only verification depend on sidecar files
        // that were never part of the backup operation.
        guard sqlite3_exec(destination, "PRAGMA journal_mode=DELETE", nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.backup("\(Self.lastMessage(destination)) while finalising backup [\(destinationPath)]")
        }
    }

    public func integrityCheck() throws -> String {
        try rows("PRAGMA integrity_check").first?.values.first?.string ?? "No integrity result"
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer?) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null:
                result = sqlite3_bind_null(statement, index)
            case .integer(let number):
                result = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                result = sqlite3_bind_double(statement, index, number)
            case .text(let text):
                result = sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
            }
            guard result == SQLITE_OK else { throw SQLiteError.bind(Self.lastMessage(db)) }
        }
    }

    private static func lastMessage(_ db: OpaquePointer?) -> String {
        if let pointer = sqlite3_errmsg(db) {
            return String(cString: pointer)
        }
        return "Unknown SQLite error"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
