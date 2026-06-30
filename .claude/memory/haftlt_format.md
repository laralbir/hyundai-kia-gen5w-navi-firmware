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

### Bloques de datos (12 bytes)

Los offsets del índice apuntan a bloques de **12 bytes**. La estructura exacta **no está completamente decodificada** pero parece ser:

```c
struct DataRecord {
    uint32_t field_a;   // Posiblemente lat µ° O HERE Link ID
    int32_t  field_b;   // Posiblemente lon µ° O atributo
    uint32_t attribs;   // Flags / atributos del registro
};
```

**Observación clave:** En Dinamarca, los offsets consecutivos en el índice para keys secuenciales se distancian exactamente **12 bytes** → confirma tamaño fijo de 12 bytes por bloque.

**Problema no resuelto:** Las coordenadas encontradas en los bloques de datos con valores en rango GPS de Europa NO corresponden a ubicaciones danesas → los datos referenciados no son coordenadas GPS directas, sino probablemente **HERE Road Link IDs** o valores de índice espacial.

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

## Próximos pasos recomendados

1. **Obtener diff entre versiones**: Comparar dos versiones de haftlt de una misma región para aislar qué bytes cambian al añadir/quitar una cámara
2. **Correlación con BD pública de radares**: Usar https://www.dgt.es o similar para correlacionar Link IDs con ubicaciones conocidas
3. **Análisis de hafls**: El archivo pan-EU podría tener estructura más plana que los haftlt

Related: [[haf-format]] · [[project-radar-db]] · [[re-findings]]
