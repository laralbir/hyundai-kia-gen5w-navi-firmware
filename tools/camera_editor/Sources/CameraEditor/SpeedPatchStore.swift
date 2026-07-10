import Foundation
import SQLite3

struct SpeedPatchRow: Identifiable, Hashable {
    let linkId: Int64
    let dir: Int
    let spLimit: Int
    let vehicleType: Int
    var id: String { "\(linkId)-\(dir)-\(vehicleType)" }
}

enum SpeedPatchError: Error, LocalizedError {
    case openFailed(String)
    case queryFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let m): return "No se pudo abrir SPEED_PATCH.db: \(m)"
        case .queryFailed(let m): return "Error de consulta: \(m)"
        }
    }
}

/// Envoltorio sobre SQLite3 para SPEED_PATCH.db. Todas las escrituras van
/// contra una COPIA editable local -- nunca contra el fichero original
/// extraído del ZIP de mapas. Ver .claude/memory/speed_patch_workflow.md
/// para el flujo completo de reempaquetado tras editar.
final class SpeedPatchStore {
    private var db: OpaquePointer?
    let path: String

    init(path: String) throws {
        self.path = path
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SpeedPatchError.openFailed(msg)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Crea una copia editable de `sourcePath` en `destPath` si no existe ya.
    static func ensureWritableCopy(source sourcePath: String, dest destPath: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destPath) {
            try fm.copyItem(atPath: sourcePath, toPath: destPath)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SpeedPatchError.queryFailed(msg)
        }
        return stmt
    }

    /// Listado paginado de TODAS las filas (orden por LINK_ID).
    func browse(offset: Int, limit: Int) throws -> [SpeedPatchRow] {
        let sql = "SELECT LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE FROM SPEED_PATCH ORDER BY LINK_ID LIMIT ? OFFSET ?"
        guard let stmt = try prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, Int32(limit))
        sqlite3_bind_int(stmt, 2, Int32(offset))
        return readRows(stmt)
    }

    func totalCount() throws -> Int {
        guard let stmt = try prepare("SELECT COUNT(*) FROM SPEED_PATCH") else { return 0 }
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW {
            return Int(sqlite3_column_int64(stmt, 0))
        }
        return 0
    }

    func search(linkId: Int64) throws -> [SpeedPatchRow] {
        guard let stmt = try prepare("SELECT LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE FROM SPEED_PATCH WHERE LINK_ID = ?") else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, linkId)
        return readRows(stmt)
    }

    func search(linkIds: [Int64], limit: Int = 500) throws -> [SpeedPatchRow] {
        guard !linkIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: linkIds.count).joined(separator: ",")
        let sql = "SELECT LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE FROM SPEED_PATCH WHERE LINK_ID IN (\(placeholders)) ORDER BY LINK_ID LIMIT \(limit)"
        guard let stmt = try prepare(sql) else { return [] }
        defer { sqlite3_finalize(stmt) }
        for (i, lid) in linkIds.enumerated() {
            sqlite3_bind_int64(stmt, Int32(i + 1), lid)
        }
        return readRows(stmt)
    }

    private func readRows(_ stmt: OpaquePointer?) -> [SpeedPatchRow] {
        var rows: [SpeedPatchRow] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(SpeedPatchRow(
                linkId: sqlite3_column_int64(stmt, 0),
                dir: Int(sqlite3_column_int(stmt, 1)),
                spLimit: Int(sqlite3_column_int(stmt, 2)),
                vehicleType: Int(sqlite3_column_int(stmt, 3))
            ))
        }
        return rows
    }

    /// Añade o actualiza (misma clave primaria LINK_ID+DIR+VEHICLE_TYPE).
    func upsert(linkId: Int64, dir: Int, spLimit: Int, vehicleType: Int) throws {
        let sql = """
            INSERT INTO SPEED_PATCH (LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE) VALUES (?,?,?,?)
            ON CONFLICT(LINK_ID, DIR, VEHICLE_TYPE) DO UPDATE SET SP_LIMIT=excluded.SP_LIMIT
            """
        guard let stmt = try prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, linkId)
        sqlite3_bind_int(stmt, 2, Int32(dir))
        sqlite3_bind_int(stmt, 3, Int32(spLimit))
        sqlite3_bind_int(stmt, 4, Int32(vehicleType))
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw SpeedPatchError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func delete(linkId: Int64, dir: Int, vehicleType: Int) throws {
        guard let stmt = try prepare("DELETE FROM SPEED_PATCH WHERE LINK_ID=? AND DIR=? AND VEHICLE_TYPE=?") else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, linkId)
        sqlite3_bind_int(stmt, 2, Int32(dir))
        sqlite3_bind_int(stmt, 3, Int32(vehicleType))
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw SpeedPatchError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}
