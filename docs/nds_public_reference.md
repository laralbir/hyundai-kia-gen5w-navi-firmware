# Documentación abierta de NDS encontrada — algoritmo exacto probado, sigue negativo

**Fecha:** 2026-07-11
**Pregunta del usuario:** ¿no hay documentación abierta que indique cómo interpretar los mapas de HERE? Hasta ahora toda la investigación se basó en ingeniería inversa pura (inspección de bytes) más una única referencia externa (una patente de Elektrobit sobre codificación de coordenadas NDS, encontrada por búsqueda web en sesión anterior). Nunca se había buscado sistemáticamente si existe una implementación de referencia pública y verificable.

## Lo que se encontró

**`gitlab.com/g4933/gen5w`** (nuestro ecosistema de exploit) no documenta el formato de mapas — solo el acceso al sistema operativo del HU. Pero **HERE es miembro de la NDS Association** (confirmado: "HERE Navigation Map delivers NDS promise of compatibility and interoperability", nds-association.org) y la NDS Association mantiene una organización pública en GitHub:

**[`github.com/ndsev`](https://github.com/ndsev)** — 29 repositorios públicos, licencia BSD-3-Clause en los relevantes. Los más útiles para esta investigación:

| Repo | Contenido |
|---|---|
| **`ndslive-math`** | Implementación de referencia (C++, Python, Java, Go, Rust, JS) de la conversión WGS84 ↔ coordenadas enteras NDS ↔ código Morton, y el empaquetado de `PackedTileId` (tile ID con nivel codificado en los bits altos) |
| `mapget` | Cliente/servidor para datos de mapa NDS.Live en caché |
| `erdblick` | Visor de mapas NDS.Live real (basado en `mapget` + deck.gl) |
| `zserio` | Framework de serialización/IDL que usa NDS — probablemente NO es lo que usa `HAF` (nuestros ficheros no tienen cabeceras zserio reconocibles), pero confirma que HERE participa del ecosistema NDS más amplio |

**Hallazgo colateral relevante:** `.hafmma` está confirmado en fuentes independientes (filext.com) como formato usado específicamente por sistemas **Mobis AVN de Hyundai/Kia** — coincide exactamente con nuestra plataforma, refuerza que "HAF" es la familia de formatos HERE usada en este ecosistema concreto (no una etiqueta interna inventada).

## El algoritmo exacto (no una aproximación de patente)

`ndslive-math` da el algoritmo **byte a byte**, no una descripción textual como la patente usada hasta ahora:

- **Coordenada NDS**: `x = floor((lon/360) × 2^32)` (32 bits con signo), `y = floor((lat/180) × 2^31)` (31 bits con signo).
- **Código Morton**: intercalado de bits de `x` e `y` (con `y` desplazado 1 bit primero) en un valor de 64 bits con el bit 63 puesto a cero — 31 iteraciones intercalando bit a bit, más un bit final de `x`.
- **`PackedTileId`**: entero de 32 bits — bits altos codifican el nivel (`1 << (16+level)` sumado al número Morton del tile), bits bajos son el número Morton del tile a esa resolución. Los niveles van de 0 a 15; nivel 15 da valores negativos (bit de signo).

Por precaución (el clasificador de seguridad del propio asistente bloqueó ejecutar directamente el código descargado del repo de terceros, correctamente — es código elegido autónomamente, no nombrado por el usuario), **se reimplementó el algoritmo a mano** en Python a partir de la lectura línea a línea del código de referencia, en vez de ejecutar su fichero. Verificado con una prueba de ida y vuelta (Madrid, 40.4168°N/-3.7038°E → Morton → de vuelta a WGS84, error <1e-4°).

## Prueba rigurosa contra datos reales — sigue negativo

Con el algoritmo exacto (no aproximado) se repitió la búsqueda de coordenadas en tres ficheros, contra las **784 coordenadas GPS reales de radares DGT** (ver [`.claude/memory/reference_dgt_radar_dataset.md`](../.claude/memory/reference_dgt_radar_dataset.md)), con **proximidad real** (≤0,02°, ~2,2 km) en vez de "cae en el bounding-box de España" (criterio demasiado laxo, usado por error en un primer pase):

| Fichero | Ventanas de 64 bits escaneadas | Candidatos en bbox España | Coincidencias reales (≤2,2 km) |
|---|---|---|---|
| `linked_records` de `VIT_EUR_SPN.haftlt` (5 ventanas posibles dentro del registro de 16 B) | 23.528 registros × 5 | 55 / 38 / 0 / 34 / 0 | 1 / 2 / — / 0 / — |
| Rama de España en `.hafr` (offset `66.781.193`, 393 KB) | 49.152 | 4 | 0 |
| `.hafp03` (primeros 60 MB) | 7.864.320 | 10.415 | **26** |

El caso de `.hafp03` (26 coincidencias) parecía prometedor a primera vista, pero **la prueba de permutación lo descarta**: se barajaron los bytes del mismo fichero 15 veces (control, sin ningún dato real) y se repitió el mismo pipeline. Comparando por **tasa** (coincidencias / candidatos, no el conteo bruto — el conteo bruto estaba confundido por diferencias en el tamaño del pool de candidatos entre pruebas): tasa real 0,250%, **4 de 15 controles igualan o superan esa tasa**, media de controles 0,221%. No significativo (p≈0,27).

## Conclusión

**El algoritmo NDS ahora está confirmado con una fuente pública, oficial y verificable** — esto cierra cualquier duda sobre si la fórmula usada en sesiones anteriores (basada en una patente) era correcta. Pero incluso con el algoritmo exacto, escanear a ciegas buscando un código Morton de 63 bits completo en `linked_records`, `.hafr` o `.hafp03` no encuentra coordenadas reales.

**Hipótesis revisada para la próxima sesión:** el propio spec de NDS.Live explica que las coordenadas raramente se almacenan como Morton completo de 63 bits en los datos de contenido — es mucho más común (y es literalmente para lo que existe `PackedTileId`) almacenar un **tile ID de nivel N** (32 bits) más un **offset pequeño relativo a la esquina suroeste de ese tile** (`SouthWestCorner()` + delta, no coordenada absoluta). Esto encaja con lo que ya se sospechaba desde hace varias sesiones ("NDS es delta-relativo a tile, no absoluto") pero ahora hay una implementación de referencia exacta (`PackedTileId.SouthWestCorner()`, `Size()`, `GetTileIdsForBoundingBox()`) para construir el candidato correcto: localizar primero un `PackedTileId` válido (32 bits, con el nivel codificado en los bits 16+) en los datos, derivar su esquina y tamaño reales, y buscar deltas pequeños (no un Morton completo) en los bytes adyacentes.

## Herramienta de referencia disponible para la próxima sesión

El algoritmo completo (Morton, WGS84↔NDS, `PackedTileId` con todos sus métodos) está en `github.com/ndsev/ndslive-math` (BSD-3-Clause) — con implementaciones paralelas en Python, C++, Go, Java y Rust, y un juego de vectores de prueba (`test-vectors/parity_vectors.json`) para verificar cualquier reimplementación propia byte a byte antes de usarla contra datos reales.

Related: [`hafr_spatial_index.md`](hafr_spatial_index.md), [`hafp_geometry_search.md`](hafp_geometry_search.md), [`road_network_topology.md`](road_network_topology.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
