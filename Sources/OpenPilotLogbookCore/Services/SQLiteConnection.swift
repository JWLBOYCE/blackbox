import Foundation
import SQLite3

public enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case bind(String)

    public var description: String {
        switch self {
        case .open(let message), .prepare(let message), .step(let message), .bind(let message):
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
            throw SQLiteError.open(SQLiteConnection.lastMessage(db))
        }
        if !readOnly {
            try execute("PRAGMA foreign_keys = ON")
            try execute("PRAGMA journal_mode = WAL")
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
