---
name: haf-format
description: "HERE Automotive Format (HAF) — estructura de cabecera, extensiones de fichero, SPEED_PATCH.db schema, y análisis técnico de los mapas HERE Europa"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2f9fdbd7-182d-499f-807a-20ce446fa9ba
---

## HERE Automotive Format (HAF)

Formato propietario de HERE para datos cartográficos embebidos. Sin spec pública.

### Cabecera común a todos los ficheros HAF binarios
```
Bytes 0x00–0x1F:  "FORMAT_VERSION_XX.XX.XX\0..." (32 bytes, null-padded)
Bytes 0x40–0x5F:  "DATA_VERSION_YYYY.MM.DD.HH\0..." (32 bytes, null-padded)
Bytes 0x80+:      Payload binario específico del tipo
```

### Extensiones y contenido

| Extensión | Significado | Tamaño en este paquete |
|-----------|-------------|------------------------|
| `.hafp` | HAF Partition — tiles cartográficos principales | ~10.6 GB (14 partes) |
| `.hafr` | HAF Route — grafo de routing | 921 MB |
| `.hafaip` | HAF ADAS Info Partitions — horizonte electrónico | ~2.86 GB (4 partes) |
| `.hafgsi` | HAF Global Spatial Index — índice espacial R-tree | 274 MB |
| `.hafls` | HAF Local Safety — cámaras velocidad pan-EU | 80 MB |
| `.haftlt` | HAF Traffic Local Threats — radares por país | 2–11 MB/país |
| `.hafmma` | HAF MultiMedia Assets — 3D, texturas ASTC, sprites | varios |
| `.hafwmd` | HAF World Map Data — mapa mundo baja res | 2.7 MB |
| `.hafbc` | HAF Basic Conditions — vel. default por país | 3.6 KB (ASCII!) |
| `.hafcc` | HAF Country Configuration | 299 KB |

### Estructura del paquete de mapas
```
S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip (16.7 GB comprimido, ~32 GB descomprimido)
├── Data/Nation/EUR/
│   ├── MAP/    Ficheros .hafp, .hafr, .hafaip, .hafgsi, .hafls, .haftlt, .hafmma, .hafwmd, .hafbc, .hafcc
│   ├── NI/     Navigation Intelligence — JSONs de configuración
│   ├── RES/    Recursos: skins (.skn), sonidos (.wav), tráfico (.alt), DEM (.cad)
│   └── SEARCH/ Categorías POI
├── vr/         Diccionarios fonéticos ASR y categorías VOZ (763 MB)
├── GlobalImage/ Assets UI globales, speed limit PNGs (185 KB)
└── Text.Info/  Licencias open source (COPYRIGHT.TXT)
```

## SPEED_PATCH.db (160 MB descomprimido)

Base de datos **SQLite 3** con límites de velocidad por segmento. Directamente accesible con `sqlite3`.

- Versión formato: `1.0.1.0`; datos: `2025072316` (23 julio 2025)
- **10.353.101 registros**

```sql
CREATE TABLE VERSION_INFO (FORMAT_VERSION TEXT, DATA_VERSION TEXT);

CREATE TABLE SPEED_PATCH (
    LINK_ID      INT64,   -- ID segmento HERE (clave foránea en .hafp)
    DIR          INT,     -- 0=A→B, 1=B→A, 2=ambos sentidos
    SP_LIMIT     INT,     -- km/h
    VEHICLE_TYPE INT,     -- máscara de bits (ver tabla abajo)
    PRIMARY KEY (LINK_ID, DIR, VEHICLE_TYPE)
) WITHOUT ROWID;
```

**VEHICLE_TYPE máscara:** 0=todos, 7=coche+moto+ciclomotor, 15=+veh. pesados ligeros, 23=+camiones, 31=+autobuses, 127=todos los tipos.

**DIR:** 0=sentido digitalización A→B, 1=B→A, 2=ambos.

**Distribución de límites:**
- 50 km/h: 3.77M registros (urbano predominante)
- 30 km/h: 1.48M · 90 km/h: 1.36M · 80 km/h: 957K

## Radares y seguridad vial

**HAFTLT/** — 13 ficheros por país (formato HAF v1.04.02, julio 2025):
DEU (10.94 MB), ITA (11.25 MB), FRA (9.46 MB), GBR (9.47 MB), SPN (5.49 MB), CZE (5.71 MB), CHE (4.11 MB), NOR (3.94 MB), SWE (3.75 MB), AUT (2.71 MB), DNK (2.18 MB), BEL (1.82 MB), NLD (1.93 MB).

TLT = **Traffic Local Threats** (terminología HERE para cámaras fijas y control de velocidad media).

**VIT_EUR.hafls** (80 MB) — Safety layer pan-europeo (HAF v1.00.01, julio 2025).
- Cabecera: 0x40=`0x00031706` (mismo tag que haftlt), 0x4C=2,280,000, 0x50=76,320,000, 0x54=33,000,000 (posible bounding box Europa en escala interna HERE)
- Búsqueda de pares GPS en rango europeo (stride 8B): 18,193 hits lat España — pero lon ≈ 0° → usa delta-encoding / Link IDs, NO coordenadas GPS planas

**VIT_EUR.hafcc** (312 KB) — HAF v1.00.02, DATA_VERSION 2025.02.25.12.
- 65,001 registros en offset 0x80 — **NO son cámaras GPS**
- Pares de muestra: (3,080,070 / 18,046,915) → en WGS84 µ° serían 3°N 18°E (norte de África) — encoding desconocido
- Estructura: bloques variables con sub-registros de coord_pair + link_ref
- Probable uso: configuración de zonas de ciudad / áreas urbanas

**Sonidos alerta radar** (`CT000009_HIGH/MID/LOW.wav`, 41.538 B c/u): `CT` = Camera Trap. Progresión LOW→MID→HIGH según se aproxima la cámara.

## Tráfico histórico (.alt)

24 países, 2 ficheros cada uno (`_IMP.alt` mph, `_MET.alt` km/h).
Magic: `"ALERT_C\0"` (8 bytes). Todos fechados **14 julio 2021** (datos estadísticos, no tiempo real).
Países: BGR, CZE, DNK, DEU, ESP, FIN, FRA, GBR, GRC, HRV, HUN, ITA, KOR, NLD, NOR, POL, PRT, ROU, RUS, SVK, SVN, SWE, TUR, UKR.

## ADAS — Horizonte electrónico (.hafaip)

~2.86 GB total (4 particiones). HAF v1.07.01, datos 16 julio 2025.
Contiene: pendientes, radios de curvatura, límites de velocidad enlazados, atributos de vía avanzados.
Alimenta: **SCC** (crucero predictivo de pendientes), **LKAS** (asistencia de carril), **ISA** (velocidad asistida inteligente).

## Software de terceros confirmados (COPYRIGHT.TXT)

| Componente | Función relevante para RE |
|------------|--------------------------|
| **Rijndael (AES)** | Cifrado de archivos OTA — **confirma AES** |
| **SQLite** | Motor de SPEED_PATCH.db — accesible directamente |
| **Anti-Grain Geometry 2.4** | Renderizado 2D vectorial |
| **Mesa3D** | OpenGL API — GPU compatible con OpenGL ES / Vulkan |
| **Texturas ASTC** | GPU embebida soporta Adaptive Scalable Texture Compression |

## Configuración JSON (NI/)

- **`RpOption.json`** v23 (2025-02-18): 5 modos de ruta — Fastest(31), Recommended(32), Economic(33), Prefer motorway(34), Avoid tolls(35). Variante `_AAOS` para Android Automotive OS.
- **`RpAvoidOption.json`**: evitar autopistas(11), vignette(12), ferrys(13), restricciones horarias(14), peajes(15), túneles(16), HOV(17), sin asfaltar(18). Variante Turkey separada.
- **`ServerURL.json`**: URLs de GIS/TIS/TIT vacías (`EU_URL=""`) — paquete completamente offline. `EU_SSL: 1` → HTTPS cuando se configure.
- **`SEARCH/CATEGORY_EU.json`** v1.2.8: Kia(0xD080), Hyundai(0xC080), Genesis(0xE080) con categorías dedicadas. Soporte EV charging (Shell Recharge, ChargePoint, etc.).

## UI y assets visuales

- **5 temas de mapa** (.skn, 118 KB c/u): BLACK, SIMPLENIGHT, SIMPLEBROWN, SIMPLEWHITE, SMARTBROWN
- **Paletas de renderizado** (.hafmma): LATTE, MILK, MOCHA (intensidades de contraste)
- **DEM** `VIT_AREA_DATA_HM.cad` (877 MB): elevación digital para relieve 3D y cálculos ADAS de pendiente
- **Junction Exit View**: fotos reales de salidas de autopista (funcionalidad premium HERE)
- **Señales de velocidad**: `GlobalImage/SpeedLimit/speed_limit_0-9.png` + `_red_` (dígitos compuestos en pantalla)

### 🎯 Visualización de mapas — primeras imágenes reales extraídas (sesión 2026-07-10/11)

Ver detalle completo en [`docs/rendering_visual_assets.md`](../../docs/rendering_visual_assets.md). Resumen:

- **`.skn`** (magic `REDSKIN#`): manifiesto de tema — referencia 3 recursos externos vía texto UTF-16LE (`VIT_EUR_CE_THEME_IMAGE.bin` atlas de texturas, `model_sym.bin`/`model_bld.bin` modelos 3D) + tabla de **807 registros de estilo** de 32 bytes (sentinelas `0xCCCC`/`0xCC00`, ID secuencial, campo `REF` no-secuencial candidato a índice de color/textura). Los 5 temas comparten tamaño exacto (121.492 B) → misma tabla de IDs, distinto `REF` por tema.
- **`VIT_EUR_CE_THEME_IMAGE.bin`** (84,5 MB) 🎯 **pixel format resuelto**: índice de 64 B/registro (`seq`, `size`, `data_offset` absoluto, verificado con `offset[i]+size[i]==offset[i+1]`); cada textura lleva cabecera de 32 B con **enums reales de OpenGL** (`channels=3→GL_RGB=6407`, `channels=4→GL_RGBA=6408`) + `width`/`height`/`mip_levels` (cadena de mipmaps completa hasta 1×1) + píxeles sin comprimir. Verificado renderizando 5 texturas reales (512×512 gradiente de cielo verde, 128×128 panel UI, etc.) — ya no es hipótesis.
- **`VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma`** 🎯 — **hallazgo principal**: cabecera HAF + tabla de 204 offsets → **136 imágenes WebP reales**, extraídas y decodificadas con éxito (Pillow/`dwebp`). Son ilustraciones esquemáticas 3D de bifurcación/salida de autopista (panel de "próxima maniobra"), dominante 640×720 px, con variantes con canal alfa para overlay de resalte de carril. Confirma que LATTE/MILK/MOCHA son la misma escena en 3 luminosidades (día/claro/noche). **Primera vez en 5+ sesiones que se extrae contenido visual real y con significado del paquete de mapas.**
- **`VIT_EUR_SYMBOL_48.hafmma`** (19,5 MB): mismo esqueleto contenedor, pero el payload NO es WebP/PNG. **ASTC descartado con evidencia directa** (0 coincidencias del magic `13 AB A1 5C` en todo el fichero) — es RGBA sin comprimir organizado por categoría con nombre legible (`"LAND\COMMON"`), con secuencias de color plano repetido típicas de iconos de POI. **El stride/ancho exacto por icono queda sin resolver** — un barrido sistemático de 192 offsets candidatos con ancho fijo (incl. 48 px) no dio ninguna imagen coherente; probablemente el ancho varía por icono vía la tabla de sub-entradas, no explorada con precisión.
- **`VIT_EUR_3D_LANDMARK_ASTC.hafmma`** (379 MB) 🎯🎯 **ASTC confirmado Y decodificado**: magic ASTC estándar (`13 AB A1 5C`) 342 veces en 2 MB muestreados (1.451 en 10 MB), bloque 10×10, cadena de mipmaps completa 256×256→...→2×2. Se compiló `ARM-software/astc-encoder` desde fuente (`brew install cmake` + build NEON; no hay fórmula Homebrew para `astcenc`) y se decodificaron texturas reales con `astcenc -dl`: **son texturas de fachadas de edificios landmark** (ventanas, columnas, tejados, planta de patio) — primer contenido 3D/arquitectónico real visualizado de toda la investigación.
- **`GlobalImage/**/*.png`**: PNG estándar ya directamente visualizables sin RE (banderas, popups, peajes, viñetas, dígitos de velocidad).

## Catálogo de primitivas genéricas de serialización (sesión 2026-07-09)

Tras analizar en profundidad `.haftlt` (`linked_records`) y `.hafls` (tabla dispersa en offset `0x108`), aparecen **los mismos 3-4 patrones de bajo nivel una y otra vez, en ficheros y offsets totalmente distintos.** Es casi seguro que son primitivas genéricas de la toolchain de serialización de HERE (estructuras de datos reutilizables), no formato específico de cámaras/radares. Catalogarlas aquí para no re-descubrirlas creyendo cada vez que son un hallazgo nuevo:

1. **Slot vacío / tombstone**: `[u32 0xFFFFFFFF][u32 0x00000000]` — relleno en tablas dispersas tipo hash. Visto en la tabla de `0x108` de `.hafls` (79.504 de 464.688 entradas).
2. **Tabla de umbrales/distancia ×128**: un valor pequeño (<4096) junto a un valor múltiplo exacto de 128 que va incrementando. Visto en la región cola de `VIT_EUR_AUT.haftlt`, justo antes de la tabla de nombres en `VIT_EUR_BEL.haftlt`, dentro del bloque denso de la tabla de `.hafls` (36.805 entradas), **y confirmado como la estructura real de la Sección 2 completa de `.haftlt`** (13.434 registros en BEL: `a` constante en grupos de 3-4, `b`=0,128,256,384... — descarta a Sección 2 como enlace a nombres o coordenadas). Hipótesis de uso: cuantización de distancia/tiempo (posible relación con la progresión de alerta LOW/MID/HIGH), no confirmada.
3. **Contador pequeño + cuenta variable**: valor que incrementa suavemente (deltas de un dígito) junto a un valor pequeño (0-15 aprox.) — variante del anterior. Visto en el resto del bloque denso de `.hafls` (167.711 entradas).
4. **ID + referencia bidireccional a vecino**: un campo que es un ID casi único y estable entre builds, y otro par de campos que apuntan al índice de array del registro anterior/siguiente (con centinela `0xFFFF`/`0xFFFFFFFF` cuando no hay vecino en ese sentido). Visto en `linked_records` de `.haftlt` (confirmado con prueba de solapamiento entre builds) y de nuevo cerca del final de la tabla dispersa de `.hafls`.

**Por qué importa:** cuando aparezca un patrón "interesante" en un fichero HAF nuevo, comprobar primero si encaja con uno de estos 4 antes de tratarlo como hallazgo nuevo — ya ha pasado 3 veces en la misma sesión que un patrón prometedor resultaba ser una de estas primitivas genéricas. Ninguna de las 4, tras inspección, codifica una coordenada geográfica reconocible.

**Implicación para la investigación de radares:** la inspección visual/estadística de bytes sin el parser real (`appnavi`, cifrado con AES) tiene rendimientos claramente decrecientes en este punto — se necesita descifrar el parser real (exploit físico `gen5w`) para saber qué contenedor genérico de estos usa cada feature y con qué semántica exacta, en vez de seguir infiriendo desde fuera.

### `.hafcc` revisitado con las herramientas de hoy — perfil distinto, sin resolver

`VIT_EUR.hafcc` (312.740→309.248 bytes entre builds) ya se había analizado en sesión 2026-06-30 y descartado como cámaras GPS (encoding de coordenadas no coincide con WGS84). Revisitado hoy: no comparte el layout de cabecera de `.haftlt` (todos los campos de sección dan 0) ni contiene tabla de Pascal-strings. El primer byte divergente entre builds es offset `0x52` con **sufijo común de 0 bytes** — como `.hafls`, prácticamente todo el fichero se reescribe.

**Dato nuevo:** el campo `0x80` (65.001, "número de registros") es **idéntico** en ambas builds pese a que el fichero encoge 3.492 bytes — descarta que sea un simple array de tamaño fijo sin más. Comparando el contenido como palabras de 32 bits desde offset `0x240`: **jaccard=0,850** entre builds — ni la persistencia casi total de `linked_records.f0` (0,974) ni la regeneración completa de Sección 4 de `.haftlt` (0,000). Es un perfil de estabilidad intermedio no visto hasta ahora, compatible con cambios de contenido reales (no solo renumeración), pero sin aislar qué cambió exactamente — pendiente si se retoma esta línea.

**Estructura de bloque variable confirmada** (recuperada de la sesión 2026-06-30, verificada byte a byte hoy contra el hex real en offset `0x240`): `[u32 block_off][u32 field_b][u32 field_c][u32 zero][u32 sub_count][u32 pad]` seguido de `sub_count` triples `[u32 id][u32 coord_a][u32 coord_b]` de 12 bytes cada uno, luego `[u32 link_ref]`. Confirmado exactamente con el primer bloque: `sub_count=3` → triples `(317, 3080070, 18046915)`, `(3087462, 18050737, 4000016)`, `(288, 3812, 66)`, `link_ref=3` — coincide con los pares de muestra de la sesión antigua.

**Intento de encontrar el "id" estable (como `linked_records.f0`) — inconcluso, no descartado.** Se probó tratar todo el fichero desde `0x258` como triples de stride fijo (12 bytes) ignorando los límites reales de bloque (que son de longitud variable según `sub_count`), y comparar solapamiento de valores por fase (0,1,2) entre builds: las tres fases dan jaccard similar y bajo (0,237–0,279), sin que ninguna destaque como el campo `id`. **Esto es más probablemente un artefacto de desalineación** que una conclusión real.

**Se intentó escribir el parser correcto que camina bloque a bloque — falla en el segundo bloque.** El bloque 1 se confirmó exactamente (`sub_count=3`, tres triples válidos, `link_ref=3`, ver arriba). Pero al aplicar el mismo esquema de cabecera (`[block_off][field_b][field_c][zero][sub_count][pad]`) al bloque 2, el campo esperado como "zero" vale `16.998.285` — **no es cero**. Es decir, el `zero=0` del bloque 1 era casuística de esa entrada concreta, no una regla general de la cabecera. La estructura real de bloque tiene más variabilidad de la que asumía la nota de la sesión 2026-06-30 (que tampoco llegó a un parser funcional para todo el fichero). **No resuelto** — replicar el parser exigiría heurísticas más finas (probablemente cabecera de tamaño variable, o un campo adicional que determina la forma del bloque) que no se han desarrollado. Los valores en offset `0x288` en adelante (`5.310.506 / 16.998.285`, `5.318.374 / 17.002.144`...) siguen pareciendo pares con la misma magnitud/patrón de delta que el bloque 1, así que el contenido es coherente — el problema es solo de segmentación del formato, no de que los datos sean ruido.

## Especificación real de NDS para coordenadas (encontrada por búsqueda web, sesión 2026-07-10)

Documentos de patente de Elektrobit Automotive (asociados a NDS Association) describen la codificación real de coordenadas NDS, distinta de lo que se venía asumiendo en sesiones anteriores:

- **Longitud**: entero de **32 bits con signo**, unidad = `90/2^30` grados por LSB (un entero de 32 bits cubre exactamente los 360° completos).
- **Latitud**: entero de **31 bits con signo** (no 32) — mismo unidad `90/2^30`, cubre exactamente 180°.
- Ambos enteros se combinan mediante **intercalado de bits (Morton code)** en un único valor de **63 bits**, no se almacenan como dos campos independientes de igual anchura.
- El direccionamiento por tiles a nivel `k` usa los `2k+1` bits más significativos de ese Morton code — la geografía se parte en `2^(2k+1)` tiles por nivel.

Fuente: patente "Technique for structuring a navigation database" (Elektrobit), vía búsqueda web — no es documentación oficial de HERE, pero describe el estándar NDS del que HERE es miembro fundador, y su formato interno (`.haftlt`/`.hafcc`/`.hafls`) muy probablemente deriva de esta misma base.

**Verificación importante — la fórmula "ingenua" de sesiones anteriores YA ERA correcta para longitud:** `lon = v/2^32 × 360 - 180` (para `v` sin signo de 32 bits) es matemáticamente idéntica a interpretar `v` como entero de 32 bits **con signo** multiplicado por `90/2^30` (son la misma operación, solo expresada distinto). Es decir, el fallo de las 3 sesiones anteriores **no estaba en la fórmula de longitud**.

**Lo que SÍ es nuevo y nunca se probó:** el **intercalado Morton real** — combinar lon (32 bits) + lat (31 bits) en un único valor de 63 bits antes de decodificar, en vez de tratar dos campos del fichero como longitud y latitud **independientes** (que es lo que han hecho todas las sesiones, incluida la de hoy, con cada par `(coord_a, coord_b)` encontrado). Esto es un hueco arquitectónico real en todo lo probado hasta ahora.

**Prueba rápida contra `.hafcc` (sesión 2026-07-10):** se recombinaron los pares conocidos de `.hafcc` (`3.080.070/18.046.915`, `5.310.506/16.998.285`, etc.) en un valor de 63 bits y se desintercalaron como Morton — los resultados son demasiado pequeños en magnitud (del orden de millones) frente al espacio NDS completo (miles de millones, dado el unidad `90/2^30`). **No descarta el Morton en general**, pero descarta que estos valores concretos de `.hafcc` sean un Morton code NDS a resolución completa — son más probablemente deltas locales o un tipo de dato no geográfico, coherente con las conclusiones ya alcanzadas hoy sobre `.hafcc`.

**Pendiente para una futura sesión:** aplicar el intercalado Morton correcto (63 bits, no independiente) a los campos de `linked_records` de `.haftlt` (especialmente `f4`/`f6`, ya descartados como coordenada lineal independiente pero nunca probados como mitades de un Morton combinado) y a la tabla dispersa de `.hafls`, con prueba de permutación desde el principio.

Related: [[project-context]] · [[vr-engine]] · [[file-details]] · [[haftlt-format]] · [[project-radar-db]]
