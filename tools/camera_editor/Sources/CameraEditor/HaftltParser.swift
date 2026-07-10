import Foundation

/// Nombre de calle extraído de la tabla de Pascal-strings de un .haftlt.
struct StreetName: Identifiable, Hashable {
    let idx: Int
    let fileOffset: Int
    let text: String
    var id: Int { idx }
}

/// Registro de 16 bytes de `linked_records`, con el LINK_ID candidato
/// confirmado en la sesión 2026-07-10 (campo f6/f7, ver docs/hafr_spatial_index.md).
struct LinkedRecord: Identifiable, Hashable {
    let idx: Int
    let f: [UInt16] // 8 campos
    var linkId: UInt32 { UInt32(f[6]) | (UInt32(f[7]) << 16) }
    var id: Int { idx }
}

enum HaftltParseError: Error, LocalizedError {
    case cannotRead(String)
    case noStringPool

    var errorDescription: String? {
        switch self {
        case .cannotRead(let path): return "No se pudo leer el fichero: \(path)"
        case .noStringPool: return "No se encontró la tabla de nombres de calle en este .haftlt"
        }
    }
}

enum HaftltParser {

    static func u32(_ data: [UInt8], _ off: Int) -> UInt32 {
        UInt32(data[off]) | (UInt32(data[off + 1]) << 8) | (UInt32(data[off + 2]) << 16) | (UInt32(data[off + 3]) << 24)
    }

    static func u16(_ data: [UInt8], _ off: Int) -> UInt16 {
        UInt16(data[off]) | (UInt16(data[off + 1]) << 8)
    }

    /// True si `raw` es UTF-8 valido y todos sus caracteres son imprimibles.
    private static func looksLikeText(_ raw: ArraySlice<UInt8>) -> String? {
        if raw.isEmpty { return nil }
        guard let txt = String(bytes: raw, encoding: .utf8) else { return nil }
        for scalar in txt.unicodeScalars {
            // aproximacion de Python str.isprintable(): excluir controles y separadores de linea
            if scalar.properties.generalCategory == .control { return nil }
            if scalar.properties.generalCategory == .lineSeparator { return nil }
            if scalar.properties.generalCategory == .paragraphSeparator { return nil }
        }
        return txt
    }

    /// Parsea hacia adelante desde `pos` como Pascal-strings [u8 len][utf8],
    /// tolerando huecos cortos de bytes 0x00 (mismo criterio que parse_haftlt.py).
    private static func parseStringChain(_ data: [UInt8], _ start: Int, maxZeroRun: Int = 8, maxLen: Int = 120) -> ([StreetName], Int) {
        var strings: [StreetName] = []
        var pos = start
        var consecutiveZero = 0
        let n = data.count
        var idx = 0
        while pos < n {
            let length = Int(data[pos])
            if length == 0 {
                consecutiveZero += 1
                pos += 1
                if consecutiveZero > maxZeroRun {
                    pos -= consecutiveZero
                    break
                }
                continue
            }
            if length > maxLen { break }
            guard pos + 1 + length <= n else { break }
            let raw = data[(pos + 1)..<(pos + 1 + length)]
            guard let txt = looksLikeText(raw) else { break }
            consecutiveZero = 0
            strings.append(StreetName(idx: idx, fileOffset: pos, text: txt))
            idx += 1
            pos += 1 + length
        }
        return (strings, pos)
    }

    /// Busca el inicio de la tabla de nombres escaneando byte a byte y
    /// verificando una cadena de al menos `minChain` Pascal-strings validas.
    static func findStringPool(_ data: [UInt8], searchStart: Int, searchEnd: Int, minChain: Int = 15) -> Int? {
        var pos = searchStart
        let n = data.count
        while pos < searchEnd {
            let length = Int(data[pos])
            if length >= 1 && length <= 120, pos + 1 + length <= n {
                let raw = data[(pos + 1)..<(pos + 1 + length)]
                if looksLikeText(raw) != nil {
                    let (chain, _) = parseStringChain(data, pos)
                    if chain.count >= minChain {
                        return pos
                    }
                }
            }
            pos += 1
        }
        return nil
    }

    struct ParsedHaftlt {
        let names: [StreetName]
        let records: [LinkedRecord]
    }

    static func parse(path: String) throws -> ParsedHaftlt {
        guard let nsData = FileManager.default.contents(atPath: path) else {
            throw HaftltParseError.cannotRead(path)
        }
        let data = [UInt8](nsData)

        let sec4End = Int(u32(data, 0xA8)) + Int(u32(data, 0xAC))
        guard let poolStart = findStringPool(data, searchStart: sec4End, searchEnd: data.count) else {
            throw HaftltParseError.noStringPool
        }
        let (names, poolEnd) = parseStringChain(data, poolStart)

        let count = Int(u32(data, poolEnd))
        let dataStart = poolEnd + 16
        var records: [LinkedRecord] = []
        records.reserveCapacity(count)
        for i in 0..<count {
            let off = dataStart + i * 16
            guard off + 16 <= data.count else { break }
            var fields: [UInt16] = []
            fields.reserveCapacity(8)
            for k in 0..<8 {
                fields.append(u16(data, off + k * 2))
            }
            records.append(LinkedRecord(idx: i, f: fields))
        }
        return ParsedHaftlt(names: names, records: records)
    }
}
