import Foundation

/// Envoltorio sobre las herramientas `unzip`/`zip` del sistema para trabajar
/// directamente sobre el ZIP de mapas (17.9 GB) sin tener que extraerlo a
/// mano con Terminal primero. El ZIP contiene ficheros individuales sin
/// comprimir de forma eficiente incluso a cientos de MB (ver
/// docs/haftlt_build_diff_260128.md) -- `unzip -p` es rápido porque
/// solo decodifica la entrada pedida, no el ZIP entero.
enum ZipTool {
    static let haftltPrefix = "Data/Nation/EUR/MAP/HAFTLT/VIT_EUR_"
    static let haftltSuffix = ".haftlt"
    static let speedPatchEntry = "Data/Nation/EUR/MAP/SPEED_PATCH.db"

    enum ZipError: Error, LocalizedError {
        case toolFailed(String, Int32)
        case entryNotFound(String)

        var errorDescription: String? {
            switch self {
            case .toolFailed(let cmd, let code): return "\(cmd) terminó con código \(code)"
            case .entryNotFound(let e): return "No se encontró \(e) dentro del ZIP"
            }
        }
    }

    /// Lista los países disponibles (VIT_EUR_XXX.haftlt) dentro del ZIP.
    static func listCountries(zipPath: String) throws -> [String] {
        let output = try run("/usr/bin/unzip", ["-l", zipPath])
        var countries: [String] = []
        for line in output.split(separator: "\n") {
            guard let range = line.range(of: haftltPrefix) else { continue }
            let rest = line[range.upperBound...]
            if let suffixRange = rest.range(of: haftltSuffix) {
                countries.append(String(rest[rest.startIndex..<suffixRange.lowerBound]))
            }
        }
        return countries.sorted()
    }

    /// Extrae una entrada del ZIP a `destPath`, sin descomprimir el resto.
    static func extract(zipPath: String, entry: String, to destPath: String) throws {
        if FileManager.default.fileExists(atPath: destPath) {
            return // ya extraído en una sesión anterior de la app
        }
        let tmp = destPath + ".partial"
        try runToFile("/usr/bin/unzip", ["-p", zipPath, entry], outputPath: tmp)
        guard FileManager.default.fileExists(atPath: tmp),
              (try? FileManager.default.attributesOfItem(atPath: tmp)[.size] as? Int) != 0 else {
            try? FileManager.default.removeItem(atPath: tmp)
            throw ZipError.entryNotFound(entry)
        }
        try FileManager.default.moveItem(atPath: tmp, toPath: destPath)
    }

    /// Actualiza (in-place) una entrada dentro de una COPIA del ZIP.
    /// NUNCA se llama sobre el ZIP original salvo que el usuario elija
    /// explícitamente esa ruta como destino -- ver aviso en la interfaz.
    static func updateEntry(zipPath: String, entry: String, withFile filePath: String) throws {
        // `zip -j` (junk paths) no sirve aquí porque hay que preservar la ruta
        // interna completa; se copia el fichero editado a esa ruta relativa
        // dentro de un directorio temporal y se usa `zip -u` con esa
        // estructura para que la entrada dentro del ZIP quede correcta.
        let tmpDir = NSTemporaryDirectory() + "camera_editor_zipstage_\(UUID().uuidString)/"
        let entryDir = (entry as NSString).deletingLastPathComponent
        let stagedPath = tmpDir + entry
        try FileManager.default.createDirectory(atPath: tmpDir + entryDir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: filePath, toPath: stagedPath)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        _ = try run("/usr/bin/zip", ["-u", zipPath, entry], currentDirectory: tmpDir)
    }

    // MARK: - Ejecución de procesos

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String], currentDirectory: String? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        if let cd = currentDirectory { process.currentDirectoryURL = URL(fileURLWithPath: cd) }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus != 0 && process.terminationStatus != 11 { // zip: 11 = "nada que actualizar"
            throw ZipError.toolFailed(launchPath, process.terminationStatus)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func runToFile(_ launchPath: String, _ args: [String], outputPath: String) throws {
        FileManager.default.createFile(atPath: outputPath, contents: nil)
        guard let fh = FileHandle(forWritingAtPath: outputPath) else {
            throw ZipError.toolFailed(launchPath, -1)
        }
        defer { try? fh.close() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args
        process.standardOutput = fh
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw ZipError.toolFailed(launchPath, process.terminationStatus)
        }
    }
}
