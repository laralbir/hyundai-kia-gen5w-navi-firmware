---
name: project-radar-db
description: "Análisis de la base de datos de radares/cámaras en el firmware del Kia Rio 2022 EU — archivos clave, formato, y plan de modificación"
metadata: 
  node_type: memory
  type: project
  originSessionId: 4fdd3d22-4481-42d4-b6d4-82d1d973bc3c
---

## Base de datos de radares — análisis completado (2026-06-30)

**Why:** Objetivo de modificar la BD de cámaras de velocidad del sistema de navegación HERE Maps para instalar datos actualizados sin afectar el resto del firmware.

**How to apply:** Al retomar este trabajo, ir directamente al análisis del formato binario del `hafcc` y la calibración de coordenadas.

---

### Archivos clave dentro del ZIP de mapas

`HU/images/navi_eu/S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip` (17.9 GB, MD5: `b00d66e5536ba37297bd6c3e1b7e0993`)

| Archivo (dentro del ZIP) | Tamaño | Formato | Rol |
|---|---|---|---|
| `Data/Nation/EUR/MAP/VIT_EUR.hafcc` | 312 KB | HAF binario propietario | **65.001 registros de cámaras/radares** ← OBJETIVO PRINCIPAL |
| `Data/Nation/EUR/MAP/SPEED_PATCH.db` | 153 MB | **SQLite** | Correcciones de límites de velocidad por segmento (10.3M filas) |
| `Data/Nation/EUR/MAP/VIT_EUR.hafbc` | 3.6 KB | Texto plano | Límites de velocidad por país (motorway/rural/urban) |
| `Data/Nation/EUR/MAP/VIT_EUR_ADAS.hafaip` (×4) | ~2.8 GB total | HAF binario | ADAS horizon — geometría + velocidades, posible refuerzo de avisos |
| `Data/Nation/EUR/SEARCH/COMMON/POI/EU_POIFRAME.mpd` | 1.3 GB | MPD binario | POI database (cámaras también pueden estar aquí como POI) |

### Estructura `SPEED_PATCH.db`
```sql
CREATE TABLE SPEED_PATCH (
    LINK_ID INT64, DIR INT, SP_LIMIT INT, VEHICLE_TYPE INT,
    PRIMARY KEY(LINK_ID, DIR, VEHICLE_TYPE)
) without rowid;
-- VERSION_INFO: FORMAT=1.0.1.0, DATA=2025072316
-- 10,353,101 filas
-- VEHICLE_TYPE values: 0, 7, 15, 23, 31, 55, 56, 63, 64, 72, 88...  (bitmask)
-- SP_LIMIT values: 5..130 km/h (o mph)
-- DIR: 0, 1, 2
```

### Estructura `VIT_EUR.hafcc` (CÁMARAS)
```
Header:
  [0x00] FORMAT_VERSION_01.00.02
  [0x40] DATA_VERSION_2025.02.25.12
  [0x80] u32 = 65001  ← número de registros
  [0x58] u32 = 12849  ← desconocido (¿índice/offset?)
  [0xAC] u32 = 2      ← desconocido (¿versión/tipo?)

Datos: a partir de 0x200 aprox.
  - Registros de ~36-40 bytes (longitud a confirmar)
  - Sin cifrado, codificación binaria propietaria HERE
  - Cada registro contiene: pares de coordenadas (lon/lat) + tipo + dirección + (¿velocidad limite?)
  - El encoding de coordenadas es DESCONOCIDO — necesita calibración
```

**Valores de muestra del primer record visible (offset 0x240+):**
- count/sub-entries: 3
- Pair 1: (3,080,070 / 18,046,915)
- Pair 2: (3,087,462 / 18,050,737)  ← diferencia ~7392 / ~3822 (segmento de carretera corto)
- Link-like ID: 4,000,016

### Sistema de integridad (dos niveles)
1. **`Rio_MY22_EU.ver`** — CRC32 del ZIP: `1273619936`, size: `17889556253`
   - También checksum del txt de MD5: `25235652`, size: `73`
2. **`EUR.18.49.56.023.631.5_md5.txt`** — MD5 del ZIP: `b00d66e5536ba37297bd6c3e1b7e0993`

Para instalar cambios: reempaquetar ZIP → recalcular MD5 → recalcular CRC32 en `.ver`.
**Incógnita:** si `appnavi` verifica checksum interno del `.hafcc` al cargarlo.

---

## Estado tras análisis profundo (sesión 2026-06-30)

### Hallazgo clave: hafcc NO son cámaras GPS

`VIT_EUR.hafcc` — La hipótesis inicial era que los 65,001 registros eran cámaras.
**Incorrecto.** El encoding de coordenadas no corresponde a WGS84 para Europa.
Probable uso: configuración de zonas urbanas / áreas de ciudad.
Ver: [[haftlt-format]] para el análisis completo del hafcc.

### Archivos de cámara confirmados: haftlt + hafls

La BD de radares está distribuida entre:
1. `VIT_EUR_*.haftlt` (por país) — Traffic Local Threats, referenciados por HERE Link IDs
2. `VIT_EUR.hafls` (80 MB) — Safety layer pan-EU

**Problema:** Ambos formatos usan HERE Road Link IDs como clave, no GPS directo.
El encoding de coordenadas en los bloques de 12 bytes NO es WGS84 microdegrees.
La app `appnavi.tar` está cifrada → no podemos leer el código para decodificar.

### Formato haftlt confirmado

Ver documento completo: [[haftlt-format]]

**Resumen de estructura:**
```
[Header 0x00-0x1FF]     → offsets y counts de secciones
[Índice 0x200-sec1]     → entradas 6 bytes: [u32 file_offset][u16 key]
[Bloques 12 bytes]      → datos referenciados por el índice
[Sección 1]             → array de 1-byte flags por record_count
[Secciones 2-4]         → índices espaciales adicionales
```

### Mapa de viabilidad final

| Objetivo | Archivo | Dificultad | Bloqueante |
|---|---|---|---|
| Cambiar límites velocidad por segmento | `SPEED_PATCH.db` | **Trivial** | Ninguno — SQLite listo |
| Cambiar límites que disparan alertas | `SPEED_PATCH.db` | **Trivial** | Solo si la app usa SP_LIMIT para alertas |
| Modificar/eliminar cámaras existentes | `haftlt` | **Difícil** | Key codes HERE desconocidos |
| Añadir nuevas cámaras | `haftlt` + `hafls` | **Muy difícil** | Formato 12-byte + Link IDs no resueltos |
| Bypass integridad (ZIP→MD5→CRC32) | Varios | **Claro** | Ver [[speed-patch-workflow]] |

### Próximos pasos pendientes (en orden de viabilidad)

1. **Ejecutar workflow SPEED_PATCH.db** — Paso a paso documentado en [[speed-patch-workflow]]
2. **Diff entre versiones haftlt** — Conseguir versión anterior de mapas HERE para el mismo país y hacer diff binario: los bytes cambiados = posición de cámara nueva/quitada
3. **Correlación con BD pública DGT** — Buscar Link IDs de radares conocidos en España usando coordenadas de https://www.dgt.es/radares/ y buscar esos Link IDs en el haftlt de SPN
4. **Tooling HERE open-source** — Buscar proyectos que procesen mapas HERE NDS/HAF format

### Archivos scratchpad extraídos (efímeros, re-extraer en cada sesión)

```bash
# Extraer de nuevo si el scratchpad se borró:
SCRATCHPAD="/private/tmp/claude-501/-Users-carlos-Projects-Rio-MY22-EU/4fdd3d22-4481-42d4-b6d4-82d1d973bc3c/scratchpad"
ZIP="/Users/carlos/Projects/Rio_MY22_EU/HU/images/navi_eu/S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip"

unzip -p "$ZIP" "Data/Nation/EUR/MAP/SPEED_PATCH.db" > "$SCRATCHPAD/SPEED_PATCH.db"
unzip -p "$ZIP" "Data/Nation/EUR/MAP/VIT_EUR.hafcc"  > "$SCRATCHPAD/VIT_EUR.hafcc"
unzip -p "$ZIP" "Data/Nation/EUR/MAP/VIT_EUR.hafls"  > "$SCRATCHPAD/VIT_EUR.hafls"
unzip -p "$ZIP" "Data/Nation/EUR/MAP/HAFTLT/VIT_EUR_SPN.haftlt" > "$SCRATCHPAD/VIT_EUR_SPN.haftlt"
unzip -p "$ZIP" "Data/Nation/EUR/MAP/HAFTLT/VIT_EUR_BEL.haftlt" > "$SCRATCHPAD/VIT_EUR_BEL.haftlt"
unzip -p "$ZIP" "Data/Nation/EUR/MAP/HAFTLT/VIT_EUR_DNK.haftlt" > "$SCRATCHPAD/VIT_EUR_DNK.haftlt"
```
