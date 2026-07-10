import Foundation
import SwiftUI

enum SearchMode: String, CaseIterable, Identifiable {
    case browseAll = "Listar todo"
    case byLinkId = "Por LINK_ID"
    case byStreet = "Por dirección"
    var id: String { rawValue }
}

@MainActor
final class AppModel: ObservableObject {
    // Ficheros cargados
    @Published var haftltPath: String = ""
    @Published var speedPatchOriginalPath: String = ""
    @Published var writableDBPath: String = ""
    @Published var store: SpeedPatchStore?

    // Datos de .haftlt
    @Published var streetNames: [StreetName] = []
    @Published var linkedRecords: [LinkedRecord] = []
    @Published var linkIdToRecordCount: [UInt32: Int] = [:]

    // Busqueda / listado
    @Published var searchMode: SearchMode = .browseAll
    @Published var streetQuery: String = ""
    @Published var linkIdQuery: String = ""
    @Published var streetMatches: [StreetName] = []
    @Published var rows: [SpeedPatchRow] = []
    @Published var page: Int = 0
    let pageSize = 100
    @Published var totalCount: Int = 0

    @Published var statusMessage: String = ""
    @Published var statusIsError: Bool = false
    @Published var isLoading: Bool = false

    func loadHaftlt(path: String) {
        isLoading = true
        defer { isLoading = false }
        do {
            let parsed = try HaftltParser.parse(path: path)
            self.haftltPath = path
            self.streetNames = parsed.names
            self.linkedRecords = parsed.records
            var counts: [UInt32: Int] = [:]
            for r in parsed.records { counts[r.linkId, default: 0] += 1 }
            self.linkIdToRecordCount = counts
            setStatus("Cargado: \(parsed.names.count) nombres de calle, \(parsed.records.count) registros linked_records", error: false)
        } catch {
            setStatus("Error cargando .haftlt: \(error.localizedDescription)", error: true)
        }
    }

    func loadSpeedPatch(originalPath: String) {
        isLoading = true
        defer { isLoading = false }
        let dest = (originalPath as NSString).deletingPathExtension + "_editable.db"
        do {
            try SpeedPatchStore.ensureWritableCopy(source: originalPath, dest: dest)
            let s = try SpeedPatchStore(path: dest)
            self.store = s
            self.speedPatchOriginalPath = originalPath
            self.writableDBPath = dest
            self.totalCount = (try? s.totalCount()) ?? 0
            setStatus("SPEED_PATCH.db cargado (\(totalCount) filas). Copia editable: \(dest)", error: false)
            refresh()
        } catch {
            setStatus("Error cargando SPEED_PATCH.db: \(error.localizedDescription)", error: true)
        }
    }

    func setStatus(_ msg: String, error: Bool) {
        statusMessage = msg
        statusIsError = error
    }

    func updateStreetMatches() {
        let q = streetQuery.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { streetMatches = []; return }
        streetMatches = streetNames.filter { $0.text.lowercased().contains(q) }.prefix(200).map { $0 }
    }

    /// LINK_ID de linked_records cuyo array-index esta cerca del indice de
    /// nombre seleccionado -- heuristica de proximidad, NO un enlace
    /// confirmado (ver docs/haftlt_build_diff_260128.md: la conexion
    /// nombre<->registro exacta sigue sin resolverse). Se muestra como
    /// "candidatos cercanos", no como verdad confirmada.
    func candidateLinkIds(nearStreetIndex idx: Int, window: Int = 5) -> [UInt32] {
        guard !linkedRecords.isEmpty else { return [] }
        let lo = max(0, idx - window)
        let hi = min(linkedRecords.count - 1, idx + window)
        guard lo <= hi else { return [] }
        return Array(Set(linkedRecords[lo...hi].map { $0.linkId }))
    }

    func refresh() {
        guard let store else { rows = []; return }
        do {
            switch searchMode {
            case .browseAll:
                totalCount = try store.totalCount()
                rows = try store.browse(offset: page * pageSize, limit: pageSize)
            case .byLinkId:
                if let lid = Int64(linkIdQuery.trimmingCharacters(in: .whitespaces)) {
                    rows = try store.search(linkId: lid)
                } else {
                    rows = []
                }
            case .byStreet:
                let ids = streetMatches.isEmpty ? [] :
                    Array(Set(streetMatches.indices.flatMap { candidateLinkIds(nearStreetIndex: streetMatches[$0].idx) }))
                rows = try store.search(linkIds: ids.map { Int64($0) })
            }
        } catch {
            setStatus("Error consultando: \(error.localizedDescription)", error: true)
        }
    }

    func nextPage() { page += 1; refresh() }
    func prevPage() { if page > 0 { page -= 1; refresh() } }

    func save(linkId: Int64, dir: Int, spLimit: Int, vehicleType: Int) {
        guard let store else { return }
        do {
            try store.upsert(linkId: linkId, dir: dir, spLimit: spLimit, vehicleType: vehicleType)
            setStatus("Guardado LINK_ID=\(linkId) DIR=\(dir) SP_LIMIT=\(spLimit) VEHICLE_TYPE=\(vehicleType)", error: false)
            refresh()
        } catch {
            setStatus("Error al guardar: \(error.localizedDescription)", error: true)
        }
    }

    func delete(row: SpeedPatchRow) {
        guard let store else { return }
        do {
            try store.delete(linkId: row.linkId, dir: row.dir, vehicleType: row.vehicleType)
            setStatus("Borrado LINK_ID=\(row.linkId) DIR=\(row.dir) VEHICLE_TYPE=\(row.vehicleType)", error: false)
            refresh()
        } catch {
            setStatus("Error al borrar: \(error.localizedDescription)", error: true)
        }
    }
}
