#!/usr/bin/env python3
"""
Desempaqueta un fichero VIT_EUR_XXX.haftlt (ya extraido del ZIP de mapas) en
sus estructuras internas conocidas: cabecera, tabla indice, Secciones 1-4,
la tabla de nombres de calle (Pascal-strings UTF-8) y la tabla de registros
de 16 bytes que la sigue.

Escribe CSV/JSON legibles en un directorio de salida. No decodifica
coordenadas GPS ni registros de camara -- ese formato sigue sin resolverse.
Ver docs/haftlt_build_diff_260128.md para el estado completo de la
investigacion y el significado de cada seccion.

Uso (un solo fichero, estructura estatica -- indice y secciones 1-4):
    python3 parse_haftlt.py VIT_EUR_SPN.haftlt -o salida/

Uso (con comparacion, para localizar tambien las zonas candidatas que
crecieron entre dos builds -- region media y region cola):
    python3 parse_haftlt.py NEW/VIT_EUR_SPN.haftlt --other OLD/VIT_EUR_SPN.haftlt -o salida/

La salida se escribe fuera del repositorio git-trackeado (o en una ruta ya
cubierta por .gitignore, p.ej. bajo HU/) -- estos CSV derivan directamente
del dato propietario de HERE y no deben commitearse.
"""
import argparse
import csv
import json
import os
import struct
import sys


def u32(data, off):
    return struct.unpack_from("<I", data, off)[0]


def u16(data, off):
    return struct.unpack_from("<H", data, off)[0]


def parse_header(data):
    def cstr(start, end):
        return data[start:end].split(b"\0")[0].decode("ascii", "replace")

    return {
        "file_size": len(data),
        "format_version_str": cstr(0x00, 0x1F),
        "data_version_field_0x40": u32(data, 0x40),
        "data_version_field_0x40_hex": hex(u32(data, 0x40)),
        "data_version_decimal_0x4c": u32(data, 0x4C),
        "crc_or_hash_0x80": u32(data, 0x80),
        "const_0x84": u32(data, 0x84),
        "const_0x88_sec1_overhead": u32(data, 0x88),
        "sec1_record_count": u32(data, 0x8C),
        "sec1_size": u32(data, 0x90),
        "sec1_start": u32(data, 0x94),
        "sec1_end": u32(data, 0x98),
        "sec2_start": u32(data, 0x9C),
        "sec2_end": u32(data, 0xA0),
        "sec3_size": u32(data, 0xA4),
        "sec3_end": u32(data, 0xA8),
        "sec4_size": u32(data, 0xAC),
        "sec4_end": u32(data, 0xA8) + u32(data, 0xAC),
    }


def parse_index_table(data, start, end, writer):
    writer.writerow(["idx", "file_offset", "key"])
    pos = start
    i = 0
    while pos + 6 <= end:
        file_offset = u32(data, pos)
        key = u16(data, pos + 4)
        writer.writerow([i, file_offset, key])
        pos += 6
        i += 1
    return i


def parse_sec1(data, start, end, record_count, overhead, writer):
    writer.writerow(["idx", "value"])
    base = start + overhead
    for i in range(record_count):
        off = base + i
        if off >= end:
            break
        writer.writerow([i, data[off]])
    return record_count


def parse_u16_pairs(data, start, end, writer):
    writer.writerow(["idx", "file_offset", "field_a", "field_b"])
    pos = start
    i = 0
    while pos + 4 <= end:
        a = u16(data, pos)
        b = u16(data, pos + 2)
        writer.writerow([i, pos, a, b])
        pos += 4
        i += 1
    return i


def parse_u32_id_blocks(data, start, end, writer):
    writer.writerow(["idx", "file_offset", "raw_hex", "id", "high_bit"])
    pos = start
    i = 0
    while pos + 4 <= end:
        v = u32(data, pos)
        writer.writerow([i, pos, hex(v), v & 0x7FFFFFFF, (v >> 31) & 1])
        pos += 4
        i += 1
    return i


def _looks_like_text(raw):
    """True si raw es una cadena UTF-8 valida compuesta solo de caracteres imprimibles."""
    if len(raw) == 0:
        return None
    try:
        txt = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not all(ch.isprintable() for ch in txt):
        return None
    return txt


def _parse_string_chain(data, pos, max_zero_run=8, max_len=120):
    """Parsea hacia adelante desde pos como Pascal-strings [u8 len][utf8 bytes].
    Tolera huecos cortos de bytes 0x00 (separadores/relleno entre sub-tablas).
    Devuelve (lista_de_(offset,texto), offset_final)."""
    strings = []
    consecutive_zero = 0
    while pos < len(data):
        length = data[pos]
        if length == 0:
            consecutive_zero += 1
            pos += 1
            if consecutive_zero > max_zero_run:
                pos -= consecutive_zero
                break
            continue
        if length > max_len:
            break
        raw = data[pos + 1 : pos + 1 + length]
        txt = _looks_like_text(raw)
        if txt is None:
            break
        consecutive_zero = 0
        strings.append((pos, txt))
        pos += 1 + length
    return strings, pos


def find_string_pool(data, search_start, search_end, min_chain=15):
    """Busca el inicio de una tabla de Pascal-strings UTF-8 (nombres de calle)
    escaneando byte a byte y verificando que arranca una cadena de al menos
    min_chain entradas consecutivas validas (para descartar coincidencias
    puntuales en datos binarios). Devuelve offset de inicio o None."""
    pos = search_start
    while pos < search_end:
        length = data[pos]
        if 1 <= length <= 120:
            raw = data[pos + 1 : pos + 1 + length]
            if _looks_like_text(raw) is not None:
                chain, _ = _parse_string_chain(data, pos)
                if len(chain) >= min_chain:
                    return pos
        pos += 1
    return None


def parse_string_pool(data, start, writer):
    strings, end = _parse_string_chain(data, start)
    writer.writerow(["idx", "file_offset", "length", "text"])
    for i, (off, txt) in enumerate(strings):
        writer.writerow([i, off, len(txt.encode("utf-8")), txt])
    return len(strings), end


def try_parse_linked_records(data, pool_end, writer, record_size=16):
    """Justo tras la tabla de nombres suele venir: [u32 record_count][12 bytes
    padding][record_count registros de 16 bytes]. Se verifica aritmeticamente
    contra el tamano real del fichero antes de aceptarlo -- ver
    docs/haftlt_build_diff_260128.md para el detalle de esta comprobacion."""
    if pool_end + 16 > len(data):
        return None
    count = u32(data, pool_end)
    data_start = pool_end + 16
    expected_end = data_start + count * record_size
    slack = len(data) - expected_end
    if count <= 0 or not (0 <= slack <= 64):
        return None  # no encaja -- no forzar la hipotesis

    writer.writerow(["idx", "file_offset", "f0", "f1", "f2", "f3", "f4", "f5", "f6", "f7"])
    for i in range(count):
        off = data_start + i * record_size
        vals = struct.unpack_from("<HHHHHHHH", data, off)
        writer.writerow([i, off] + list(vals))

    return {
        "count_field_offset": pool_end,
        "record_count": count,
        "record_size": record_size,
        "data_range": [data_start, expected_end],
        "trailing_slack_bytes": slack,
        "note": (
            "Estructura confirmada aritmeticamente (count*16 + cabecera encaja "
            "con el tamano real del fichero, holgura <64B). El SIGNIFICADO de "
            "los campos f0-f7 NO esta confirmado. f1/f5/f7 parecen IDs de grupo "
            "casi constantes; f2/f3 alternan un valor real con el centinela "
            "0xFFFF y suelen rondar el indice del propio registro (ver "
            "haftlt_format.md). La hipotesis 'f0 = offset a la tabla de "
            "nombres' se probo y quedo REFUTADA (0/30 aciertos) -- no dar la "
            "conexion nombre<->registro por buena sin mas evidencia."
        ),
    }


def common_prefix(a, b, off_a, off_b, max_len):
    p = 0
    while p < max_len and a[off_a + p] == b[off_b + p]:
        p += 1
    return p


def common_suffix(a, b, max_len):
    s = 0
    la, lb = len(a), len(b)
    while s < max_len and a[la - 1 - s] == b[lb - 1 - s]:
        s += 1
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("haftlt_file", help="Fichero .haftlt a desempaquetar")
    ap.add_argument("--other", help="Fichero .haftlt de la otra build (misma pais) -- para localizar zonas candidatas de crecimiento")
    ap.add_argument("-o", "--output", required=True, help="Directorio de salida")
    args = ap.parse_args()

    os.makedirs(args.output, exist_ok=True)

    with open(args.haftlt_file, "rb") as f:
        data = f.read()

    hdr = parse_header(data)

    growth = {}
    if args.other:
        with open(args.other, "rb") as f:
            other = f.read()
        other_hdr = parse_header(other)

        mid_max = min(hdr["sec2_start"] - hdr["sec1_end"], other_hdr["sec2_start"] - other_hdr["sec1_end"])
        mid_prefix = common_prefix(data, other, hdr["sec1_end"], other_hdr["sec1_end"], mid_max)

        tail_max = min(len(data) - hdr["sec4_end"], len(other) - other_hdr["sec4_end"])
        tail_suffix = common_suffix(data[hdr["sec4_end"]:], other[other_hdr["sec4_end"]:], tail_max)

        mid_new_start = hdr["sec1_end"] + mid_prefix
        mid_new_end = hdr["sec2_start"]
        tail_new_start = hdr["sec4_end"]
        tail_new_end = len(data) - tail_suffix

        true_size_delta = len(data) - len(other)

        growth = {
            "compared_against": args.other,
            "note": (
                "mid/tail '_diverging' ranges are everything AFTER the common prefix/BEFORE the "
                "common suffix -- NOT literally new bytes. Most of this range is old content "
                "shifted/renumbered (see sec2-4 cascade-renumbering in haftlt_format.md). Only "
                "roughly true_size_delta_bytes worth of it is genuinely new; the rest is noise "
                "until the exact insertion point within the range is isolated."
            ),
            "true_size_delta_bytes": true_size_delta,
            "mid_region_prefix_common_bytes": mid_prefix,
            "mid_region_diverging_range": [mid_new_start, mid_new_end],
            "mid_region_diverging_len": mid_new_end - mid_new_start,
            "tail_region_suffix_common_bytes": tail_suffix,
            "tail_region_diverging_range": [tail_new_start, tail_new_end],
            "tail_region_diverging_len": tail_new_end - tail_new_start,
        }

        if mid_new_end > mid_new_start:
            with open(os.path.join(args.output, "mid_region_diverging.bin"), "wb") as f:
                f.write(data[mid_new_start:mid_new_end])
        if tail_new_end > tail_new_start:
            with open(os.path.join(args.output, "tail_region_diverging.bin"), "wb") as f:
                f.write(data[tail_new_start:tail_new_end])

    string_pool_info = {}
    pool_start = find_string_pool(data, hdr["sec4_end"], len(data))
    if pool_start is not None:
        with open(os.path.join(args.output, "street_names.csv"), "w", newline="") as f:
            n_strings, pool_end = parse_string_pool(data, pool_start, csv.writer(f))
        print(f"street_names.csv: {n_strings} cadenas (offset 0x{pool_start:x} - 0x{pool_end:x})", file=sys.stderr)
        string_pool_info = {"start": pool_start, "end": pool_end, "count": n_strings}

        with open(os.path.join(args.output, "linked_records.csv"), "w", newline="") as f:
            linked_info = try_parse_linked_records(data, pool_end, csv.writer(f))
        if linked_info:
            string_pool_info["linked_records"] = linked_info
            print(
                f"linked_records.csv: {linked_info['record_count']} registros de 16 bytes "
                f"tras la tabla de nombres (holgura {linked_info['trailing_slack_bytes']} bytes)",
                file=sys.stderr,
            )
        else:
            os.remove(os.path.join(args.output, "linked_records.csv"))
            print("linked_records.csv: no se encontró un conteo de registros consistente tras la tabla de nombres", file=sys.stderr)
    else:
        print("street_names.csv: no se encontró una tabla de Pascal-strings en este fichero", file=sys.stderr)

    summary = {"source_file": args.haftlt_file, "header": hdr, "growth_zones": growth, "string_pool": string_pool_info}

    with open(os.path.join(args.output, "header.json"), "w") as f:
        json.dump(summary, f, indent=2)

    with open(os.path.join(args.output, "index.csv"), "w", newline="") as f:
        n = parse_index_table(data, 0x200, hdr["sec1_start"], csv.writer(f))
    print(f"index.csv: {n} entradas (6 bytes c/u)", file=sys.stderr)

    with open(os.path.join(args.output, "sec1_flags.csv"), "w", newline="") as f:
        n = parse_sec1(data, hdr["sec1_start"], hdr["sec1_end"], hdr["sec1_record_count"], hdr["const_0x88_sec1_overhead"], csv.writer(f))
    print(f"sec1_flags.csv: {n} flags de 1 byte", file=sys.stderr)

    with open(os.path.join(args.output, "sec2.csv"), "w", newline="") as f:
        n = parse_u16_pairs(data, hdr["sec2_start"], hdr["sec2_end"], csv.writer(f))
    print(f"sec2.csv: {n} registros de 4 bytes ([u16,u16])", file=sys.stderr)

    with open(os.path.join(args.output, "sec3.csv"), "w", newline="") as f:
        n = parse_u32_id_blocks(data, hdr["sec2_end"], hdr["sec3_end"], csv.writer(f))
    print(f"sec3.csv: {n} IDs de 4 bytes (bit31 = flag alternante)", file=sys.stderr)

    with open(os.path.join(args.output, "sec4.csv"), "w", newline="") as f:
        n = parse_u32_id_blocks(data, hdr["sec3_end"], hdr["sec4_end"], csv.writer(f))
    print(f"sec4.csv: {n} IDs de 4 bytes (bit31 = flag alternante)", file=sys.stderr)

    if growth:
        print(f"true file size delta vs --other: {growth['true_size_delta_bytes']} bytes (most of the ranges below are OLD content shifted, not new)", file=sys.stderr)
        print(f"mid_region_diverging.bin: {growth['mid_region_diverging_len']} bytes (offset {hex(growth['mid_region_diverging_range'][0])})", file=sys.stderr)
        print(f"tail_region_diverging.bin: {growth['tail_region_diverging_len']} bytes (offset {hex(growth['tail_region_diverging_range'][0])})", file=sys.stderr)

    print(f"header.json escrito. Salida completa en {args.output}/", file=sys.stderr)


if __name__ == "__main__":
    main()
