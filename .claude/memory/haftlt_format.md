---
name: haftlt-format
description: "Análisis completo del formato binario VIT_EUR_*.haftlt (HAF Traffic Local Threats) — estructura de cabecera, índice, bloques de datos y comparativa entre países"
metadata: 
  node_type: memory
  type: project
  originSessionId: 4fdd3d22-4481-42d4-b6d4-82d1d973bc3c
---

## VIT_EUR_*.haftlt — HAF Traffic Local Threats

Archivos por país dentro del ZIP de mapas HERE en `Data/Nation/EUR/MAP/HAFTLT/`.
Son los archivos que contienen los datos de **cámaras de velocidad fijas** y control de tramo.
Formato propietario HERE, versión `FORMAT_VERSION_01.04.02`.

### Archivos disponibles y tamaños (descomprimidos)

| Archivo | Tamaño | Países |
|---------|--------|--------|
| VIT_EUR_DEU.haftlt | 10.94 MB | Alemania |
| VIT_EUR_ITA.haftlt | 11.25 MB | Italia |
| VIT_EUR_FRA.haftlt | 9.46 MB | Francia |
| VIT_EUR_GBR.haftlt | 9.47 MB | Reino Unido |
| VIT_EUR_SPN.haftlt | 5.49 MB | España |
| VIT_EUR_CZE.haftlt | 5.71 MB | Chequia |
| VIT_EUR_CHE.haftlt | 4.11 MB | Suiza |
| VIT_EUR_NOR.haftlt | 3.94 MB | Noruega |
| VIT_EUR_SWE.haftlt | 3.75 MB | Suecia |
| VIT_EUR_AUT.haftlt | 2.71 MB | Austria |
| VIT_EUR_DNK.haftlt | 2.18 MB | Dinamarca |
| VIT_EUR_BEL.haftlt | 1.82 MB | Bélgica |
| VIT_EUR_NLD.haftlt | 1.93 MB | Países Bajos |

---

## Estructura del archivo

### Cabecera (0x00 – 0x1FF)

```
[0x00 – 0x1F]  FORMAT_VERSION_01.04.02\0...   (32 bytes, null-padded)
[0x20 – 0x3F]  (ceros o datos de plataforma)
[0x40 – 0x5F]  DATA_VERSION_YYYY.MM.DD.HH\0   (32 bytes, null-padded)
               DATA_VERSION siempre truncada — contaminada con bytes de 0x4C-0x5F
```

**Campos clave del header (offsets absolutos en el archivo):**

| Offset | Campo | España | Bélgica | Dinamarca | Notas |
|--------|-------|--------|---------|-----------|-------|
| 0x40 | format_tag | 0x00031706 | 0x00031706 | 0x00031706 | **Constante** en todos los países |
| 0x44 | flags | 1 / 1 / 1 | — | — | — |
| 0x4C | timestamp | 0x78B42395 | 0x78B42395 | 0x78B42395 | **Constante** — timestamp compilación HERE |
| 0x80 | crc_or_hash | 288,090,382 | 17,730,424 | 152,140,046 | Varía por país (¿CRC32?) |
| 0x84 | const_34 | **34** | **34** | **34** | **Constante** en todos los países |
| 0x88 | const_20 | **20** | **20** | **20** | **Constante** — overhead de la sección 1 |
| 0x8C | sec1_record_count | 1,043 | 9,203 | 3,488 | Número de registros de 1 byte en sección 1 |
| 0x90 | sec1_size | 1,063 | 9,223 | 3,508 | = 0x8C + 0x88 (siempre) |
| 0x94 | sec1_start | 80,452 | 44,514 | 50,855 | Offset inicio sección 1 en el archivo |
| 0x98 | sec1_end | 81,515 | 53,737 | 54,363 | = 0x94 + 0x90 (siempre) |
| 0x9C | sec2_start | 2,361,594 | 779,792 | 824,438 | Offset inicio sección 2 |
| 0xA0 | sec2_end | 2,443,109 | 833,529 | 878,801 | sec2_size = sec2_end - sec2_start |
| 0xA4 | sec3_size | 246,368 | 56,671 | 193,645 | Tamaño sección 3 en bytes |
| 0xA8 | sec3_end | 2,689,477 | 890,200 | 1,072,446 | = sec2_end + sec3_size (siempre) |
| 0xAC | sec4_size | 188,232 | 63,008 | 72,656 | Tamaño sección 4 en bytes |

**Invariantes confirmadas:**
- `sec1_size = sec1_record_count + 20`
- `sec1_end = sec1_start + sec1_size`
- `sec3_end = sec2_end + sec3_size`
- `sec4_end = sec3_end + sec4_size` (inferido)

---

### Tabla índice (0x200 – sec1_start)

La región desde offset `0x200` hasta `sec1_start` contiene una tabla de índice plana con registros de **6 bytes** cada uno:

```c
struct IndexEntry {
    uint32_t file_offset;  // Offset absoluto en el archivo donde está el bloque de datos
    uint16_t key;          // Tipo/categoría HERE (0-65535)
};
```

**Estadísticas por país:**

| País | Entradas índice | Rango de keys |
|------|----------------|---------------|
| España | ~13,300 | 0 – 65535 |
| Bélgica | ~7,330 | — |
| Dinamarca | 8,390 | 0 – 65535 |

**Observaciones del índice:**
- `key=0xFFFF` (65535) aparece repetidamente → marcador especial / default
- `key=0x03E8` (1000) apunta a offset 0 (cabecera del archivo) → entrada nula/referencia
- Los offsets apuntan a bloques de datos de **12 bytes** en cualquier parte del archivo
- Algunos offsets apuntan al propio header (auto-referencia) para valores de configuración

**Ejemplo de lectura Python:**
```python
import struct

def read_index(data, start=0x200, end=None):
    entries = []
    pos = start
    while pos + 6 <= (end or len(data)):
        offset = struct.unpack_from('<I', data, pos)[0]
        key    = struct.unpack_from('<H', data, pos+4)[0]
        entries.append((key, offset))
        pos += 6
    return entries
```

---

### ✅ ENCODING DE COORDENADAS CONFIRMADO: HERE NDS

```python
def nds_to_lat(v_u32): return (v_u32 / 2**32) * 180 - 90
def nds_to_lon(v_u32): return (v_u32 / 2**32) * 360 - 180
def lat_to_nds(lat):   return int((lat + 90) / 180 * 2**32) & 0xFFFFFFFF
def lon_to_nds(lon):   return int((lon + 180) / 360 * 2**32) & 0xFFFFFFFF
```

Verificado con datos reales daneses: valor 3,439,329,283 → lat=54.14°N (frontera DK-DE) ✓  
**Tile boundary:** lon=±1.40625°E = 2^24/2^32×360 = 360/256. Aparece frecuentemente como falso positivo (límite de tile NDS, no cámara).

---

### ✅ REGISTRO DE CÁMARA: estructura de 12 bytes CONFIRMADA

```c
struct CameraRecord {
    uint32_t nds_lat;    // latitud HERE NDS (lat = v/2^32 * 180 - 90)
    uint32_t nds_lon;    // longitud HERE NDS (lon = v/2^32 * 360 - 180)
    uint32_t attribs;    // [b0=speed_limit_kmh?][b1=camera_type?][b2=flags?][b3=flags?]
};
```

Ejemplo SPN, cámara en 38.34°N -4.22°E (Córdoba):
```
raw: 85 d6 85 b6  90 eb ff 7c  50 de 00 f0
nds_lat = 0xB685D685 → 38.336°N ✓
nds_lon = 0x7CFFEB90 → -4.219°E ✓
attribs = [b0=0x50=80, b1=0xDE, b2=0x00, b3=0xF0]
```

**attribs pendiente decode:**
- `b0` podría ser velocidad km/h (b0=80 en Córdoba, b0=30 en Mallorca coinciden con límites reales)
- `b1` frecuentes: 0xDE=222, 0xDD=221, 0xEB=235 (posibles tipo-HERE de cámara)
- El índice externo (tabla 0x200→sec1_start) **NO** apunta a estos registros GPS

---

### Bloques de datos (12 bytes) — índice externo

Los offsets del índice en 0x200–sec1_start apuntan a bloques de 12 bytes. Éstos son estructuras de rango / referencia, NO registros de cámara GPS:

```c
struct DataRecord {
    uint16_t range_start_a;  uint16_t range_end_a;   // patrón A, A+1
    uint16_t range_start_b;  uint16_t range_end_b;   // patrón B, B+delta
    uint16_t zero_a;         uint16_t zero_b;         // siempre 0
};
```

Pattern `(A, B, 0, A+1, B+delta, 0)` como u16 → apunta a rangos en secciones secundarias.  
En Dinamarca, offsets consecutivos separados exactamente 12B → tamaño fijo confirmado.

---

### Secciones secundarias

**Sección 1** (`sec1_start`, `sec1_size` bytes):
- 20 bytes de overhead al inicio
- Seguido de `sec1_record_count` bytes de 1 byte cada uno
- Distribución típica (España): 0→401, 1→53, 2→23, 3→20, 4→37... (0 es el valor más común)
- **Posible uso:** Flags por tipo de road attribute (0=sin cámara, 1-7=tipo de cámara)

**Sección 2** (`sec2_start`, tamaño = `sec2_end - sec2_start`):
- Registros de 4 bytes con patrón de pares `[u16 idx][u16 ref]`
- Parecen ser pares de referencia a tiles o Link IDs
- Ejemplo DNK: `[0x000A, 0x12E8], [0x0000, 0x12E8], [0x0100, 0x12E8], [0x0180, 0x1AE8]`

**Sección 3** (`sec2_end`, `sec3_size` bytes):
- Bloques con IDs incrementales y bit 31 alternante (0 y 0x80000000)
- Patrón en DNK: `(X, X+2^31)` donde X incrementa secuencialmente
- Probable uso: índice de segmentos bidireccionales

**Sección 4** (`sec3_end`, `sec4_size` bytes):
- Patrón similar a sección 3 pero con diferente base de IDs

---

## ✅ REGIÓN PRINCIPAL DE CÁMARAS (sec4_end → EOF) — HALLAZGO CLAVE

**Localización SPN:**
```
sec4_end = 2,689,477 + 188,232 = 2,877,709 = 0x2BE90D
EOF      = 5,755,556 bytes = 0x57D2A4
Tamaño:    2,877,847 bytes (≈50% del archivo total)
```

### Contenido confirmado

- **138 registros de cámara española** localizados (lat 34.5-44.5°N, lon -10.5 a 5.5°E)
- Los GPS reales están aquí con stride **NO constante** (los registros no son un array plano)
- Inicio de región: bounding boxes de tiles del índice espacial (coordenadas pan-europeas)

### Sub-descriptores de tipos de cámara (header 0xC4–0xFF)

```
[0xC4] tipo=0x0005  cnt=12   → tipo 5,  12 cámaras
[0xD0] tipo=0x000B  cnt=60   → tipo 11, 60 cámaras
[0xDC] tipo=0x000D  cnt=72   → tipo 13, 72 cámaras
[0xE8] tipo=0x000F  cnt=168  → tipo 15, 168 cámaras (dominante)
[0xF4] tipo=0x0011  cnt=144  → tipo 17, 144 cámaras
                    TOTAL  = 456 cámaras en España
```

Tipos: números IMPARES 5, 11, 13, 15, 17. Significado exacto pendiente (posibles: fija/tramo/semáforo/radar_móvil/ADAS).

### Cámaras españolas confirmadas (muestra)

| Latitud | Longitud | Zona | attribs b0 |
|---------|----------|------|------------|
| 38.34°N | -4.22°E | Córdoba / La Mancha | 0x50=80 km/h |
| 41.15°N | 2.81°E | Costa Daurada | 0x3A=58 |
| 37.97°N | -1.41°E | Murcia | 0x71=113 |
| 39.39°N | 2.70°E | Mallorca | 0x1E=30 km/h |
| 40.79°N | -1.31°E | Zaragoza | 0x57=87 |
| 41.48°N | 0.00°E | Lleida | 0x20=32 |
| 40.08°N | -7.03°E | Cáceres | 0xC8=200 |
| 43.59°N | -5.62°E | Asturias | 0x35=53 |

### Código Python para encontrar cámaras

```python
def camera_region_start(data):
    sec3_end  = struct.unpack_from('<I', data, 0xA8)[0]
    sec4_size = struct.unpack_from('<I', data, 0xAC)[0]
    return sec3_end + sec4_size

def find_cameras_in_bbox(data, lat_min, lat_max, lon_min, lon_max):
    start = camera_region_start(data)
    hits = []
    for off in range(start, len(data) - 12, 4):
        a, b, c = struct.unpack_from('<III', data, off)
        lat = (a / 2**32) * 180 - 90
        lon = (b / 2**32) * 360 - 180
        if lat_min < lat < lat_max and lon_min < lon < lon_max:
            hits.append((off, lat, lon, c))
    return hits

# España: lat_min=34.5, lat_max=44.5, lon_min=-10.5, lon_max=5.5
```

---

## Relación con otros archivos de cámara

| Archivo | Tamaño | Función | Estado análisis |
|---------|--------|---------|----------------|
| `VIT_EUR.hafls` | 80 MB | Safety layer pan-EU | IFF data, estructura similar a haftlt |
| `VIT_EUR.hafcc` | 312 KB | Configuración país/ciudad | 65,001 records, no son cámaras GPS |
| `VIT_EUR.hafbc` | 3.6 KB | Límites por país | **Texto plano** — completamente legible |
| `SPEED_PATCH.db` | 153 MB | Límites por Link ID | **SQLite** — completamente accesible |
| `HAFTLT/*.haftlt` | 1.8-11 MB | Cámaras por país | Binario propietario — parcialmente analizado |

## Archivos de audio de alerta (confirman qué archivos usa el sistema)

En `Data/Nation/EUR/RES/SOUND/`:
- `CT000009_HIGH.wav` — CT = **Camera Trap**, progresión cuando se acerca
- `CT000009_MID.wav`
- `CT000009_LOW.wav`

Estos confirman que el sistema SABE diferenciar proximidad a la cámara.

---

## Flujo de integridad para modificar

Para instalar cualquier cambio dentro del ZIP:

```
1. Extraer archivo del ZIP
2. Modificar binario
3. Reempaquetar ZIP (conservando compresión original)
4. Recalcular MD5 → actualizar EUR.18.49.56.023.631.5_md5.txt
5. Recalcular CRC32 signed int32 → actualizar Rio_MY22_EU.ver
   - Entrada ZIP:  checksum=1273619936, size=17889556253
   - Entrada MD5:  checksum=25235652,   size=73
```

**Incógnita abierta:** ¿Verifica appnavi checksums internos de los haftlt al cargarlos?

---

## Qué falta por resolver

1. **Estructura exacta de tiles en región de cámaras** — entender cómo están organizados los tiles y si hay más cámaras fuera de los 138 encontrados
2. **Decodificación de `attribs`** — b0 parece ser velocidad (30/80 coinciden) pero no todos los valores son velocidades estándar. b1 podría ser tipo HERE de cámara
3. **Relación índice → cámaras GPS** — las ~13,300 entradas del índice externo NO apuntan a los registros GPS (todos los offsets inspeccionados apuntan a estructuras de rango). Ruta desconocida
4. **Tipos 5, 11, 13, 15, 17** — qué cámara corresponde a cada tipo

## Para modificar: añadir/quitar cámara

1. Crear registro de 12B: `struct.pack('<III', lat_to_nds(lat), lon_to_nds(lon), attribs)`
2. Insertar en la región GPS (sec4_end → EOF), posición correcta dentro del tile correspondiente
3. Actualizar sub-descriptores de tipo en header (0xC4-0xFF): incrementar `cnt` del tipo correspondiente
4. ¿Actualizar CRC/hash en 0x80? Incógnita — puede que appnavi no lo verifique
5. Reempaquetar ZIP → recalcular MD5 → actualizar CRC32 signed en .ver

Related: [[haf-format]] · [[project-radar-db]] · [[re-findings]]
