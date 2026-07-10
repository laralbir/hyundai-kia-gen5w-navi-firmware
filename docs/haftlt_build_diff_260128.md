# Diff binario entre dos builds reales de `.haftlt` (251204 vs 260128)

**Fecha de análisis:** 2026-07-09
**Objetivo:** determinar cómo añadir una cámara/radar a la base de datos nativa de HERE (`VIT_EUR_*.haftlt`), continuando la investigación de [`.claude/memory/haftlt_format.md`](../.claude/memory/haftlt_format.md) y [`project_radar_db.md`](../.claude/memory/project_radar_db.md).

## Por qué este análisis es nuevo

Las tres sesiones de RE anteriores (ver memoria) agotaron el camino de "escaneo de coordenadas GPS por fuerza bruta" con resultado negativo confirmado contra datos reales de la DGT. El propio documento de hallazgos señalaba como paso pendiente más prometedor: *"Obtener una build de mapas HERE distinta (anterior o posterior) del mismo país → diff binario dirigido sobre un cambio de cámara conocido"*. Ese material no existía hasta ahora.

En esta sesión apareció una segunda descarga completa del paquete en `/Users/carlos/Downloads/NaU/Rio_MY22_EU` (versión `YB_22.EUR.S5W_L.001.001.260128`, mapas HERE `18.52.70.012.632.5`, datos del `2025-11-22`), frente a la versión `251204` ya presente en el repo (mapas `18.49.56.023.631.5`, datos del `2025-07-16`). Son **~4 meses de diferencia real** en el mismo formato, mismo país, mismo fichero — el escenario ideal para diff dirigido.

El ZIP de mapas **no está cifrado** (a diferencia del resto del paquete OTA), por lo que ambos `.haftlt` se extraen directamente con `unzip -p`.

## Metodología

Para cada país se extrajeron los `.haftlt` de ambas versiones y se compararon:

1. **Cabecera** (campo a campo, offsets ya documentados en `haftlt_format.md`).
2. **Índice** (`0x200`→`sec1_start`).
3. **Sección 1** (`sec1_start`→`sec1_end`).
4. **Región media sin etiquetar** (`sec1_end`→`sec2_start`) — la única que crece.
5. **Secciones 2+3+4** (`sec2_start`→`sec4_end`) — tamaño constante entre builds.
6. **Región cola sin etiquetar** (`sec4_end`→EOF) — la otra región que crece.

Para las regiones que crecen se calculó el **prefijo común** y **sufijo común** byte a byte para localizar el punto exacto de inserción, en vez de asumir alineación fija.

## Resultado 1 — Todos los países crecieron (nunca decrecieron)

| País | Tamaño 251204 | Tamaño 260128 | Δ bytes | Δ % |
|---|---|---|---|---|
| AUT | 2,842,184 | 2,844,432 | +2,248 | 0.079% |
| BEL | 1,906,552 | 1,951,432 | +44,880 | **2.354%** |
| DNK | 2,290,340 | 2,293,500 | +3,160 | 0.138% |
| SPN | 5,755,556 | 5,759,744 | +4,188 | 0.073% |

Consistente con radares **solo añadidos** (nunca eliminados en neto) en ~4 meses — coherente con la realidad (los países europeos con radares fijos raramente los retiran, mayormente instalan nuevos). Bélgica destaca con un incremento de datos ~30× superior al resto en términos relativos, lo cual encaja con la alta densidad de cámaras/tramos de control belgas conocida.

## Resultado 2 — Corrección de campos de cabecera

- **Campo `0x40` (antes descrito como "constante `0x00031706`")**: en realidad es un **contador de versión de build** que se incrementa +1 entre releases: `0x00031706` (251204) → `0x00031707` (260128). No es una constante fija — el valor observado en sesiones previas solo coincidía porque ambas muestras pertenecían al mismo build.
- **Campo `0x4C` (antes descrito como "timestamp de compilación HERE, constante")**: en realidad codifica la **fecha/hora de `DATA_VERSION` en decimal puro** `YYYYMMDDHH`: `2025071509` (15 jul 2025, 09h) → `2025112102` (21 nov 2025, 02h). Tampoco es constante — coincidía en sesiones previas por la misma razón. Esto es información nueva y útil: da una forma directa de leer la fecha de datos sin parsear el string ASCII `DATA_VERSION_*`.
- **Campo `0x80` (`crc_or_hash`)** cambia de forma no trivial entre builds (288090382→288092476 en SPN) — sigue sin descifrarse su fórmula exacta, pero se confirma que depende del contenido (no es estático).

## Resultado 3 — Localización de las zonas de crecimiento real

Comparando región por región (país AUT, el más simple):

| Región | Tamaño 251204 | Tamaño 260128 | ¿Cambia tamaño? | Bytes distintos |
|---|---|---|---|---|
| Índice (`0x200`→sec1_start) | 58,469 | 58,469 | No | **0** (idéntico) |
| Sección 1 | 38,758 | 38,758 | No | **0** (idéntico) |
| **Región media** | 1,051,451 | 1,052,575 | **Sí (+1,124)** | prefijo común 6,767 B, luego diverge |
| Secciones 2+3+4 | 174,714 | 174,714 | No | 157,460/174,714 (90%) distintos |
| **Región cola** | 1,421,160 | 1,422,284 | **Sí (+1,124)** | sufijo común 348,214 B (el final coincide) |

Mismo patrón en DNK y SPN, con las secciones 2+3+4 manteniéndose de tamaño constante pero con ~90% de bytes distintos.

**Interpretación:**

- **Índice y Sección 1 apenas cambian** → confirma la conclusión de sesiones anteriores: no son el almacén principal de cámaras.
- **Secciones 2+3+4 mantienen tamaño exacto pero difieren en el 90% de sus bytes** → consistente con **IDs secuenciales/incrementales** que se renumeran en cascada cuando se inserta cualquier registro nuevo aguas arriba (ya se había observado que estas secciones contienen "IDs incrementales con bit 31 alternante"). Esto explica por qué un cambio pequeño (unos pocos KB) puede parecer que modifica el 90% del bloque: **no es la ubicación real del nuevo contenido**, es ruido de renumeración.
- **Solo dos regiones crecen de verdad**: la región media (`sec1_end`→`sec2_start`) y la región cola (`sec4_end`→EOF). Estas son las candidatas reales a contener los datos nuevos de cámara.
- El punto de inserción en la región cola está muy cerca del principio (todo el resto realinea con un sufijo común de cientos de KB) — el patrón de inserción es más limpio ahí que en la región media, donde casi todo el bloque posterior al prefijo común difiere (probablemente por renumeración interna similar a secciones 2-4, no solo por el contenido añadido).

## Mapa visual de bytes (Austria)

Para inspeccionar el fichero directamente (no solo por offsets numéricos) se generó una imagen donde cada píxel es el brillo medio de ~22 bytes consecutivos de `VIT_EUR_AUT.haftlt`, coloreada según la región de la estructura conocida a la que pertenece. De arriba a abajo = principio a final del fichero (1 fila ≈ 3.080 bytes).

| Build 251204 (datos 2025-07-16, 2,842,184 B) | Build 260128 (datos 2025-11-22, 2,844,432 B) |
|---|---|
| ![Mapa de bytes AUT build 251204](assets/haftlt_bytemap_AUT_251204.png) | ![Mapa de bytes AUT build 260128](assets/haftlt_bytemap_AUT_260128.png) |

**Leyenda de colores:**

| Color | Región | ¿Crece entre builds? | Conclusión |
|---|---|---|---|
| Gris neutro | Cabecera (`0x00`–`0x200`) | No | Metadatos: versión, fechas, offsets de sección |
| Azul | Índice (`0x200`→sec1_start) | No (0 B en 4 meses) | Descartada como almacén de cámaras |
| Verde/aqua | Sección 1 | No | Descartada como almacén de cámaras |
| Gris oscuro | Tramos sin cambios entre builds | — | — |
| **Rojo** | **Región media** | **Sí, +1,124 B en AUT** | Candidata real — contenido nuevo genuino |
| Amarillo | Secciones 2–4 | No (tamaño exacto igual), pero 90% de bytes distintos | IDs secuenciales renumerados en cascada — ruido, no la fuente |
| **Naranja** | **Región cola** | **Sí, +1,124 B en AUT** | Candidata real — inserción más limpia (gran sufijo idéntico al final) |

A simple vista el ruido gris moteado es indistinguible de datos aleatorios — así se ve cualquier tabla binaria compacta. Lo informativo es **dónde cambia el color entre las dos columnas**: azul y verde ocupan el mismo tramo exacto en ambas versiones (cero cámaras nuevas ahí en 4 meses reales); rojo y naranja son las únicas dos bandas que se alargan de una build a otra — ahí es donde algo se insertó de verdad. Script de generación: `render_bytemap2.py` (efímero en scratchpad de sesión, reconstruible con la metodología descrita arriba — extraer ambos `.haftlt`, localizar offsets de sección, downsample a bloques de N bytes por píxel coloreando por rango).

### Visualizador interactivo

Además de la imagen estática, existe [`tools/haftlt_viewer/generate_viewer.py`](../tools/haftlt_viewer/generate_viewer.py) — genera una página HTML autocontenida con minimapa navegable, hex dump en vivo e inspector u8/u16/u32 bajo el cursor, sobre las dos builds reales de un país. Uso e instrucciones completas en [`tools/haftlt_viewer/README.md`](../tools/haftlt_viewer/README.md).

**Importante:** el HTML que genera este script embebe ambos `.haftlt` completos en base64 (dato propietario de HERE sin pérdida) — por eso el script vive en el repo pero **su salida no se commitea nunca**. Genera bajo demanda y ábrelo localmente, o publícalo como Artifact efímero/privado para revisarlo puntualmente.

### Desempaquetado estructurado (CSV/JSON)

[`tools/haftlt_parser/parse_haftlt.py`](../tools/haftlt_parser/parse_haftlt.py) vuelca la tabla índice y las Secciones 1–4 a CSV/JSON en vez de hex crudo, y con `--other` localiza además los rangos exactos de las dos zonas candidatas (región media / región cola) en bytes de offset. Uso completo en [`tools/haftlt_parser/README.md`](../tools/haftlt_parser/README.md).

Ejecutado ya contra AUT/BEL/DNK/SPN (ambas builds) — salida en `HU/images/navi_eu/haftlt_parsed/` (fuera de git, junto a los `.haftlt` ya extraídos en `HU/images/navi_eu/haftlt_extracted/`). Igual que con el visualizador, ni los `.haftlt` ni la salida del parser se commitean — solo el script.

## Resultado 4 — Estructura visible en la región cola (candidata a tabla de umbrales de alerta)

Volcando los bytes insertados en la región cola de AUT a partir del offset donde se detecta contenido genuinamente nuevo, aparece una tabla muy regular de grupos de 4 bytes (little-endian `u16`+`u16`):

```
2a 00 b0 03   → (0x002a, 0x03b0)
00 00 b0 03   → (0x0000, 0x03b0)
80 00 b0 03   → (0x0080, 0x03b0)
00 01 b0 03   → (0x0100, 0x03b0)
80 01 b0 03   → (0x0180, 0x03b0)
00 02 b0 03   → (0x0200, 0x03b0)
80 02 b0 03   → (0x0280, 0x03b0)
00 03 b8 03   → (0x0300, 0x03b8)   ← el campo "alto" salta de 0x03b0 a 0x03b8
...
```

El campo bajo (`u16` izquierdo) **incrementa en pasos exactos de `0x80` (128)** dentro de cada grupo; el campo alto sube en saltos de `0x800` (2048) cada ~6-8 entradas. Este patrón — paso fijo pequeño repetido varias veces, seguido de un salto grande — tiene la forma de una **tabla de distancias/umbrales cuantizados**, no de coordenadas GPS (que no mostrarían esta regularidad aritmética tan limpia).

**Hipótesis de trabajo (no confirmada):** esta tabla podría corresponder a los umbrales de distancia de la progresión de alerta sonora `CT000009_LOW/MID/HIGH.wav` (3 niveles → posible relación con los saltos de grupo) o a parámetros de cálculo de velocidad media para tramos de control (**Section Control**, muy común en autopistas y túneles austríacos — encaja con que Austria muestre esta estructura con claridad). Pendiente de verificación cruzada.

## Resultado 5 — Tabla de nombres de calle (Pascal-strings UTF-8) confirmada en los 4 países

Dentro de la región cola, justo después de la zona de IDs de Secciones 3-4, hay una tabla de **cadenas de texto reales** (nombres de calles/carreteras) — el primer texto legible y con significado geográfico claro encontrado en cualquier `.haftlt` en toda la investigación.

**Formato confirmado (verificado byte a byte):** cada entrada es `[u8 longitud][bytes UTF-8, sin terminador]`, empaquetadas de forma consecutiva. Ejemplo real (España): el byte `0x12` (18) precede a `"Carretera del Prat"` (18 caracteres exactos), seguido del byte `0x1e` (30) precediendo a `"Calle del Doctor Tolosa Latour"` (30 caracteres exactos). El texto incluye acentos y eñes en UTF-8 (p. ej. `"Cañada de Velayos"`, `"Calle Quiñón"`) y nombres bilingües en Bélgica/Cataluña (`"Bd. Louis Mettewie/Mettewielaan"`, `"Carrer del Pare Manyanet"`).

**Confirmado en los 4 países probados** con un detector genérico (sin offsets hardcodeados por país — escanea buscando una cadena de ≥15 Pascal-strings válidas consecutivas):

| País | Nº de nombres | Rango de offsets (251204) |
|---|---|---|
| AUT | 9.849 | `0x2616f2`–`0x287050` |
| BEL | 7.563 (7.746 en 260128) | `0x1a0792`–`0x1bcdf6` |
| DNK | 23.067 | `0x1ade82`–`0x20c75c` |
| SPN | 20.290 | `0x4a9fae`–`0x52246e` |

### Tabla de registros de 16 bytes justo después

Inmediatamente tras el final de la tabla de nombres aparece: `[u32 record_count][12 bytes de relleno][record_count × registro de 16 bytes]`. Se verificó aritméticamente contra el tamaño real del fichero en los 4 países — encaja con una holgura de 0–2 bytes (redondeo/alineación) en todos los casos:

| País | `record_count` | Holgura final |
|---|---|---|
| AUT | 12.139 | 0 bytes |
| BEL | 7.875 (8.076 en 260128) | 0–2 bytes |
| DNK | 9.081 | 0 bytes |
| SPN | 23.528 | 2 bytes |

Cada registro de 16 bytes se probó como 8×`u16` LE. Patrones observados (sin confirmar su significado):
- `f1`, `f5`, `f7` son casi constantes dentro de bloques de registros consecutivos (posibles IDs de grupo/categoría).
- `f2`/`f3` alternan entre un valor real y el centinela `0xFFFF`, y ese valor real suele rondar el **índice del propio registro** (p. ej. registro 3000 → valores 2999/3001) — mismo patrón de "ID secuencial con slot alternante" ya visto en Secciones 3-4, solo que aquí a nivel `u16` en vez de bit31 de un `u32`.

**Hipótesis probada y REFUTADA:** que `f0` fuera un offset (relativo al inicio de la tabla de nombres) apuntando a la cadena asociada a ese registro. Se comprobó contra los offsets reales de las 20.290 cadenas de SPN: **0 aciertos en 30 registros probados.** La conexión nombre↔registro sigue sin resolverse — no dar por buena ninguna hipótesis sin este tipo de verificación cruzada explícita.

### Validación cruzada con la build nueva (Bélgica)

Bélgica es el único de los 4 países donde el conteo de nombres cambió entre builds (7.563 → 7.746, **+183 nombres nuevos**) — coherente con ser el país de mayor crecimiento real (2,35%). Los 183 nombres nuevos son calles belgas genuinas y verificables (p. ej. `"Bd. Louis Mettewie/Mettewielaan"`, `"Chaussée de Waterloo/Waterloosesteenweg"`). **No están todos al final de la lista** — aparecen tanto al principio (posiciones 0-9) como cerca del final (~7100-7740), lo que sugiere que la tabla se reordena/reindexa en cada build en vez de ser puramente append-only. AUT/DNK/SPN no ganaron ningún nombre nuevo en esta ventana de 4 meses (su crecimiento real está en otra parte del fichero).

## Resultado 6 — Bélgica dirigido: `f0` es un ID estable, la conexión nombre↔registro queda refutada por campo simple

Usando el caso de Bélgica (183 nombres nuevos por conteo, 157 por contenido exacto tras filtrar reordenaciones; 201 registros nuevos por conteo) se pudo por fin aislar de forma limpia los registros genuinamente nuevos, algo que la comparación posicional cruda no permitía (el prefijo/sufijo común entre `linked_records` de ambas builds es de solo 69/0 registros — la tabla se reordena/renumera casi por completo en cada build, igual que Secciones 2-4).

**Hallazgo clave — `f0` no es un índice posicional, es un ID persistente:** comparando el *conjunto de valores* (no la posición) de cada campo entre builds, `f0` tiene 7.875 valores casi únicos en la build antigua con un **97,4% de solapamiento** con la build nueva — es decir, es un identificador estable por registro que sobrevive a la reordenación. Filtrando por "`f0` nunca visto en la build antigua" aísla **204 registros** — coincide casi exactamente con el delta real de conteo (201). Este es el método correcto para localizar contenido genuinamente nuevo en tablas con renumeración en cascada, mejor que el diff binario prefijo/sufijo usado en Resultados 1-4.

**`f2`/`f3` son referencias a registros vecinos, no a nombres.** Ejemplo real: el registro con `f0`-nuevo en índice de array 3406 tiene `f3=3407`; el registro en índice 3407 tiene `f2=3406` — apuntan el uno al otro. Es un enlace bidireccional entre entradas adyacentes del array (consistente con segmentos de carretera conectados), y explica por qué `f2`/`f3` "rondaban el índice propio del registro" (nota de Resultado 5): no es azar, es literalmente el índice de su vecino.

**Prueba sistemática de conexión con nombres — REFUTADA:** sobre los 204 registros genuinamente nuevos, se probó cada uno de los 8 campos (`f0`-`f7`) como:
- Offset en bytes hacia la tabla de nombres, con 4 anclas distintas (`pool_start`, `pool_end`, `data_start`, `0`, en ambos sentidos +/-) → como mucho 9-85 aciertos de 204 contra *cualquier* nombre válido, pero **0 aciertos contra alguno de los 157 nombres nuevos**, en todas las combinaciones.
- Índice directo (0-based) en el orden de fichero de la lista de nombres → 3 campos caen 204/204 dentro de rango válido (`f1`, `f5`, `f7`), pero **0/204 apuntan a un nombre nuevo**, en los 8 campos.

Control estadístico: con 157/7.746 nombres nuevos (2,03%), 204 intentos al azar deberían acertar ~4,1 veces de media (simulación de 10.000 pruebas, rango 0-16). Obtener **0 aciertos de forma consistente en 8 campos × 5 anclas** es una desviación notable por debajo del azar — refuerza que no hay conexión directa por campo simple, no es solo "no se ha encontrado todavía".

**Conclusión:** la tabla de nombres y la tabla de registros de 16 bytes están estructuralmente confirmadas por separado, pero **no están enlazadas por ningún campo individual de forma directa**. Si existe relación, es indirecta — quizá vía una tercera tabla no identificada, vía las Secciones 2-4 (que sí comparten el patrón de ID+vecino), o los registros de 16 bytes son datos de topología de rutas sin relación con los nombres (que podrían servir a un propósito distinto, como búsqueda de direcciones/POI en vez de a la base de cámaras). No dar por sentado ningún vínculo entre ambas tablas sin repetir este mismo tipo de verificación cruzada.

**Nota (2026-07-10, `tools/camera_editor`):** medida la *cobertura* (no la exactitud) de la heurística de proximidad de posición sobre España: con ventana=5 registros alrededor del índice del `linked_record` de un `LINK_ID`, un **~89%** de una muestra de 2.000 `LINK_ID` tiene *algún* nombre de calle dentro de esa ventana (1774/2000 en build 251204, 1786/2000 en 260128). Esta cifra alta es consistente con la refutación de arriba, no la contradice: con 20.290 nombres repartidos entre 23.528 registros, casi cualquier posición tiene un nombre cerca — encontrar *un* candidato es fácil, que sea *el correcto* es lo que sigue sin confirmarse (y lo que el test de permutación puso en percentil 90, peor que el azar). La app muestra este candidato en su listado con un aviso explícito de que no es un enlace verificado.

## Estado de la investigación tras este análisis

**No se ha logrado extraer una coordenada GPS ni un formato de registro de cámara completo, insertable de forma segura.** Pero se ha avanzado material y metodológicamente:

1. **Existe ahora una segunda build real** para diffing futuro — activo reutilizable en sesiones posteriores (ubicación: `/Users/carlos/Downloads/NaU/Rio_MY22_EU`, o volver a descargar con `update_fetcher` del ecosistema gen5w).
2. **Descartadas definitivamente** como almacén de cámaras: tabla de índice y Sección 1 (crecimiento cero entre builds con +4 meses de datos reales).
3. **Confirmado que Secciones 2-4 usan numeración secuencial que se re-cascada** ante cualquier inserción — no son la fuente, son ruido de renumeración.
4. **Localizadas dos zonas de crecimiento real** (región media y región cola) que si contienen los datos de cámara nuevos.
5. **Corregidos dos campos de cabecera** mal etiquetados como "constantes" (`0x40`, `0x4C`) — en realidad codifican versión de build y fecha de datos.
6. Encontrada una **subtabla de valores regulares** en la región cola, con forma de tabla de distancias/umbrales — candidata a parámetros de alerta, no a coordenadas.
7. **Tabla de nombres de calle (Pascal-strings UTF-8) totalmente decodificada** en los 4 países, con extracción automática vía `tools/haftlt_parser/parse_haftlt.py` — primer texto legible con significado geográfico de toda la investigación.
8. **Tabla de registros de 16 bytes**: conteo estructuralmente confirmado; `f0` identificado como ID persistente por registro (97,4% estable entre builds — mejor método para aislar contenido nuevo en tablas con renumeración en cascada); `f2`/`f3` identificados como referencias bidireccionales a registros vecinos. **La conexión directa nombre↔registro vía campo simple queda descartada** tras prueba sistemática (8 campos × 5 anclas, 0 aciertos contra nombres nuevos frente a ~4 esperados por azar).

## Próximos pasos recomendados (orden de factibilidad)

1. **Buscar la conexión nombre↔registro por una vía indirecta**, ya que la directa está descartada: ¿hay una tercera tabla que actúe de puente? ¿Las Secciones 2-4 (que comparten el patrón ID+vecino con `linked_records`) referencian ambas? ¿O la tabla de 16 bytes no tiene relación con los nombres y sirve a otro propósito (topología de rutas, búsqueda de direcciones)? Usar de nuevo el caso dirigido de Bélgica (204 registros + 157 nombres genuinamente nuevos, ya aislados) en vez de repetir el análisis desde cero.
2. **Aplicar el método de "ID estable entre builds" (en vez de diff binario prefijo/sufijo) a las Secciones 2-4** y a las regiones media/cola de Resultados 1-4 — puede aislar contenido nuevo con mucha más precisión que el enfoque usado hasta ahora.
3. **Aislar un cambio de una sola cámara conocida.** Con una ventana temporal más corta entre builds (semanas en vez de meses) habría muchos menos registros nuevos que comparar.
4. **Diff binario del `.hafls`** (capa pan-europea) entre las dos builds con la misma metodología — buscar también ahí la tabla de nombres/registros de 16 bytes, y aplicar el mismo método de ID estable.
5. **Vía exploit físico (`gen5w`)**: si en algún momento se obtiene acceso físico al HU, extraer `DecryptToPIPE` + `decryption_key.der` y descifrar `appnavi.tar` permitiría leer el parser real de HERE — la única vía que resuelve esto con certeza total en vez de por inferencia. Ver [`gen5w_exploit_ecosystem.md`](gen5w_exploit_ecosystem.md).

## Camino alternativo ya operativo (sin resolver el formato nativo)

Si el objetivo final es "el sistema avisa de un radar en una ubicación nueva", el único camino **confirmado y sin incógnitas de formato** sigue siendo el documentado en [`speed_patch_workflow.md`](../.claude/memory/speed_patch_workflow.md): modificar `SPEED_PATCH.db` (SQLite estándar, editable con `sqlite3` sin ingeniería inversa adicional). La limitación conocida es que ese fichero controla **límites de velocidad por segmento (`LINK_ID`)**, no la posición georreferenciada de una cámara — no está confirmado si `appnavi` dispara la alerta sonora de radar a partir de estos datos o solo ajusta el límite mostrado en pantalla.
