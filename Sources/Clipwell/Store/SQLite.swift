import Foundation
import SQLite3

/// `SQLITE_TRANSIENT` tells SQLite to copy the bound bytes rather than hold a
/// pointer into memory we're about to free. It's a macro in C so Swift can't
/// see it; this is the standard reconstruction.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

enum SQLiteError: Error, CustomStringConvertible {
    case open(String)
    case prepare(String)
    case step(String)
    case exec(String)

    var description: String {
        switch self {
        case .open(let message):    return "sqlite open failed: \(message)"
        case .prepare(let message): return "sqlite prepare failed: \(message)"
        case .step(let message):    return "sqlite step failed: \(message)"
        case .exec(let message):    return "sqlite exec failed: \(message)"
        }
    }
}

/// Minimal SQLite wrapper.
///
/// Deliberately dependency-free: the C API is stable, always present on macOS,
/// and keeps `swift build` offline.
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(path, &handle, flags, nil) == SQLITE_OK, let handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw SQLiteError.open(message)
        }
        self.handle = handle
        // WAL keeps the capture thread's writes from blocking UI reads.
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
        try execute("PRAGMA foreign_keys = ON;")
        sqlite3_busy_timeout(handle, 3000)
    }

    deinit {
        if let handle { sqlite3_close_v2(handle) }
    }

    private var errorMessage: String {
        guard let handle else { return "no handle" }
        return String(cString: sqlite3_errmsg(handle))
    }

    func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteError.exec("\(errorMessage) -- while running: \(sql)")
        }
    }

    /// `execute` that reports failure instead of throwing. Used for optional
    /// features such as FTS5, which may not be compiled into the system SQLite.
    @discardableResult
    func tryExecute(_ sql: String) -> Bool {
        sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    }

    var lastInsertRowID: Int64 {
        sqlite3_last_insert_rowid(handle)
    }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            _ = tryExecute("ROLLBACK;")
            throw error
        }
    }

    /// Runs a statement, invoking `row` once per result row.
    func query(_ sql: String, _ bindings: [SQLiteValue] = [], row: (SQLiteRow) -> Void) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw SQLiteError.prepare("\(errorMessage) -- while preparing: \(sql)")
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_ROW {
                row(SQLiteRow(statement: statement))
            } else if code == SQLITE_DONE {
                break
            } else {
                throw SQLiteError.step("\(errorMessage) -- while running: \(sql)")
            }
        }
    }

    /// Runs a statement that returns no rows.
    func run(_ sql: String, _ bindings: [SQLiteValue] = []) throws {
        try query(sql, bindings) { _ in }
    }

    private func bind(_ values: [SQLiteValue], to statement: OpaquePointer) throws {
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let code: Int32
            switch value {
            case .null:
                code = sqlite3_bind_null(statement, index)
            case .integer(let number):
                code = sqlite3_bind_int64(statement, index, number)
            case .real(let number):
                code = sqlite3_bind_double(statement, index, number)
            case .text(let string):
                code = sqlite3_bind_text(statement, index, string, -1, SQLITE_TRANSIENT)
            case .blob(let data):
                if data.isEmpty {
                    code = sqlite3_bind_zeroblob(statement, index, 0)
                } else {
                    code = data.withUnsafeBytes { buffer in
                        sqlite3_bind_blob(statement, index, buffer.baseAddress, Int32(data.count), SQLITE_TRANSIENT)
                    }
                }
            }
            guard code == SQLITE_OK else {
                throw SQLiteError.prepare("failed to bind parameter \(index): \(errorMessage)")
            }
        }
    }
}

enum SQLiteValue {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    static func int(_ value: Int) -> SQLiteValue { .integer(Int64(value)) }
    static func bool(_ value: Bool) -> SQLiteValue { .integer(value ? 1 : 0) }
    static func date(_ value: Date) -> SQLiteValue { .real(value.timeIntervalSince1970) }
    static func optionalText(_ value: String?) -> SQLiteValue {
        guard let value else { return .null }
        return .text(value)
    }
}

/// Column accessors for one result row. Only valid inside the `row` callback.
struct SQLiteRow {
    let statement: OpaquePointer

    func int64(_ index: Int32) -> Int64 { sqlite3_column_int64(statement, index) }
    func int(_ index: Int32) -> Int { Int(sqlite3_column_int64(statement, index)) }
    func double(_ index: Int32) -> Double { sqlite3_column_double(statement, index) }
    func bool(_ index: Int32) -> Bool { sqlite3_column_int64(statement, index) != 0 }
    func date(_ index: Int32) -> Date { Date(timeIntervalSince1970: sqlite3_column_double(statement, index)) }

    func string(_ index: Int32) -> String { optionalString(index) ?? "" }

    func optionalString(_ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_text(statement, index)
        else { return nil }
        return String(cString: pointer)
    }

    func optionalData(_ index: Int32) -> Data? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL,
              let pointer = sqlite3_column_blob(statement, index)
        else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return Data(bytes: pointer, count: count)
    }
}
