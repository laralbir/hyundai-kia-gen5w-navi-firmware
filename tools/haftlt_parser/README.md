# haftlt_parser — desempaquetar la estructura interna de un `.haftlt`

`parse_haftlt.py` toma un fichero `VIT_EUR_XXX.haftlt` ya extraído del ZIP de mapas
y lo desempaqueta en las estructuras internas confirmadas (ver
[`docs/haftlt_build_diff_260128.md`](../../docs/haftlt_build_diff_260128.md) y
[`.claude/memory/haftlt_format.md`](../../.claude/memory/haftlt_format.md)):
cabecera, tabla índice, Secciones 1–4, la tabla de nombres de calle (texto UTF-8
real) y la tabla de registros de 16 bytes que la sigue — cada una en su propio
CSV/JSON en vez de hex crudo.

**No decodifica coordenadas GPS ni registros de cámara** — ese formato sigue sin
resolverse, y la conexión entre un nombre de calle y su registro de 16 bytes
asociado tampoco está confirmada (una hipótesis obvia ya se probó y quedó
refutada, ver más abajo). Esto es la vista estructurada de lo que sí se conoce,
para poder inspeccionar/filtrar con `pandas`, Excel, `csvkit`, etc. en vez de un
hexdump.

## Uso

```bash
# Estructura estática (índice + secciones 1-4), un solo fichero:
python3 parse_haftlt.py HU/images/navi_eu/haftlt_extracted/260128/VIT_EUR_SPN.haftlt \
  -o HU/images/navi_eu/haftlt_parsed/SPN

# Con --other además localiza las dos zonas candidatas que cambian de tamaño
# entre builds (región media y región cola) y las vuelca a .bin:
python3 parse_haftlt.py \
  HU/images/navi_eu/haftlt_extracted/260128/VIT_EUR_SPN.haftlt \
  --other HU/images/navi_eu/haftlt_extracted/251204/VIT_EUR_SPN.haftlt \
  -o HU/images/navi_eu/haftlt_parsed/SPN
```

## Salida (por país)

| Fichero | Contenido |
|---|---|
| `header.json` | Todos los campos de cabecera decodificados (versión, fechas, offsets/tamaños de sección) + metadatos de la comparación si se usó `--other` |
| `index.csv` | Tabla índice (`0x200`→sec1_start): `idx, file_offset, key` — 6 bytes/entrada. Descartada como almacén de cámaras (creación cero entre builds). |
| `sec1_flags.csv` | Sección 1: `idx, value` — un flag de 1 byte por registro. Descartada como almacén de cámaras. |
| `sec2.csv` | Sección 2: `idx, file_offset, field_a, field_b` — registros de 4 bytes (`u16`+`u16`). |
| `sec3.csv` | Sección 3: `idx, file_offset, raw_hex, id, high_bit` — IDs de 4 bytes con bit 31 alternante. |
| `sec4.csv` | Sección 4: igual formato que sec3, base de IDs distinta. |
| `street_names.csv` | Tabla de nombres de calle/carretera: `idx, file_offset, length, text` — Pascal-strings UTF-8 (`[u8 length][bytes]`, sin terminador). Detección automática por país, sin offsets hardcodeados. |
| `linked_records.csv` | Tabla de 16 bytes justo después de `street_names`: `idx, file_offset, f0..f7` (8×`u16` LE). Conteo verificado aritméticamente contra el tamaño del fichero. Solo se escribe si el conteo encaja (holgura <64 bytes) — si no, no se genera el fichero. |
| `mid_region_diverging.bin` | Solo con `--other`. Bytes desde donde el fichero deja de coincidir con la otra build hasta `sec2_start`. |
| `tail_region_diverging.bin` | Solo con `--other`. Bytes desde `sec4_end` hasta donde vuelve a coincidir el final con la otra build. |

## Sobre `street_names.csv` y `linked_records.csv`

Confirmado en los 4 países probados (AUT/BEL/DNK/SPN): formato de cadena verificado
byte a byte (longitud del prefijo == longitud real del texto), y conteo de
`linked_records` verificado aritméticamente (`count*16 + cabecera` encaja con el
tamaño real del fichero, holgura 0–2 bytes en todos los casos).

**Lo que NO está confirmado:** qué significan los campos `f0`–`f7` de cada
registro, ni cómo (o si) cada registro de 16 bytes se asocia a un nombre de
calle concreto. Se probó la hipótesis obvia — `f0` como offset hacia la cadena
correspondiente — contra las 20.290 cadenas de España: **0 aciertos en 30
registros probados.** No asumas esa conexión sin verificarla tú mismo.

## ⚠️ Lee esto antes de interpretar `*_diverging.bin`

**El tamaño de estos ficheros NO es "bytes nuevos".** Es "todo lo que aparece después
del prefijo común / antes del sufijo común" — la mayoría de ese rango es contenido
antiguo que se desplazó de posición o cuyos IDs se renumeraron en cascada (mismo
fenómeno que hace que las Secciones 2–4 tengan tamaño idéntico entre builds pero
~90% de bytes distintos). `header.json` incluye `true_size_delta_bytes`, que es la
diferencia de tamaño real entre las dos builds — la cantidad real de contenido nuevo
está en algún punto dentro de ese rango mucho más grande, todavía sin aislar con
precisión. Ver la sección "Resultado 3" de `docs/haftlt_build_diff_260128.md` para
el detalle completo de por qué ocurre esto.

## Nota sobre dónde vive la salida

Tanto los `.haftlt` de entrada como la salida de este script deben quedarse bajo
rutas ya cubiertas por `.gitignore` (p. ej. `HU/images/navi_eu/haftlt_extracted/`
y `HU/images/navi_eu/haftlt_parsed/`, ambas fuera del control de versiones). Son
datos derivados del paquete propietario de HERE — el script (código) sí vive en
el repo, sus resultados no.
