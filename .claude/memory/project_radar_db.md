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
| Añadir nuevas cámaras | `haftlt` + `hafls` | ~~Muy difícil~~ **Difícil (bloqueo conceptual resuelto)** | ⚠️ **Actualizado 2026-07-10:** ya no falta saber "qué es la posición" — `linked_records` referencia `LINK_ID` real (confirmado con permutación, p=0.0, ver [`docs/hafr_spatial_index.md`](../../docs/hafr_spatial_index.md)). Falta resolver la implementación: cuál de los 4 campos usar, y cómo insertar un registro nuevo manteniendo consistencia (record_count, referencias de vecino, checksum de cabecera) |
| Bypass integridad (ZIP→MD5→CRC32) | Varios | **Claro** | Ver [[speed-patch-workflow]] |

### Próximos pasos pendientes (en orden de viabilidad)

1. **Exploit gen5w** (ver [[gen5w-exploit]]) → extraer `DecryptToPIPE`+`key.der` del HU físico →
   descifrar `appnavi.tar` → analizar el parser real con Ghidra. **Activo**: otro agente trabaja
   en obtener acceso a Engineering Mode.
2. **`update_fetcher`** (repo gen5w, no requiere HU) → descargar build anterior de mapas para el
   mismo modelo → diff binario entre dos `.haftlt` del mismo país → localización exacta de registros.
3. ~~Correlación con BD pública DGT~~ — **PROBADO, resultado negativo confirmado (2026-06-30)**, ver abajo
4. ~~Tooling HERE open-source~~ — No encontrado; formato HAF es propietario sin RE pública conocida

### ✅ Test decisivo contra dataset público DGT (2026-06-30) — CONFIRMA arquitectura Link-ID

Se descargó el dataset oficial abierto de radares fijos de la DGT (NAP — Punto de Acceso Nacional de
Tráfico, `http://infocar.dgt.es/datex2/dgt/PredefinedLocationsPublication/radares/content.xml`,
formato DATEX2/XML, licencia CC-BY, actualización horaria) → **759 coordenadas reales** de radares en
la España peninsular con precisión de 6 decimales.

Se buscaron esas 759 coordenadas dentro de `VIT_EUR_SPN.haftlt` completo (no solo la región de
cámaras) probando:
- NDS estándar de 32 bits (la fórmula confirmada para boundary boxes de cabecera)
- Microgrados con signo (`v / 1e6`)
- Decigrados ×1e5
- NDS truncado a 24 bits altos

con tolerancia de hasta ±90 m y comprobando que lat/lon aparecieran en palabras adyacentes (offset±4,
±8 bytes). **Resultado: 0 coincidencias en todos los casos.** Esto descarta definitivamente que el
archivo contenga pares de coordenadas WGS84 (en cualquier escala lineal simple) de cámaras reales
recuperables por escaneo de fuerza bruta — confirma con evidencia externa (no solo sospecha estructural)
que el formato usa **HERE Link IDs + offset-a-lo-largo-del-enlace**, resuelto contra el grafo de rutas
(`.hafr`, 921 MB), no coordenadas absolutas embebidas.

**Implicación práctica:** todas las "cámaras españolas" reportadas en sesiones anteriores mediante
escaneo NDS (ver corrección en [[haftlt-format]]) eran ruido — ahora confirmado por partida doble
(colisión con límites de tile + cero correlación con datos reales).

### ❌ Test de `.hafr` (921 MB) — TAMBIÉN negativo, refuta el encoding NDS de 32 bits en general

Se extrajo `VIT_EUR.hafr` completo (sin cifrar, 921 MB = 241,448,302 palabras de 32 bits) y se repitió
el mismo cruce contra las 759 coordenadas DGT con tolerancia ±90 m, usando numpy para procesar el
archivo entero. De **82,347 candidatos de latitud** dentro de tolerancia, **0 tuvieron longitud
adyacente coincidente**.

Como `.hafr` es el grafo de rutas y por definición debe contener geometría real en algún formato, este
resultado niega algo más fundamental que la arquitectura Link-ID de haftlt: **niega que la fórmula NDS
de 32 bits absolutos (`v/2^32 × rango - offset`) sea correcta en ningún archivo de este paquete**, ni
siquiera para nodos de carretera. El "match" de la frontera DK-DE de sesiones anteriores que sustentaba
esta fórmula era un único punto de datos — estadísticamente débil, casi con certeza una coincidencia.

**Conclusión arquitectónica:** el formato NDS real (spec pública de NDS Association) codifica
coordenadas como **deltas relativos a un tile/mesh base** (Morton-coded), no como un entero de 32 bits
absoluto e independiente por punto. Localizar la tabla de tile-bases + esquema de delta es un
prerrequisito para decodificar CUALQUIER coordenada en estos archivos — bloquea tanto a `haftlt` como
a `hafr`, `hafls` y `hafcc`. Detalle completo y vías futuras en [[haftlt-format]].

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

---

## Sesión 2026-07-09 — diff dirigido contra segunda build real (260128)

**Why:** El paso #2 de "próximos pasos" (arriba) — obtener una build de mapas distinta para diff binario — dejó de ser hipotético: apareció una segunda descarga completa (`260128`, datos HERE `2025-11-22`) junto a la `251204` del repo (datos `2025-07-16`). Primer diff dirigido real de la investigación.

**Resultado resumen** (detalle completo en [`docs/haftlt_build_diff_260128.md`](../../docs/haftlt_build_diff_260128.md) y sección nueva de [[haftlt-format]]):

- Los 13 países crecieron en tamaño entre builds (nunca decrecieron) → confirma que sí hay cámaras nuevas codificadas en el fichero en esta ventana de 4 meses.
- Índice y Sección 1: crecimiento cero → descartados definitivamente como almacén de cámaras.
- Secciones 2-4: tamaño constante pero ~90% de bytes distintos → ruido de renumeración de IDs secuenciales, no la fuente real.
- Dos zonas SÍ crecen: región media (`sec1_end`→sec2_start) y región cola (`sec4_end`→EOF) — candidatas reales, aún sin registro completo aislado.
- Corregidos 2 campos de cabecera mal etiquetados como "constantes" en sesiones previas (`0x40`=contador de versión de build, `0x4C`=fecha DATA_VERSION en decimal).

**How to apply:** Al retomar esta investigación, no repetir el escaneo de coordenadas GPS por fuerza bruta (agotado y refutado 2 veces). Continuar desde la localización de zonas de crecimiento — el siguiente paso de mayor valor es conseguir una ventana temporal más corta entre builds (menos cámaras mezcladas = diff más limpio) o repetir el mismo análisis en `.hafls`.

**Estado del mapa de viabilidad (actualización):** "Añadir nuevas cámaras" sigue en **Muy difícil**, pero con el bloqueante parcialmente reducido: ya no es "formato 12-byte + Link IDs no resueltos" en abstracto — ahora hay dos regiones de fichero concretas y acotadas donde buscar, en vez de todo el fichero.

---

## Sesión 2026-07-09 (continuación) — tabla de nombres de calle: primer texto legible de toda la investigación

Comprobación de si `.haftlt` es un contenedor (ZIP/TAR) de otros ficheros: **no lo es** — verificado sin ambigüedad (cero firmas `PK\x03\x04` de ZIP en todo el fichero; los "hits" de firmas que aparecían eran falsos positivos de IDs secuenciales y texto coincidente).

Pero esa comprobación llevó a encontrar, dentro de la región cola, una **tabla de nombres de calle en texto UTF-8 real** — Pascal-strings `[u8 length][texto]`, formato verificado byte a byte, con detector genérico confirmado en los 4 países (AUT 9.849, BEL 7.563→7.746, DNK 23.067, SPN 20.290 nombres). Justo después: una tabla de registros de 16 bytes con conteo verificado aritméticamente (AUT 12.139, BEL 7.875→8.076, DNK 9.081, SPN 23.528).

Bélgica (el país de mayor cambio real, 2.35%) es el único con crecimiento en ambas tablas entre builds — 183 nombres nuevos + 201 registros nuevos, coherente y verificable (nombres de calle belgas genuinos).

**Se probó y refutó** la hipótesis obvia de conexión: `f0` del registro de 16 bytes como offset hacia su nombre de calle — 0/30 aciertos. La relación nombre↔registro sigue abierta, pero por primera vez hay **texto legible con significado geográfico real** para anclar futuras hipótesis, y una tabla de tamaño fijo justo al lado con un patrón de ID+slot-alternante que en el resto del fichero siempre ha señalado datos "vivos" (no de relleno).

**Detalle completo:** [`docs/haftlt_build_diff_260128.md`](../../docs/haftlt_build_diff_260128.md) sección "Resultado 5". Extracción automatizada ya integrada en `tools/haftlt_parser/parse_haftlt.py` (`street_names.csv`, `linked_records.csv`).

**Próximo paso de mayor valor:** usar el caso dirigido de Bélgica (183 nombres + 201 registros nuevos, mucho menos ruido que los ~4 meses completos de otras regiones) para intentar de nuevo la conexión nombre↔registro con otros anclajes (offset relativo distinto, índice directo, o relación inversa).

---

## Sesión 2026-07-09 (continuación 2) — cruce contra SPEED_PATCH.db (LINK_ID) — REFUTADO, con corrección metodológica importante

**Pregunta del usuario:** ¿los nombres de calle o los registros de 16 bytes de `linked_records` tienen relación con `SPEED_PATCH.db` (que usa `LINK_ID` como clave)?

Se probaron los 4 posibles `u32` LE dentro de cada registro de 16 bytes (offsets 0, 4, 8, 12) contra los 7.100.825 `LINK_ID` distintos de `SPEED_PATCH.db` (BEL, 7.875 registros). Primeros resultados parecían prometedores (offset 8: 29,6% de aciertos; offset 4: ratio 10,63x sobre la densidad local) — **ambos resultaron ser artefactos de medir mal la línea base**.

**Corrección metodológica clave:** los `LINK_ID` de HERE **no están distribuidos uniformemente** en su rango (736–153.433.402) — hay tramos con densidad real de hasta 29% y otros con densidad mucho menor. Comparar la tasa de acierto contra la densidad **global** (4,63%) en vez de la densidad **local** (calculada solo dentro del rango real que cubren los candidatos) produce falsas señales de "enriquecimiento" que desaparecen al corregir:

| Offset probado | Rango de candidatos | Tasa observada | Densidad local real | Ratio corregido |
|---|---|---|---|---|
| 0 (f0+f1) | 19.666.176–63.493.294 | 4,94% | 5,23% | 0,94x |
| 4 (f2+f3) | filtrado a valores <153.433.402 | 4,89% | 4,63% | 1,06x |
| 8 (f4+f5) | 921.582–2.283.620 | 29,60% | 29,34% | 1,01x |
| 12 (f6+f7) | 17.823.179–18.534.924 | 7,31% | 7,20% | 1,02x |

Los 4 offsets dan ratio ≈1,0x tras la corrección — **sin relación con `LINK_ID` en ninguna interpretación probada.** Además, offset 4 combina `f2`+`f3`, que ya sabíamos que son referencias a registros vecinos (no un ID real) — los valores "candidatos" resultantes eran una secuencia artificial y regular (131072, 196609, 262146...), confirmando que ni siquiera era una prueba con sentido semántico.

**⚠️ Revisar con esta corrección el hallazgo de la sesión 2026-06-30** ("Test del cruce Link ID — resultado INCONCLUSO", en [[haftlt-format]]): esa prueba comparó 6,46-6,50% contra una densidad **global** de 4,56-4,63% para Secciones 3/4 de España. Dado lo aprendido hoy, es muy probable que ese "1,4x" también sea un artefacto de rango — pendiente de recalcular con densidad local antes de considerarlo evidencia de nada.

**Conclusión:** SPEED_PATCH.db (límites de velocidad por segmento) y la base de datos de cámaras (`haftlt`) parecen ser sistemas de indexación independientes — al menos no comparten `LINK_ID` de forma directa y numéricamente simple en los campos probados hasta ahora.

---

## Sesión 2026-07-09 (continuación 3) — coordenada local escalada por país, probada y REFUTADA con prueba de permutación

**Hipótesis nueva:** dado que `f4`/`f6` de `linked_records` usan casi todo el rango de un `u16` (0-65.535) y son casi únicos/estables por registro, podrían codificar una coordenada **local, escalada linealmente al bounding-box del país** (lat = LAT_MIN + (f4/65535)×rango_lat, lon = LON_MIN + (f6/65535)×rango_lon) — algo nunca probado antes (sesiones previas solo probaron WGS84 absoluto o NDS de rango mundial).

**Método:** se descargó de nuevo el dataset DGT (759 radares reales, ver [[reference_dgt_radar_dataset]]) y se probaron las 56 combinaciones posibles de (campo→lat, campo→lon) de los 8 campos de `linked_records` de España (23.528 registros) con tolerancia ~1,1 km. La mejor combinación bruta (`f4→lat, f6→lon`) dio 52-80 coincidencias (según definición exacta de "coincidencia") — parecía prometedor a primera vista.

**Prueba de significancia (lección aplicada de la refutación de SPEED_PATCH.db):** en vez de comparar contra una densidad teórica, se hizo una **prueba de permutación** — barajar los valores de `f6` entre registros (mismos valores, misma distribución marginal, rompe cualquier relación conjunta real con `f4`) y repetir el conteo de coincidencias 200 veces. Resultado real (52) cayó en el **percentil 90 de la distribución de controles barajados** (p=0,900, media de controles=63,4) — **peor que la mayoría de permutaciones aleatorias**. No hay señal; el resultado bruto de 52-80 solo parecía alto por no compararlo contra un control adecuado.

**Conclusión:** `f4`/`f6` no codifican una coordenada lineal local simple. Sumado a los resultados anteriores de esta sesión (sin conexión a nombres de calle, sin conexión a `LINK_ID`), `linked_records` sigue siendo una tabla completamente estructurada (ID persistente, referencias a vecinos, campos de grupo) pero **sin ningún significado semántico decodificado más allá de su propia topología interna**.

**Lección metodológica reforzada:** cualquier test de "¿este campo es una coordenada/ID real?" en este proyecto debe pasar por una prueba de significancia contra un control aleatorio o baraiado — nunca comparar el conteo bruto de coincidencias contra una intuición o una densidad teórica sin verificar.

---

## 🎯 Sesión 2026-07-10 — hallazgo principal: correlación real a LINK_ID confirmada en `.hafr` (p=0.0)

**Origen:** el usuario planteó si la posición de una cámara podría resolverse vía referencia a `LINK_ID` (segmento con nombre) en vez de coordenadas GPS embebidas — igual que hace el sistema para la guía de voz. `SPEED_PATCH.db` solo cubre un subconjunto de segmentos (con límite especial), así que se investigó `.hafr` (grafo de rutas completo, 921 MB, nunca analizado estructuralmente antes — solo escaneado a fuerza bruta en sesiones previas).

**Resultado:** se localizó en `.hafr` un índice espacial real (bounding boxes que coinciden exactamente con constantes de cabecera compartidas con `.hafls`, ver [`docs/hafr_spatial_index.md`](../../docs/hafr_spatial_index.md)) con un mecanismo de puntero verificado matemáticamente (`m0[i+1]=m0[i]+m1[i]×65536`). Siguiendo ese puntero se llega a registros de 12 bytes que terminan en **una tabla de Pascal-strings con nombres de calle reales** (mismo formato que la ya confirmada en `.haftlt`, con un byte de tipo extra).

**El campo candidato a `LINK_ID`** (tercer campo de cada registro de 12 bytes) se probó a escala (389.413 candidatos de una muestra de 20 MB) contra `SPEED_PATCH.db`: **10,654% de aciertos frente a 4,628% de densidad local — ratio 2,30x, confirmado con prueba de permutación (30 controles aleatorios, ninguno alcanza el resultado real, p=0,0).**

**Es el primer resultado de toda la investigación (4+ sesiones) que sobrevive una prueba de significancia rigurosa con margen abrumador**, a diferencia de todos los intentos anteriores (incluidos los de hoy mismo: cruce directo `linked_records`↔`SPEED_PATCH.db`, coordenada local escalada, Morton en `.hafcc` — todos ≈1,0x tras corregir la línea base).

**Implicación práctica:** confirma con evidencia sólida que la arquitectura real es "posición = `LINK_ID` + nombre de calle", resuelta contra el grafo de rutas — no coordenadas GPS embebidas. El siguiente paso natural es comprobar si `linked_records` de `.haftlt` (que hoy se descartó solo contra el subconjunto de `SPEED_PATCH.db`) correlaciona con el espacio real de `LINK_ID` extraído de `.hafr` — pendiente de hacer.

**How to apply (actualiza la nota de cabecera de este fichero):** al retomar esta investigación, ir directamente a `.hafr` y su tabla de Pascal-strings + campo `LINK_ID` candidato — es la pista más sólida con diferencia. `.hafcc` (mencionado en la nota original de 2026-06-30) queda en segundo plano tras confirmarse hoy que su formato de bloque variable no se llegó a parsear con éxito y no ha dado ninguna señal positiva.

---

## Sesión 2026-07-11 — España localizada en `.hafr` por primera vez; geometría sigue sin resolver (negativo con permutación)

**Why:** el usuario pidió retomar la búsqueda de geometría real para intentar un mapa navegable de verdad (calles trazadas), no solo assets visuales (ver [`docs/rendering_visual_assets.md`](../../docs/rendering_visual_assets.md), sesión previa centrada en iconos/texturas).

**Corrección importante:** repitiendo el recorrido de los `m0` de la sesión 2026-07-10 con ventanas de búsqueda correctamente acotadas (`m1×65536` bytes, no una ventana fija que se solapaba entre secciones vecinas), se descubrió que **la rama de `.hafr` ya explorada (offset `0x308`, 6.776 registros raíz) es casi enteramente Portugal** — 169 de 170 registros muestreados por todo el rango dan contenido portugués (`Rua`, `Estrada Nacional`, códigos `IC`/`IP`/`A`/`N`). Esto refuta que esos 6.776 registros sean una subdivisión geográfica limpia de toda Europa como se interpretó el 2026-07-10 (el único soporte de esa hipótesis eran 2 coincidencias con constantes de cabecera, no una tile real por registro).

**🎯 España localizada:** probando los otros nodos "resumen" hermanos (candidatos con `b3=76.320.000` y `m2` real), se encontró que **el byte de tipo de la tabla Pascal-string varía por rama/país** (no es constante `0x25` global como se asumía): `0x27`=Rumanía (códigos `DN`), **`0x2f`=España** (confirmado: `AP-7`, `A-30`, `"Autovía de Murcia"`, `"Avenida de Juan Carlos I"`, topónimos reales de Murcia/Elche/Javalí Nuevo/Torres de Cotillas), `0x34`=Francia (confirmado: `"Rue François Brichet"`, `"Avenue Aristide Briand"`). Nodo raíz: offset `0x12ec` (4.844), `m0=66.781.193`. **Primera vez en 5+ sesiones que se confirma contenido español real dentro de `.hafr`.**

**Geometría: negativo, con prueba de permutación.** Con la rama de España acotada a solo 393.216 bytes, se probaron 4 escalas de coordenadas (`/1e5`, `/1e6`, `/1e7`, y el encoding NDS real `90/2^30`) contra el bounding-box de Murcia. El encoding NDS dio 6 coincidencias aparentemente coherentes geográficamente — pero la prueba de permutación (40 ventanas aleatorias del mismo tamaño en todo el fichero) dio **13/40 controles ≥ 6, p≈0,325, no significativo**. Ruido, no señal — mismo patrón de falso positivo ya catalogado varias veces.

**Conclusión:** avance real (localizar España, nunca logrado antes) pero el bloqueo de fondo persiste — ni siquiera acotando la búsqueda a la región exacta correcta aparece una codificación de coordenadas que sobreviva significancia. Refuerza que la geometría real probablemente vive en `.hafp` (sin resolver, ver [`docs/hafp_geometry_search.md`](../../docs/hafp_geometry_search.md)) o requiere el parser real cifrado (`appnavi`).

Detalle completo: [`docs/hafr_spatial_index.md`](../../docs/hafr_spatial_index.md) sección "España localizada por primera vez".

### Continuación misma sesión — `.hafp03` (partición España), pista de cabecera decodificada y descartada

Aplicando la misma técnica (byte de tipo Pascal-string por país) a `.hafp03`: confirma `type=0x2f` para nombres españoles (consistente con `.hafr` — mismo código en dos ficheros HAF distintos) y descubre `type=0xaf` (`0x2f|0x80`) para la transcripción fonética que sigue a cada nombre. 12.696 nombres reales localizados en 20 MB (incluye El Hierro/Canarias).

La pista más prometedora que había dejado la sesión de `.hafp` (patrón de cabecera regular con "longitud plausible −16,7772°") se decodificó por completo: son **dos contadores entrelazados** (patrón `A,B,B,A`, no monótono) — la coincidencia con una longitud real era casualidad de un único valor de muestra, no un patrón geográfico. Prueba sistemática (306 combinaciones de campos × 4 escalas, 5.633 registros) contra El Hierro real: **0 combinaciones con señal**. Descartada.

**Estado tras esta sesión:** tanto `.hafr` como `.hafp03` dan nombre+fonética/tipo con byte de país consistente (`0x2f`=España en ambos), pero **ninguno de los dos da coordenadas** pese a búsquedas sistemáticas con prueba de significancia. El bloqueo de "encontrar geometría por inspección externa" se mantiene tras esta sesión — siguiente candidato más prometedor sin probar: `.hafgsi` (274 MB, índice espacial global, cabecera con patrón de tiles ya visto pero sin seguir hasta datos útiles).
