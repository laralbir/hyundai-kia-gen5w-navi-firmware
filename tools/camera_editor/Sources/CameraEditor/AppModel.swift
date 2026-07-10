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
    // ZIP de mapas + país elegido
    @Published var zipPath: String = ""
    @Published var availableCountries: [String] = []
    @Published var selectedCountry: String = ""
    @Published var cacheDir: String = ""

    // Ficheros ya extraídos (locales, cacheados junto al ZIP)
    @Published var haftltPath: String = ""
    @Published var speedPatchOriginalPath: String = ""
    @Published var writableDBPath: String = ""
    @Published var store: SpeedPatchStore?

    // Datos de .haftlt
    @Published var streetNames: [StreetName] = []
    @Published var linkedRecords: [LinkedRecord] = []
    @Published var linkIdToRecordCount: [UInt32: Int] = [:]
    @Published var linkIdToRecordIndices: [UInt32: [Int]] = [:]

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

    /// Ruta de ejemplo para orientar al usuario en el selector de ficheros.
    /// No se usa como valor real -- es solo el texto de ayuda de la interfaz.
    static let examplePath = "HU/images/navi_eu/S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip"

    // MARK: - Paso 1: elegir el ZIP y listar países

    func loadZip(path: String) {
        isLoading = true
        defer { isLoading = false }
        do {
            let countries = try ZipTool.listCountries(zipPath: path)
            guard !countries.isEmpty else {
                setStatus("No se encontraron VIT_EUR_*.haftlt dentro de este ZIP -- ¿es el ZIP de mapas correcto?", error: true)
                return
            }
            self.zipPath = path
            self.availableCountries = countries
            self.selectedCountry = countries.first ?? ""
            let zipDir = (path as NSString).deletingLastPathComponent
            self.cacheDir = zipDir + "/camera_editor_cache/"
            try FileManager.default.createDirectory(atPath: cacheDir, withIntermediateDirectories: true)
            setStatus("ZIP leído: \(countries.count) países disponibles (\(countries.joined(separator: ", ")))", error: false)
        } catch {
            setStatus("Error leyendo el ZIP: \(error.localizedDescription)", error: true)
        }
    }

    /// Extrae (si hace falta) el .haftlt del país elegido y SPEED_PATCH.db
    /// del ZIP, y los carga. Usa una caché local junto al ZIP para no
    /// re-extraer en cada sesión.
    func extractAndLoadFromZip() {
        guard !zipPath.isEmpty, !selectedCountry.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let haftltEntry = ZipTool.haftltPrefix + selectedCountry + ZipTool.haftltSuffix
            let haftltDest = cacheDir + "VIT_EUR_\(selectedCountry).haftlt"
            setStatus("Extrayendo \(haftltEntry)…", error: false)
            try ZipTool.extract(zipPath: zipPath, entry: haftltEntry, to: haftltDest)

            let speedPatchDest = cacheDir + "SPEED_PATCH.db"
            setStatus("Extrayendo SPEED_PATCH.db (153 MB, puede tardar unos segundos)…", error: false)
            try ZipTool.extract(zipPath: zipPath, entry: ZipTool.speedPatchEntry, to: speedPatchDest)

            loadHaftlt(path: haftltDest)
            loadSpeedPatch(originalPath: speedPatchDest)
        } catch {
            setStatus("Error extrayendo del ZIP: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Paso 2: cargar ficheros ya extraídos (uso directo, sin ZIP)

    func loadHaftlt(path: String) {
        do {
            let parsed = try HaftltParser.parse(path: path)
            self.haftltPath = path
            self.streetNames = parsed.names
            self.linkedRecords = parsed.records
            var counts: [UInt32: Int] = [:]
            var indices: [UInt32: [Int]] = [:]
            for r in parsed.records {
                counts[r.linkId, default: 0] += 1
                indices[r.linkId, default: []].append(r.idx)
            }
            self.linkIdToRecordCount = counts
            self.linkIdToRecordIndices = indices
            setStatus("Cargado: \(parsed.names.count) nombres de calle, \(parsed.records.count) registros linked_records", error: false)
        } catch {
            setStatus("Error cargando .haftlt: \(error.localizedDescription)", error: true)
        }
    }

    func loadSpeedPatch(originalPath: String) {
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

    // MARK: - Paso 3 (opcional, explícito): reinyectar cambios en una copia del ZIP

    /// Actualiza SPEED_PATCH.db dentro de una copia del ZIP. Operación
    /// potencialmente larga sobre un fichero de ~18 GB -- nunca se lanza
    /// automáticamente, solo cuando el usuario pulsa el botón y confirma
    /// una ruta de destino (por defecto NO es el ZIP original).
    func writeBackToZip(destinationZip: String) {
        guard let store, !writableDBPath.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            if destinationZip != zipPath {
                setStatus("Copiando ZIP a \(destinationZip) antes de actualizar (puede tardar varios minutos, ~18 GB)…", error: false)
                if !FileManager.default.fileExists(atPath: destinationZip) {
                    try FileManager.default.copyItem(atPath: zipPath, toPath: destinationZip)
                }
            }
            _ = store // la copia editable ya está en disco (writableDBPath)
            try ZipTool.updateEntry(zipPath: destinationZip, entry: ZipTool.speedPatchEntry, withFile: writableDBPath)
            setStatus("SPEED_PATCH.db actualizado dentro de \(destinationZip). Recuerda: falta recalcular MD5/CRC32 en Rio_MY22_EU.ver -- ver .claude/memory/speed_patch_workflow.md", error: false)
        } catch {
            setStatus("Error actualizando el ZIP: \(error.localizedDescription)", error: true)
        }
    }

    // MARK: - Estado / utilidades comunes

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

    /// Nombre de calle candidato para un LINK_ID: busca su(s) registro(s) en
    /// linked_records (enlace real, vía f6/f7) y devuelve el nombre de calle
    /// cuya posición en la tabla de nombres esté más cerca de la posición de
    /// ese registro. La parte "posición ~ registro" es la MISMA heurística de
    /// proximidad que candidateLinkIds, sin confirmar formalmente (ver
    /// docs/haftlt_build_diff_260128.md) -- se ofrece como candidato, no como
    /// enlace verificado. Devuelve nil si no hay .haftlt cargado o no hay
    /// ningún nombre dentro de la ventana.
    func candidateStreetName(for linkId: UInt32, window: Int = 5) -> String? {
        guard let recordIdx = linkIdToRecordIndices[linkId]?.first, !streetNames.isEmpty else { return nil }
        let lo = max(0, recordIdx - window)
        let hi = min(streetNames.count - 1, recordIdx + window)
        guard lo <= hi else { return nil }
        var best: StreetName?
        var bestDist = Int.max
        for name in streetNames[lo...hi] {
            let d = abs(name.idx - recordIdx)
            if d < bestDist { bestDist = d; best = name }
        }
        return best?.text
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

    func save(linkId: Int64, dir: Int, spLimit: Int, vehicleType: Int?) {
        guard let store else { return }
        do {
            try store.upsert(linkId: linkId, dir: dir, spLimit: spLimit, vehicleType: vehicleType)
            let vtPart = store.hasVehicleType ? " VEHICLE_TYPE=\(vehicleType ?? 0)" : ""
            setStatus("Guardado LINK_ID=\(linkId) DIR=\(dir) SP_LIMIT=\(spLimit)\(vtPart)", error: false)
            refresh()
        } catch {
            setStatus("Error al guardar: \(error.localizedDescription)", error: true)
        }
    }

    func delete(row: SpeedPatchRow) {
        guard let store else { return }
        do {
            try store.delete(linkId: row.linkId, dir: row.dir, vehicleType: row.vehicleType)
            let vtPart = row.vehicleType.map { " VEHICLE_TYPE=\($0)" } ?? ""
            setStatus("Borrado LINK_ID=\(row.linkId) DIR=\(row.dir)\(vtPart)", error: false)
            refresh()
        } catch {
            setStatus("Error al borrar: \(error.localizedDescription)", error: true)
        }
    }
}
