// ORIX Clean — Packages/ORIXCleanCore/Sources/ORIXCleanCore/Persistence/HistoryStore.swift
// Description: Local SQLite store: volume samples, watched-folder samples, cleanup operation log, saved workflows.
// Author: Simon-Pierre Boucher — contact@spboucher.ai
import Foundation
import SQLite3

public struct VolumeSample: Sendable, Hashable, Identifiable {
    public var id: Double { date.timeIntervalSince1970 }
    public var date: Date
    public var volumeID: String
    public var name: String
    public var total: Int64
    public var available: Int64
    public var used: Int64 { max(0, total - available) }
}

public struct FolderSample: Sendable, Hashable, Identifiable {
    public var id: String { path + "\(date.timeIntervalSince1970)" }
    public var date: Date
    public var path: String
    public var logical: Int64
    public var allocated: Int64
    public var files: Int
}

public enum StoreError: Error, Sendable { case sqlite(String) }

/// One connection guarded by a lock. Every write is a single statement or a transaction.
public final class HistoryStore: @unchecked Sendable {
    private var db: OpaquePointer?
    private let lock = NSLock()
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    /// `path` nil opens an in-memory store (tests, screenshots).
    public init(path: String?) throws {
        if let path { try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true) }
        guard sqlite3_open_v2(path ?? ":memory:", &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            throw StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
        }
        try exec("""
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS volume_samples(ts REAL NOT NULL, volume TEXT NOT NULL, name TEXT NOT NULL, total INTEGER NOT NULL, available INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS volume_samples_i ON volume_samples(volume, ts);
        CREATE TABLE IF NOT EXISTS folder_samples(ts REAL NOT NULL, path TEXT NOT NULL, logical INTEGER NOT NULL, allocated INTEGER NOT NULL, files INTEGER NOT NULL);
        CREATE INDEX IF NOT EXISTS folder_samples_i ON folder_samples(path, ts);
        CREATE TABLE IF NOT EXISTS watched(path TEXT PRIMARY KEY);
        CREATE TABLE IF NOT EXISTS operations(id TEXT PRIMARY KEY, ts REAL NOT NULL, json BLOB NOT NULL);
        CREATE TABLE IF NOT EXISTS documents(kind TEXT NOT NULL, id TEXT NOT NULL, json BLOB NOT NULL, PRIMARY KEY(kind, id));
        """)
    }

    deinit { sqlite3_close_v2(db) }

    public static func defaultPath() -> String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ORIX Clean/history.sqlite").path
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let m = err.map { String(cString: $0) } ?? "sqlite"
            sqlite3_free(err)
            throw StoreError.sqlite(m)
        }
    }

    private enum Value { case real(Double), int(Int64), text(String), blob(Data) }

    @discardableResult
    private func run<T>(_ sql: String, _ values: [Value] = [], row: ((OpaquePointer) -> T)? = nil) -> [T] {
        lock.lock(); defer { lock.unlock() }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, v) in values.enumerated() {
            let n = Int32(i + 1)
            switch v {
            case let .real(d): sqlite3_bind_double(stmt, n, d)
            case let .int(x): sqlite3_bind_int64(stmt, n, x)
            case let .text(s): sqlite3_bind_text(stmt, n, s, -1, Self.transient)
            case let .blob(d): _ = d.withUnsafeBytes { sqlite3_bind_blob(stmt, n, $0.baseAddress, Int32(d.count), Self.transient) }
            }
        }
        var out: [T] = []
        while sqlite3_step(stmt) == SQLITE_ROW { if let row { out.append(row(stmt)) } }
        return out
    }

    private func text(_ s: OpaquePointer, _ i: Int32) -> String { sqlite3_column_text(s, i).map { String(cString: $0) } ?? "" }
    private func blob(_ s: OpaquePointer, _ i: Int32) -> Data {
        guard let p = sqlite3_column_blob(s, i) else { return Data() }
        return Data(bytes: p, count: Int(sqlite3_column_bytes(s, i)))
    }

    // MARK: Volumes

    /// Records one sample unless the previous one for this volume is newer than `minimumInterval` and unchanged within 1 MB.
    public func record(volume v: VolumeInfo, at date: Date = Date(), minimumInterval: TimeInterval = 900) {
        if let last = volumeSamples(volumeID: v.id, since: nil).last, date.timeIntervalSince(last.date) < minimumInterval,
           abs(last.available - v.available) < 1_000_000 { return }
        run("INSERT INTO volume_samples VALUES(?,?,?,?,?)", [.real(date.timeIntervalSince1970), .text(v.id), .text(v.name), .int(v.total), .int(v.available)]) as [Void]
    }

    public func volumeSamples(volumeID: String, since: Date?) -> [VolumeSample] {
        run("SELECT ts, volume, name, total, available FROM volume_samples WHERE volume=? AND ts>=? ORDER BY ts",
            [.text(volumeID), .real(since?.timeIntervalSince1970 ?? 0)]) { [self] s in
            VolumeSample(date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), volumeID: text(s, 1), name: text(s, 2),
                         total: sqlite3_column_int64(s, 3), available: sqlite3_column_int64(s, 4))
        }
    }

    /// Date of the first sample: history does not exist before it.
    public func monitoringStart() -> Date? {
        let rows: [Double] = run("SELECT MIN(ts) FROM volume_samples") { sqlite3_column_type($0, 0) == SQLITE_NULL ? -1 : sqlite3_column_double($0, 0) }
        guard let t = rows.first, t >= 0 else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    // MARK: Folders

    public func watch(_ path: String) { run("INSERT OR IGNORE INTO watched VALUES(?)", [.text(path)]) as [Void] }
    public func unwatch(_ path: String) { run("DELETE FROM watched WHERE path=?", [.text(path)]) as [Void] }
    public func watched() -> [String] { run("SELECT path FROM watched ORDER BY path") { [self] in text($0, 0) } }

    public func record(folder path: String, measurement m: Measurement, at date: Date = Date()) {
        run("INSERT INTO folder_samples VALUES(?,?,?,?,?)", [.real(date.timeIntervalSince1970), .text(path), .int(m.logical), .int(m.allocated), .int(Int64(m.files))]) as [Void]
    }

    public func folderSamples(path: String) -> [FolderSample] {
        run("SELECT ts, path, logical, allocated, files FROM folder_samples WHERE path=? ORDER BY ts", [.text(path)]) { [self] s in
            FolderSample(date: Date(timeIntervalSince1970: sqlite3_column_double(s, 0)), path: text(s, 1), logical: sqlite3_column_int64(s, 2),
                         allocated: sqlite3_column_int64(s, 3), files: Int(sqlite3_column_int64(s, 4)))
        }
    }

    // MARK: Operations

    public func save(_ report: DeletionReport) {
        guard let data = try? JSONEncoder().encode(report) else { return }
        run("INSERT OR REPLACE INTO operations VALUES(?,?,?)", [.text(report.id.uuidString), .real(report.started.timeIntervalSince1970), .blob(data)]) as [Void]
    }

    public func operations(limit: Int = 200) -> [DeletionReport] {
        let rows: [Data] = run("SELECT json FROM operations ORDER BY ts DESC LIMIT ?", [.int(Int64(limit))]) { [self] in blob($0, 0) }
        return rows.compactMap { try? JSONDecoder().decode(DeletionReport.self, from: $0) }
    }

    // MARK: Documents (saved workflows and similar small values)

    public func saveDocument<T: Encodable>(_ value: T, kind: String, id: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        run("INSERT OR REPLACE INTO documents VALUES(?,?,?)", [.text(kind), .text(id), .blob(data)]) as [Void]
    }

    public func documents<T: Decodable>(_ type: T.Type, kind: String) -> [T] {
        let rows: [Data] = run("SELECT json FROM documents WHERE kind=? ORDER BY id", [.text(kind)]) { [self] in blob($0, 0) }
        return rows.compactMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    public func deleteDocument(kind: String, id: String) { run("DELETE FROM documents WHERE kind=? AND id=?", [.text(kind), .text(id)]) as [Void] }

    /// Removes every stored sample and operation (Settings > Erase history).
    public func eraseAll() { try? exec("DELETE FROM volume_samples; DELETE FROM folder_samples; DELETE FROM operations;") }
}

public enum Trend {
    /// Least-squares slope of used space, in bytes per day. Nil with fewer than 3 samples or under 6 hours of data.
    public static func bytesPerDay(_ samples: [VolumeSample]) -> Double? {
        guard samples.count >= 3, let first = samples.first, let last = samples.last, last.date.timeIntervalSince(first.date) >= 6 * 3600 else { return nil }
        let xs = samples.map { $0.date.timeIntervalSince(first.date) / 86400 }
        let ys = samples.map { Double($0.used) }
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        var num = 0.0, den = 0.0
        for i in xs.indices { num += (xs[i] - mx) * (ys[i] - my); den += (xs[i] - mx) * (xs[i] - mx) }
        return den > 0 ? num / den : nil
    }
}
