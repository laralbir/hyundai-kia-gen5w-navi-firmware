import Foundation
import SQLite3

struct SpeedPatchRow: Identifiable, Hashable {
    let linkId: Int64
    let dir: Int
    let spLimit: Int
    let vehicleType: Int?  // nil si esta build de SPEED_PATCH.db no tiene esa columna
    var id: String { "\(linkId)-\(dir)-\(vehicleType ?? -1)" }
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
///
/// El esquema de SPEED_PATCH.db NO es idéntico entre builds: la build
/// 260128 (2025-11-22) eliminó la columna VEHICLE_TYPE por completo
/// (clave primaria pasó de LINK_ID+DIR+VEHICLE_TYPE a solo LINK_ID+DIR).
/// Se detecta en tiempo de apertura vía PRAGMA table_info y se adapta.
final class SpeedPatchStore {
    private var db: OpaquePointer?
    let path: String
    let hasVehicleType: Bool

    init(path: String) throws {
        self.path = path
        if sqlite3_open(path, &db) != SQLITE_OK {
            let msg = String(cString: sqlite3_errmsg(db))
            throw SpeedPatchError.openFailed(msg)
        }
        self.hasVehicleType = Self.detectVehicleTypeColumn(db: db)
    }

    deinit {
        sqlite3_close(db)
    }

    private static func detectVehicleTypeColumn(db: OpaquePointer?) -> Bool {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, "PRAGMA table_info(SPEED_PATCH)", -1, &stmt, nil) == SQLITE_OK else {
            return true // por defecto asumir el esquema "clasico" si no se puede comprobar
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cName = sqlite3_column_text(stmt, 1) {
                let name = String(cString: cName)
                if name.caseInsensitiveCompare("VEHICLE_TYPE") == .orderedSame {
                    return true
                }
            }
        }
        return false
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

    private var selectColumns: String {
        hasVehicleType ? "LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE" : "LINK_ID, DIR, SP_LIMIT"
    }

    /// Listado paginado de TODAS las filas (orden por LINK_ID).
    func browse(offset: Int, limit: Int) throws -> [SpeedPatchRow] {
        let sql = "SELECT \(selectColumns) FROM SPEED_PATCH ORDER BY LINK_ID LIMIT ? OFFSET ?"
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
        guard let stmt = try prepare("SELECT \(selectColumns) FROM SPEED_PATCH WHERE LINK_ID = ?") else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, linkId)
        return readRows(stmt)
    }

    func search(linkIds: [Int64], limit: Int = 500) throws -> [SpeedPatchRow] {
        guard !linkIds.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: linkIds.count).joined(separator: ",")
        let sql = "SELECT \(selectColumns) FROM SPEED_PATCH WHERE LINK_ID IN (\(placeholders)) ORDER BY LINK_ID LIMIT \(limit)"
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
                vehicleType: hasVehicleType ? Int(sqlite3_column_int(stmt, 3)) : nil
            ))
        }
        return rows
    }

    /// Añade o actualiza. Clave primaria LINK_ID+DIR+VEHICLE_TYPE si esta
    /// build tiene esa columna, o solo LINK_ID+DIR si no (build >= 260128).
    func upsert(linkId: Int64, dir: Int, spLimit: Int, vehicleType: Int?) throws {
        let sql: String
        if hasVehicleType {
            sql = """
                INSERT INTO SPEED_PATCH (LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE) VALUES (?,?,?,?)
                ON CONFLICT(LINK_ID, DIR, VEHICLE_TYPE) DO UPDATE SET SP_LIMIT=excluded.SP_LIMIT
                """
        } else {
            sql = """
                INSERT INTO SPEED_PATCH (LINK_ID, DIR, SP_LIMIT) VALUES (?,?,?)
                ON CONFLICT(LINK_ID, DIR) DO UPDATE SET SP_LIMIT=excluded.SP_LIMIT
                """
        }
        guard let stmt = try prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, linkId)
        sqlite3_bind_int(stmt, 2, Int32(dir))
        sqlite3_bind_int(stmt, 3, Int32(spLimit))
        if hasVehicleType {
            sqlite3_bind_int(stmt, 4, Int32(vehicleType ?? 0))
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw SpeedPatchError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    func delete(linkId: Int64, dir: Int, vehicleType: Int?) throws {
        let sql = hasVehicleType
            ? "DELETE FROM SPEED_PATCH WHERE LINK_ID=? AND DIR=? AND VEHICLE_TYPE=?"
            : "DELETE FROM SPEED_PATCH WHERE LINK_ID=? AND DIR=?"
        guard let stmt = try prepare(sql) else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int64(stmt, 1, linkId)
        sqlite3_bind_int(stmt, 2, Int32(dir))
        if hasVehicleType {
            sqlite3_bind_int(stmt, 3, Int32(vehicleType ?? 0))
        }
        if sqlite3_step(stmt) != SQLITE_DONE {
            throw SpeedPatchError.queryFailed(String(cString: sqlite3_errmsg(db)))
        }
    }
}
