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

### ❌ ENCODING "NDS de 32 bits absoluto" — REFUTADO (2026-06-30)

```python
def nds_to_lat(v_u32): return (v_u32 / 2**32) * 180 - 90
def nds_to_lon(v_u32): return (v_u32 / 2**32) * 360 - 180
```

Esta fórmula se dio por "confirmada" en una sesión anterior basándose en **un único punto de datos**:
un valor en datos daneses que decodificaba a 54.14°N, cerca de la frontera DK-DE. Con un solo punto,
esa coincidencia es estadísticamente débil (cualquier valor de 32 bits tiene ~1/180 de probabilidad de
caer en un rango de latitud plausible por puro azar).

**Test decisivo de refutación:** se buscaron las 759 coordenadas reales de radares DGT (ver
[[project_radar_db]]) con esta fórmula dentro de `VIT_EUR.hafr` — el **grafo de rutas pan-europeo
completo (921 MB, 241M palabras de 32 bits)**, que por definición DEBE contener geometría real de
carreteras en algún sitio. Resultado: de 82,347 candidatos de latitud dentro de tolerancia (~90 m),
**0 tuvieron una longitud adyacente coincidente**. Mismo resultado negativo que en `haftlt` (ver
corrección más abajo).

**Conclusión:** el formato HERE NDS real (especificación pública de NDS Association) usa codificación
**relativa por tile/mesh**: cada tile tiene una coordenada base (Morton-coded) y los puntos dentro de
él se almacenan como **deltas pequeños** (8/16/24 bits) respecto a esa base — NO como un valor lineal
absoluto de 32 bits por punto. Esto explica por qué un escaneo de fuerza bruta de 32 bits nunca
encuentra coincidencias reales: la información de posición está fragmentada entre una referencia de
tile (en otra parte de la estructura) y un offset local pequeño. **Pendiente:** localizar la tabla de
tiles/mesh-base y el esquema de delta antes de poder decodificar coordenadas reales en cualquier
archivo HERE de este paquete (haftlt, hafr, hafls, hafcc).

**Lo único que sigue siendo válido:** el límite de tile en `lon=±1.40625°E` (`=2^24/2^32×360`) seguía
apareciendo como patrón estructural recurrente — consistente con un sistema de tiles de **256 columnas
en el nivel raíz** (2^8), lo cual sí encaja con la jerarquía real de NDS (niveles de zoom Morton). Esto
sugiere que el "scale" de 32 bits no está mal en general — está mal asumir que un **registro individual**
de carretera/cámara usa los 32 bits completos como coordenada absoluta independiente del tile.

---

### ❌ "REGISTRO DE CÁMARA de 12 bytes" — REFUTADO, dependía del encoding refutado arriba

```c
// Hipótesis anterior, NO confirmada — descartar:
struct CameraRecord {
    uint32_t nds_lat;
    uint32_t nds_lon;
    uint32_t attribs;
};
```

El "ejemplo confirmado" de Córdoba (38.34°N -4.22°E) que sustentaba esta estructura usaba la misma
fórmula NDS de 32 bits absoluto que quedó refutada arriba por el test masivo contra `.hafr` y contra
las 759 coordenadas reales de radares DGT (0 coincidencias). Era, con alta probabilidad, otro falso
positivo de coincidencia aleatoria — coherente con el patrón ya visto en la sección de corrección de
"138 cámaras" más abajo. **No dar por buena ninguna coordenada de cámara obtenida por este método.**

**attribs pendiente decode (nota histórica, igualmente sin confirmar):**
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

## ⚠️ REGIÓN SIN ETIQUETAR (sec4_end → EOF) — REEVALUADO, MAYORÍA FALSOS POSITIVOS

**Localización SPN:**
```
sec4_end = 2,689,477 + 188,232 = 2,877,709 = 0x2BE90D
EOF      = 5,755,556 bytes = 0x57D2A4
Tamaño:    2,877,847 bytes (≈50% del archivo total)
```

### ❌ CORRECCIÓN IMPORTANTE (control de calidad posterior)

Un hallazgo anterior en esta misma sesión afirmaba "138 cámaras españolas confirmadas" mediante escaneo
stride-4 de toda la región buscando pares NDS válidos dentro del bounding-box de España. **Ese resultado
era mayoritariamente ruido.** Verificación posterior:

1. **Filtro de límites de tile NDS**: los límites de tile ocurren en todo múltiplo de `1.40625°`
   (= 2²⁴/2³² × 360) tanto en lat como en lon. Re-escaneando los 58 candidatos brutos en bbox España:
   - 14 caían en límite de tile en AMBOS ejes (basura total del índice espacial)
   - 28 caían en límite de tile solo en longitud
   - 6 caían en límite de tile solo en latitud
   - **Solo 10/58 sobrevivieron el filtro**
2. De esos 10 supervivientes, al menos 2 comparten coordenada exacta (41.3177°N -7.8789°E) con
   `attribs` que decodifican como **texto ASCII legible** (`" ed "`, `"erA "`) — es decir, son colisiones
   con una cadena de texto en otra parte del archivo, no datos de cámara.
3. Se probó también usar el sentinel `XX_FFFFFF` (ver abajo) como ancla — de 33 candidatos en bbox España
   ampliado (incl. Canarias), el **100% cayó en límite de tile** (falsos positivos puros).

**Conclusión: la hipótesis "registro de cámara = 12B [NDS_lat][NDS_lon][attribs] disperso en la región
sin etiquetar, localizable por escaneo de coordenadas" NO está validada.** El espacio de valores NDS de
32 bits es tan grande que un escaneo de fuerza bruta sobre ~720K posiciones produce decenas de coincidencias
aleatorias dentro de cualquier bounding-box razonable, agravado porque la región está LLENA de quasi-NDS
(límites de tile, IDs de enlace que caen por azar en rango, fragmentos de texto/flags). Cualquier coordenada
"confirmada" en sesiones anteriores debe tratarse como **no verificada** hasta correlación cruzada con una
fuente externa (BD pública DGT) o hasta entender la estructura real de la región.

### Lo que SÍ se mantiene firme

- **Encoding NDS confirmado en general** (ver sección anterior) — válido para coordenadas de tile en
  cabeceras y para los pocos valores verificados contra ubicaciones reales conocidas (frontera DK-DE)
- **Sentinel `XX_FFFFFF`** (high byte variable, low 3 bytes = 0xFFFFFF) aparece 14,026 veces en la región
  de SPN — es extremadamente común, lo que lo invalida como marcador específico de cámara; probablemente
  es parte de la codificación general de tiles/límites del índice espacial, no un delimitador de registro
- **Sub-descriptores de tipos en header (0xC4–0xFF)** — estructura sigue siendo válida (ver abajo), pero
  su relación con "cantidad de cámaras" es dudosa: en Bélgica los `cnt` llegan a 7,296 y 7,260 para un país
  pequeño, lo que sugiere que cuentan **asociaciones cámara↔enlace de carretera**, no instalaciones físicas
- **Campo header 0x80** = `(N << 24) | camera_region_start` donde N varía por país (17 en SPN, 9 en DNK,
  1 en BEL) — fórmula confirmada aritméticamente, pero el significado de N (¿nº de tiles?) no está probado

### Sub-descriptores de tipos (header 0xC4–0xFF) — estructura, no recuento de cámaras

```
SPN: [0xC4] tipo=5  cnt=12   [0xD0] tipo=11 cnt=60   [0xDC] tipo=13 cnt=72
     [0xE8] tipo=15 cnt=168  [0xF4] tipo=17 cnt=144  (total asociaciones=456)
BEL: [0xC4] tipo=2  cnt=0    [0xD0] tipo=8  cnt=7296 [0xDC] tipo=10 cnt=36
     [0xE8] tipo=45 cnt=7260 [0xF4] tipo=100 cnt=60  (total asociaciones=14652)
```

Los `cnt` de BEL (7296, 7260) descartan que sean "número de cámaras" — son demasiado altos para un país
pequeño. Interpretación más plausible: nº de **enlaces de carretera (HERE Link IDs)** vinculados a cada
tipo de amenaza/cámara en ese país.

### Próximo enfoque recomendado (no intentado aún)

1. **No** confiar en escaneo NDS de fuerza bruta sin validación cruzada
2. Buscar la verdadera tabla de cámaras vía los **HERE Link IDs** (visible en patrones tipo
   `(X, X+0x8000)` / `(X, X+0x800000)` que sí están confirmados como estructurales) y cruzarlos con
   `SPEED_PATCH.db` (que usa la misma clave `LINK_ID`) — ese cruce podría revelar qué enlaces llevan
   asociada una amenaza de tipo 5/11/13/15/17
3. Si se dispone de una build anterior/posterior del mismo haftlt, hacer diff binario para aislar
   qué bytes cambian al añadir/quitar exactamente una cámara conocida (método más fiable que inferencia)
4. Correlacionar con base de datos pública de radares DGT antes de declarar cualquier coordenada confirmada

### Test del cruce Link ID — resultado INCONCLUSO (ligera señal, no probado)

Se probó el punto 2: extraer todos los IDs de las secciones 3 y 4 de SPN (masking bit31:
`v & 0x7FFFFFFF`), filtrarlos al rango válido de `LINK_ID` en SPEED_PATCH.db (736–153,433,402),
y comprobar cuántos coinciden con un `LINK_ID` real:

```
sec3: 5,244/16,873 IDs distintos caen en rango LINK_ID → muestra 5000 → 6.46% coinciden
sec4: 7,271/21,805 IDs distintos caen en rango LINK_ID → muestra 5000 → 6.50% coinciden
control aleatorio (mismo rango):                          4.56% coinciden
densidad real de LINK_ID en el rango (7,100,825 distintos / 153,432,666): 4.63%
```

La tasa observada (6.46–6.50%) es ~1.4× la línea base de densidad/azar (4.56–4.63%) — una señal
por encima del ruido pero **demasiado débil para confirmar** que las secciones 3/4 sean mayormente
`LINK_ID`s reales de carretera. Interpretación más probable: una **minoría** de los valores en
sec3/sec4 son LINK_IDs genuinos, mezclados con otro tipo de dato (índices internos, IDs de tile,
referencias cruzadas no relacionadas con SPEED_PATCH.db). No usar este cruce como base fiable para
localizar cámaras sin filtrado adicional (p.ej. cruzar solo los IDs que aparecen en posiciones
consistentes con el patrón bidireccional `(X, X+2^31)` Y dentro de tiles de España).

---

## Relación con otros archivos de cámara

| Archivo | Tamaño | Función | Estado análisis |
|---------|--------|---------|----------------|
| `VIT_EUR.hafls` | 80 MB | Safety layer pan-EU | IFF data, estructura similar a haftlt |
| `VIT_EUR.hafcc` | 312 KB | Configuración país/ciudad | 65,001 records, no son cámaras GPS |
| `VIT_EUR.hafbc` | 3.6 KB | Límites por país | **Texto plano** — completamente legible |
| `SPEED_PATCH.db` | 153 MB | Límites por Link ID | **SQLite** — completamente accesible |
| `HAFTLT/*.haftlt` | 1.8-11 MB | Cámaras por país | Binario propietario — encoding GPS refutado |
| `VIT_EUR.hafr` | 921 MB | Grafo de rutas pan-EU | Sin cifrar, mismo encoding NDS refutado probado y descartado |

## Estado real de la investigación (resumen honesto, 2026-06-30)

Tras un test sistemático contra datos públicos reales (radares DGT) y contra el archivo de mayor
tamaño y mejor candidato a contener geometría real (`hafr`, 921 MB), **no se ha logrado decodificar
ninguna coordenada GPS real en ningún archivo HERE binario de este paquete**. Toda coordenada
"confirmada" en notas anteriores de esta investigación debe considerarse refutada.

**Lo que SÍ está sólido:**
- Estructura de cabecera HAF común (`FORMAT_VERSION_*`, `DATA_VERSION_*`, offsets/tamaños de sección)
- Layout de secciones de `haftlt` (índice 6B, secciones 1-4, sus invariantes aritméticas)
- `SPEED_PATCH.db` — SQLite accesible, *no* es el archivo que el usuario quiere modificar (límites de
  velocidad por tramo, no posición de cámaras) pero queda como referencia de formato accesible
- Patrón estructural de tile en `lon=±1.40625°E` → consistente con jerarquía NDS real de 256 tiles
  en el nivel raíz (delta-encoding, no coordenada absoluta de 32 bits por punto)

**Lo que falta y por qué es difícil:**
- El formato NDS real usa coordenadas **relativas a un tile/mesh base** (Morton-coded), no un valor
  lineal de 32 bits por punto — hay que localizar la tabla de tile-bases y el esquema de delta exacto
  antes de poder leer o escribir ninguna coordenada
- El binario que sí sabe decodificar esto (`appnavi.tar`) está cifrado con AES sin clave conocida
- No disponemos de una segunda versión del mismo `.haftlt`/`.hafr` para diff binario dirigido

**Caminos restantes, de más a menos prometedor:**
1. Obtener una build de mapas HERE distinta (versión anterior o posterior) del mismo país → diff
   binario dirigido sobre un cambio de cámara conocido — el método más fiable, pero requiere material
   que no tenemos ahora
2. Estudiar la especificación pública de NDS Association (formato NDS estándar, no propietario HERE)
   para entender el esquema real de tile-base + delta y aplicarlo a estos archivos
3. Intentar romper el cifrado AES de `appnavi.tar` / `mango-rootfs.tar.gz` para acceder al parser real
   (proyecto de RE considerablemente más grande, fuera del alcance de esta sesión)

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

## Para modificar: añadir/quitar cámara — ⚠️ NO VIABLE TODAVÍA

El procedimiento descrito en una versión anterior de esta nota (insertar struct de 12B en la región
sec4_end→EOF) **asumía que esa región es un array de registros de cámara fácilmente localizables**.
Esa asunción ha sido refutada (ver sección de corrección arriba): no se ha logrado distinguir de forma
fiable un registro de cámara real de ruido/coincidencias NDS en esa región. Hasta no resolver la
estructura real (vía cruce de Link IDs, diff binario entre builds, o ingeniería inversa del binario de
`appnavi` que parsea este formato), **no hay un método de modificación seguro para `.haftlt`**.

Alternativa práctica ya validada para el objetivo final (avisos de velocidad/radar): el workflow de
`SPEED_PATCH.db` (ver [[speed_patch_workflow]]) sí está confirmado y operativo — permite modificar
límites de velocidad por tramo sin tocar el formato binario propietario haftlt.

---

## Diff binario contra segunda build real (260128) — sesión 2026-07-09

Apareció una segunda descarga completa del paquete (`YB_22.EUR.S5W_L.001.001.260128`, mapas HERE `18.52.70.012.632.5`, datos `2025-11-22`) junto a la `251204` del repo (datos `2025-07-16`) — ~4 meses de diferencia real, mismo formato, mismo país. Primera vez que se dispone de dos builds reales para diff dirigido (el paso pendiente #3 de la sección anterior). Análisis completo: [`docs/haftlt_build_diff_260128.md`](../../docs/haftlt_build_diff_260128.md).

**Correcciones a la tabla de cabecera de arriba:**
- `0x40` **NO es constante** — es un contador de versión de build que incrementa +1 por release (`0x00031706`→`0x00031707`). Coincidía en muestras previas por pertenecer al mismo build.
- `0x4C` **NO es constante** — codifica literalmente la fecha de `DATA_VERSION` en decimal `YYYYMMDDHH` (`2025071509`→`2025112102`). Da lectura directa de la fecha sin parsear el string ASCII.
- `0x80` (crc/hash) cambia de forma dependiente del contenido, fórmula aún no resuelta.

**Localización de zonas de crecimiento real entre builds:**
- Índice (`0x200`→sec1_start) y Sección 1: **crecimiento cero** en las 3 muestras (AUT/DNK/SPN) pese a 4 meses de datos reales → descartadas definitivamente como almacén de cámaras.
- Secciones 2+3+4: **tamaño exactamente constante** entre builds pero ~90% de bytes distintos → consistente con IDs secuenciales que se renumeran en cascada ante cualquier inserción aguas arriba (no son la fuente real, es ruido de renumeración).
- Las únicas dos regiones que **sí crecen** en tamaño: región media (`sec1_end`→sec2_start) y región cola (`sec4_end`→EOF) — candidatas reales a contener las cámaras nuevas.
- En la región cola de AUT se encontró una subtabla muy regular: grupos de `u16+u16` donde el campo bajo incrementa en pasos de `0x80` y el alto en saltos de `0x800` — forma de tabla de distancias/umbrales cuantizados (hipótesis: parámetros de la progresión de alerta LOW/MID/HIGH o de Section Control), no de coordenadas GPS.

**Todos los 13 países crecieron entre builds, ninguno decreció** (BEL +2.35%, el resto +0.07–0.14%) — coherente con radares que solo se añaden. Confirma indirectamente que SÍ hay cámaras nuevas codificadas en algún lugar del fichero entre estas dos fechas, solo falta localizar el registro exacto.

**Sigue sin resolverse:** el registro de cámara completo (posición + atributos) insertable de forma segura. Ver docs para próximos pasos recomendados (diff de ventana más corta, repetir en BEL, diff de `.hafls`).

**Mapa visual de bytes:** `docs/haftlt_build_diff_260128.md` incluye un mapa de bytes coloreado por región (`docs/assets/haftlt_bytemap_AUT_251204.png` / `_260128.png`) que muestra visualmente las dos únicas bandas que crecen entre builds — útil como referencia rápida antes de reanudar la investigación.

## Tabla de nombres de calle + tabla de 16 bytes (sesión 2026-07-09) — mayor avance de la investigación

Buscando si el `.haftlt` era un contenedor de otros ficheros (no lo es — verificado: cero `PK\x03\x04` de ZIP, solo firmas falsas positivas de IDs/texto coincidentes), se encontró texto legible real dentro de la región cola: nombres de calle/carretera en UTF-8.

**Formato confirmado byte a byte:** Pascal-string `[u8 length][bytes UTF-8, sin terminador]`, empaquetadas consecutivamente. Verificado con `"Carretera del Prat"` (prefijo `0x12`=18) seguido de `"Calle del Doctor Tolosa Latour"` (prefijo `0x1e`=30) — longitudes exactas.

**Detector genérico** (sin offsets hardcodeados por país, busca una cadena de ≥15 Pascal-strings consecutivas válidas) confirmado en los 4 países:

| País | nombres (251204→260128) | registros de 16B (251204→260128) |
|---|---|---|
| AUT | 9.849 → 9.849 | 12.139 → 12.139 |
| BEL | 7.563 → **7.746 (+183)** | 7.875 → **8.076 (+201)** |
| DNK | 23.067 → 23.067 | 9.081 → 9.081 |
| SPN | 20.290 → 20.290 | 23.528 → 23.528 |

Justo tras la tabla de nombres: `[u32 record_count][12B padding][record_count × registro de 16B]`. Conteo verificado aritméticamente contra el tamaño real del fichero (holgura 0–2 bytes) en los 4 países.

**Bélgica es el único con crecimiento real en esta tabla** (coherente con ser el país de mayor delta total, 2.35%). Los 183 nombres nuevos son calles belgas genuinas (`"Bd. Louis Mettewie/Mettewielaan"`) — **no todas al final de la lista** (aparecen en posiciones 0-9 y también ~7100-7740), sugiriendo reordenación/reindexación en cada build, no append puro.

**Hipótesis probada y REFUTADA:** `f0` del registro de 16 bytes como offset (relativo al inicio de la tabla de nombres) hacia su cadena asociada — 0/30 aciertos contra las 20.290 cadenas reales de SPN. La conexión nombre↔registro sigue sin resolverse. Patrones observados sin confirmar: `f1`/`f5`/`f7` casi constantes en bloques (posible ID de grupo/categoría); `f2`/`f3` alternan un valor real con centinela `0xFFFF`, valor real ronda el índice del propio registro (mismo patrón de ID secuencial + slot alternante que Secciones 3-4, aquí a nivel u16).

**Extracción automatizada:** `tools/haftlt_parser/parse_haftlt.py` ahora genera `street_names.csv` y `linked_records.csv` para cualquier país sin intervención manual (funciones `find_string_pool`, `parse_string_pool`, `try_parse_linked_records`).

**Por qué importa:** primer texto legible con significado geográfico de toda la investigación (3+ sesiones previas nunca encontraron nada así). No es la coordenada de una cámara, pero es la pista más prometedora hasta ahora — la tabla de 16 bytes al lado casi con toda seguridad conecta con algo posicional dado el patrón de IDs, solo falta encontrar cómo.

### Continuación (mismo día): `f0` = ID estable, conexión directa REFUTADA

Usando Bélgica dirigido (único país con cambio real en estas tablas): comparar *conjuntos de valores* por campo entre builds (no posición) reveló que `f0` tiene 97,4% de solapamiento — es un **ID persistente por registro**, no un índice posicional. Filtrar por "`f0` nunca visto en la build antigua" aísla 204 registros genuinamente nuevos (delta real: 201) — mucho más preciso que el diff binario prefijo/sufijo usado antes (que da 0-69 de prefijo común porque la tabla se renumera casi entera en cada build).

`f2`/`f3` = referencias bidireccionales a **registros vecinos** (no a nombres): registro en índice 3406 tiene `f3=3407`; registro 3407 tiene `f2=3406`. Explica por qué antes parecían "rondar el índice propio".

**Prueba sistemática y REFUTACIÓN:** los 8 campos de los 204 registros nuevos probados como offset (4 anclas × 2 sentidos) e índice directo contra los 157 nombres nuevos de Bélgica → **0 aciertos en todas las combinaciones**, frente a ~4,1 esperados por azar (simulación 10.000 pruebas). La conexión nombre↔registro NO es un campo simple. Detalle completo, incluyendo la tabla de resultados por campo/ancla: `docs/haftlt_build_diff_260128.md` sección "Resultado 6".

**No repetir** la prueba de offset/índice simple sin nueva evidencia — está descartada con solidez estadística, no es "no probado todavía". El siguiente paso es buscar una tabla puente (quizá Secciones 2-4, que comparten el patrón ID+vecino) o aceptar que `linked_records` no tiene relación con los nombres.

### `.hafls` — tabla de tiles candidata (nuevo, mismo día)

Tras agotar las hipótesis de conexión nombre↔registro en `.haftlt`, se investigó `.hafls` (capa pan-EU, 84 MB) desde cero — cabecera con layout distinto al de `.haftlt`, sin la misma tabla de nombres. Se encontró en offset `0x108` una tabla muy regular (~464.688 entradas de 8 bytes, stride constante `0x300000`=3.145.728=3MB, esquema de índice de 2 niveles en los 16 bits altos/bajos del segundo campo) que es **idéntica entre builds** — el mejor candidato a "tabla de tile-bases" NDS encontrado en toda la investigación. Aún sin decodificar a coordenadas reales. Detalle completo: [`docs/hafls_tile_table.md`](../../docs/hafls_tile_table.md).

**Secciones 3-4 descartadas como tabla puente estable (mismo día, BEL):** aplicando el mismo método de solapamiento de valores por campo entre builds — Sección 3: jaccard=0,359 (moderadamente inestable, "nuevos" ≈48% del total, muy por encima del crecimiento real de +2,6%). Sección 4: **jaccard=0,000** — de miles de IDs, solo 5 sobreviven entre builds. A diferencia de `linked_records.f0` (97,4% estable), las Secciones 3-4 se **regeneran casi por completo en cada build** — no son identificadores persistentes, son contadores secuenciales que se recalculan desde cero. Confirma (con datos, no solo sospecha) la hipótesis original de "renumeración en cascada" y descarta usarlas como puente hacia los nombres vía coincidencia de ID.

---

**Herramientas de sesión 2026-07-09 (todas en `tools/`, código sí commiteado, datos/salida no):**
- `tools/haftlt_viewer/generate_viewer.py` — visualizador HTML interactivo (minimapa + hexdump + inspector u8/u16/u32) para un país, comparando dos builds.
- `tools/haftlt_parser/parse_haftlt.py` — desempaqueta índice + Secciones 1–4 a CSV/JSON; con `--other` localiza los rangos exactos de las dos zonas candidatas.
- **Ojo con `*_diverging.bin`/región "candidata"**: su tamaño NO es "bytes nuevos" — es todo el rango tras el prefijo común, y la mayoría es contenido antiguo renumerado (mismo fenómeno que Secciones 2-4). El tamaño real de contenido nuevo es `header.json.growth_zones.true_size_delta_bytes` (p.ej. AUT: rango marcado 1,045,808 B pero delta real solo 2,248 B). Aislar el registro exacto dentro de ese rango sigue siendo el paso pendiente.
- Ya ejecutado contra AUT/BEL/DNK/SPN (ambas builds); `.haftlt` extraídos en `HU/images/navi_eu/haftlt_extracted/{251204,260128}/`, salida parseada en `HU/images/navi_eu/haftlt_parsed/` — ambas rutas fuera de git (bajo `HU/`), no hace falta re-extraer del ZIP de 17GB en sesiones futuras.

Related: [[haf-format]] · [[project-radar-db]] · [[re-findings]]
