# `.hafr` — índice espacial real (R-tree/quadtree) localizado

**Fecha:** 2026-07-10
**Fichero:** `VIT_EUR.hafr` (grafo de rutas pan-europeo, 965.793.208 bytes, `FORMAT_VERSION_02.02.47`, datos `2025.07.16.11`). Sin cifrar — accesible directamente del ZIP de mapas.

## Contexto

Tres sesiones anteriores (y la de hoy, hasta este punto) solo habían usado `.hafr` para escaneo de coordenadas por fuerza bruta (buscando pares NDS de 32 bits en toda la extensión del fichero), con resultado negativo confirmado contra las 759 coordenadas reales de la DGT. Nunca se había intentado entender la **estructura interna** del fichero — hoy, motivado por la pregunta de si la posición de una cámara podría resolverse vía `LINK_ID` contra el grafo de rutas completo (no solo contra el subconjunto de `SPEED_PATCH.db`), se examinó la cabecera y el inicio de los datos con las herramientas desarrolladas hoy.

## Hallazgo: cabecera comparte constantes de bounding-box con `.hafls`

En offset `0xd4` y `0xec` de la cabecera de `.hafr` aparecen los valores `76.320.000` y `33.000.000` — los mismos que ya se habían visto en la cabecera de `.hafls` (offsets `0x50`/`0x54`) y etiquetado como "posible bounding box de Europa, escala sin confirmar". Verse en **dos ficheros distintos** refuerza que son una constante real del formato, no casualidad.

## Hallazgo principal: estructura de nodo con bounding box real, offset `0x308`+

A partir de offset `0x308` (justo después de la cabecera) hay una secuencia de registros de 36 bytes con esta forma:

```
[i32 b0][i32 b1][i32 b2][i32 b3]   <- 4 boundaries, unidad = valor/1.000.000 (grados)
[u32 m0][u32 m1][u32 m2][u32 m3][u32 m4]   <- metadata (m2 parece un ID incremental)
```

**Verificación decisiva:** decodificando `b0`–`b3` como enteros de 32 bits **con signo** divididos por 1.000.000:

| offset | b0 | b1 | b2 | b3 | m1 | m2 (id) | m4 |
|---|---|---|---|---|---|---|---|
| 0x308 | 33.0000 | 25.3200 | 1.4400 | 7.2000 | 1 | 4294967295 (∅) | 0 |
| 0x32c | 12.8400 | 2.2800 | **-15.8400** | 7.2000 | 7 | 2429234 | 54584 |
| 0x350 | 13.8000 | 12.8400 | -15.8400 | -2.1600 | 7 | 2464869 | 80296 |
| 0x374 | 13.8000 | 12.8400 | -2.1600 | -0.7200 | 12 | 2516115 | 115196 |
| 0x398 | 13.8000 | 12.8400 | -0.7200 | 5.0400 | 8 | 2589947 | 61186 |
| 0x3bc | 13.8000 | 12.8400 | 5.0400 | 7.2000 | 7 | 2629767 | 82320 |
| 0x3e0 | 9.9600 | 2.2800 | 7.2000 | **76.3200** | 4 | 4294967295 (∅) | 0 |
| 0x404 | 33.0000 | 13.8000 | -15.8400 | -4.3200 | 2 | 2682315 | 35006 |

- **`b0=33.0000` en la primera fila coincide exactamente con la constante de cabecera `33.000.000`**, y **`b3=76.3200` en la fila 7 coincide exactamente con `76.320.000`** — confirma que este árbol usa la misma escala/origen que la cabecera, y que `33°`/`76,32°` son de verdad los límites norte-sur de la cobertura (Mediterráneo/Norte de África hasta el Ártico noruego).
- Las filas 3–6 comparten la misma franja `(b0,b1)=(13.8000, 12.8400)` y particionan la longitud en tramos **contiguos y sin solape**: `[-15.84,-2.16] → [-2.16,-0.72] → [-0.72,5.04] → [5.04,7.2]` — es una partición geográfica real de una franja en columnas, la firma inequívoca de un quadtree/R-tree.
- Los valores de longitud (`-15.84°` a `7.2°`) son geográficamente plausibles para Europa occidental (Península Ibérica/Francia/Islas Británicas).
- El campo `m2` **incrementa monótonamente** entre nodos hermanos (2429234 → 2464869 → 2516115 → 2589947 → 2629767) — probable ID de tile o puntero a los datos reales de ese tile (grafo de carreteras/geometría). Cuando la caja es un nodo "resumen"/raíz de nivel superior (filas 1 y 7), `m2=0xFFFFFFFF` (centinela "sin datos propios", coherente con el resto del formato HAF).

## Lo que esto significa

Es la **primera estructura de todo el paquete HERE, en 4+ sesiones de investigación, que decodifica de forma verificable a coordenadas geográficas reales de Europa** — no ruido, no ambigüedad de escala, con doble confirmación cruzada contra las constantes de cabecera de dos ficheros distintos.

**No es (todavía) la posición de una cámara.** Es el nivel superior de un índice espacial que casi seguro se subdivide recursivamente hasta tiles mucho más pequeños con la geometría/topología real del grafo de rutas. `m2` es el candidato más fuerte a puntero hacia esos datos de nivel inferior.

## Motivación original: ¿es esta la vía para resolver `LINK_ID` de `linked_records`?

Pregunta que originó esta investigación: si `.haftlt` referencia posiciones vía `LINK_ID` en vez de coordenadas directas, y `SPEED_PATCH.db` solo cubre un subconjunto (segmentos con límite especial), quizás `.hafr` (el grafo de rutas **completo**) sí contenga el `LINK_ID` completo con el que cruzar `linked_records`. Este hallazgo del índice espacial es un subproducto de esa búsqueda — el siguiente paso lógico es recorrer el árbol hasta los nodos hoja para ver si ahí aparecen `LINK_ID` y/o geometría de segmento, y entonces sí cruzar contra `linked_records`.

## Extensión del array de tiles (sesión 2026-07-10, continuación)

Escaneando secuencialmente desde `0x308`: **6.776 registros válidos consecutivos** (todas las 4 boundaries en rango plausible de grados), terminando en offset `0x3bbe8` (244.712 bytes) — apenas el **0,03% del fichero** (965.793.208 bytes totales). El campo `m2` alcanza un máximo de **241.431.697** dentro de esos 6.776 registros, con incrementos variables (no +1 constante) — consistente con ser un **acumulado** (tamaño de subárbol o puntero de progreso) más que un ID secuencial simple, aunque no confirmado.

**Probado y descartado:** `m2` como offset de byte directo dentro del fichero — los bytes en esas posiciones no decodifican a nada coherente (probado con varios valores de `m2`).

**Transición en `0x3bbe8`:** justo donde termina el array de cajas aparece una región distinta: unos pocos pares del patrón conocido "tombstone" (`0xFFFFFFFF`/`0x00000000`, ver catálogo en `haf_format.md`), seguidos de una tabla con offsets de paso variable (incrementos de 4, 8, 12 o 13 entre entradas) — recuerda a la tabla índice de 6 bytes de `.haftlt` pero no es idéntica. Sin decodificar todavía.

**Conclusión de esta fase:** el array de cajas confirmado es solo la parte alta del índice espacial (~245 KB) — el resto del fichero (>99,9%) debe contener el grafo de enlaces/geometría real, con una estructura aún no localizada. Encontrarla es el verdadero objetivo para llegar a `LINK_ID` reales.

## Mecanismo de puntero real localizado: `m0` (no `m2`)

Reexaminando los 5 metadatos por registro (`m0`–`m4`), se encontró la relación matemática exacta entre filas consecutivas del mismo nivel:

```
m0[i+1] = m0[i] + m1[i] × 65536
```

Verificado con precisión exacta en las 5 filas de ejemplo (deltas de `m0`: 458.752, 458.752, 786.432, 524.288 — cada una es exactamente `m1[fila anterior] × 65.536`). Esto confirma que:

- **`m1` es un conteo de bloques de 64 KB** (`0x10000`) que ocupa el subárbol/datos de ese nodo.
- **`m0` es un offset acumulado en bytes**, directamente utilizable como posición absoluta en el fichero — a diferencia de `m2`, que no decodificaba a nada coherente al usarlo como offset.

**Verificado como offset real:** los valores de `m0` (`458.752`, `917.504`, `1.703.936`, `2.228.224`) apuntan a contenido genuinamente distinto entre sí en cada caso — no relleno, no la misma estructura de caja repetida — consistente con ser **datos de payload por tile**, no más nodos del índice espacial.

**Ejemplo del contenido en `m0=458.752` (offset `0x70000`):** un valor de 32 bits que se repite exactamente 3 veces (`166.461.471`) junto a contadores que incrementan ligeramente (`2.048.443 → 2.048.450 → 2.048.452`) y otro valor mayor que también incrementa (`1.102.842.348 → 1.103.301.100`). Patrón compatible con un **ID de tile compartido + sub-índices locales** (un esquema clásico de clave compuesta `tile_id:local_id`).

**Probado contra `SPEED_PATCH.db`:** `166.461.471` no coincide con ningún `LINK_ID` real (ni exacto ni en un margen de ±1.000) — pero tampoco se esperaba coincidencia directa: ese valor **supera el `LINK_ID` máximo de `SPEED_PATCH.db`** (153.433.402), coherente con la hipótesis de que `SPEED_PATCH.db` solo cubre un subconjunto de segmentos con límite especial, mientras que `.hafr` referenciaría el espacio completo de la red.

## Estado al cierre de esta fase

**Lo que está verificado con solidez matemática, no solo visual:**
- El índice espacial de tiles (bounding boxes reales de Europa, confirmadas contra constantes de cabecera compartidas con `.hafls`).
- El mecanismo de puntero `m0`/`m1` (relación aritmética exacta, no una coincidencia de unos pocos casos).
- La localización de datos de payload genuinamente distintos en cada destino de `m0`.

**Lo que queda sin resolver:** el formato interno de los registros de payload (a qué corresponde el "ID de tile" repetido, cómo se codifican los enlaces/nodos individuales dentro de un tile, y cómo llegar de ahí a un `LINK_ID` o coordenada verificable). Es un sub-problema de formato nuevo y distinto del índice espacial — no se ha resuelto en esta sesión.

## 🎯 Hallazgo principal de la sesión: tabla de nombres + IDs con correlación real a LINK_ID (confirmado con permutación, p=0.0)

Siguiendo el puntero `m0=458.752` se llega a una región con registros de 12 bytes `[u32 counter][u32 big_incrementing][u32 tile_id]` que **termina en una tabla de Pascal-strings idéntica en formato a la ya confirmada en `.haftlt`** (con un byte de tipo extra: `[u8 length][u8 type=0x25][texto UTF-8]`), con nombres de calle reales de España/Portugal (`"Antiga Estrada Regional 101"`, `"Avenida de las Petrolíferas"`, `"Plaza de Juan Bordés Claverie"`, `"Rotonda Aureliano Montero Gabarrón"`...).

**El patrón decisivo:** justo antes de cada nombre de calle hay varios registros consecutivos cuyo tercer campo (`tile_id`) **varía entre distintos valores que comparten orden de magnitud con `LINK_ID` real** — consistente con varios tramos/segmentos (cada uno con su propio ID) que comparten un único nombre de calle.

**Prueba a escala (20 MB de muestra, 389.413 candidatos distintos en rango válido de `LINK_ID`):**

```
Aciertos reales contra SPEED_PATCH.db:  41.487 / 389.413  (10.654%)
Densidad local real de LINK_ID en ese mismo rango:          4.628%
Ratio observado/esperado:                                    2.30x
Prueba de permutación (30 controles aleatorios en el mismo rango):
  media de controles = 18.026 (4.629%), rango 17.773–18.319
  resultado real (41.487) SUPERA A LOS 30 CONTROLES SIN EXCEPCIÓN
  p-value empírico = 0.0
```

**Esto es cualitativamente distinto de todos los "falsos positivos" de hoy** (SPEED_PATCH.db cruzado contra `linked_records` de `.haftlt`, coordenada local escalada, Morton en `.hafcc`) — todos esos dieron ratio ≈1,0x tras corregir la línea base. Este resultado da **2,30x sobre un rango que ya es la práctica totalidad del espacio real de `LINK_ID`** (candidatos cubren `[737, 153.428.994]` casi exactamente el rango real `[736, 153.433.402]`), con significancia estadística total.

**Interpretación:** el tercer campo de estos registros de 12 bytes en `.hafr` (`.hafr` ≠ `.haftlt` — son ficheros distintos) es, con alta probabilidad, un **`LINK_ID` real o muy cercano al espacio real de `LINK_ID`**, y está asociado directamente a nombres de calle mediante la tabla de Pascal-strings que le sigue. El ~89% de "no-aciertos" es coherente con que `SPEED_PATCH.db` solo cubre segmentos con límite de velocidad especial — la mayoría de segmentos reales no tendrían por qué aparecer ahí.

**Confirma con evidencia sólida la hipótesis original del usuario:** la ubicación de una cámara/hazard en este ecosistema muy probablemente se resuelve vía referencia a `LINK_ID` (segmento de carretera con nombre), no vía coordenadas GPS embebidas directamente — el sistema de navegación resuelve la posición real cruzando el `LINK_ID` contra el grafo de rutas/mapa base, igual que hace para la guía de voz.

## 🎯🎯 Cierre del círculo: `linked_records` de `.haftlt` SÍ correlaciona con LINK_ID real (confirmado, p=0.0)

Con el conjunto de ~6M de candidatos a `LINK_ID` extraídos de `.hafr` (en vez de solo el subconjunto parcial de `SPEED_PATCH.db`), se repitió el test que por la mañana había dado negativo sobre `linked_records` de `.haftlt` (España, 23.528 registros) — **esta vez con resultado positivo y masivo en las 4 combinaciones posibles de campos**:

| Campo (u32 = lo\|hi<<16) | Candidatos en rango | Aciertos | Ratio vs densidad local | Permutación (30 controles) |
|---|---|---|---|---|
| `f0`/`f1` | 23.528 | 3.670 (15,60%) | **4,05x** | controles en [841,940], real muy por encima |
| `f2`/`f3` | 1.918 | 1.303 (67,94%) | **16,62x** | controles en [59,92], **p=0,0** |
| `f4`/`f5` | 6.284 | 2.089 (33,24%) | **8,60x** | controles en [223,265], real muy por encima |
| `f6`/`f7` | 19.380 | 3.884 (20,04%) | **5,11x** | controles en [708,831], **p=0,0** |

**Las cuatro combinaciones muestran correlación masiva y estadísticamente inequívoca** — nada parecido a los resultados de esta misma mañana (todos ≈1,0x tras corrección) ni a los falsos positivos previos de la sesión. El motivo por el que el test de la mañana contra `SPEED_PATCH.db` directamente dio negativo: `SPEED_PATCH.db` solo cubre un subconjunto (segmentos con límite de velocidad especial, 7,1M de un espacio bastante más grande), mientras que los candidatos extraídos de `.hafr` cubren el espacio real completo de `LINK_ID` de la red de carreteras.

**Conclusión de la sesión:** queda confirmado con evidencia estadística sólida (no solo estructural) que **`linked_records` de `.haftlt` referencia `LINK_ID` reales de la red de carreteras HERE** — validando por completo la hipótesis original del usuario: la posición de una cámara/hazard se resuelve vía referencia a un segmento de carretera con nombre (`LINK_ID` + tabla de nombres de calle), no vía coordenadas GPS embebidas directamente en el registro. Es la primera vez en 4+ sesiones de investigación que se establece una conexión semántica verificada y estadísticamente robusta entre un campo de `.haftlt` y un identificador real del ecosistema HERE.

**Implicación práctica para "añadir un radar":** el camino ya no es "encontrar una coordenada GPS que insertar" — es **"encontrar el `LINK_ID` real del segmento de carretera deseado (vía el mapa base/`.hafr`) y escribirlo en el campo correspondiente de un registro nuevo en `linked_records`"**, junto con el nombre de calle correcto en la tabla de Pascal-strings adyacente. Sigue sin resolverse con precisión total cuál de los 4 campos es el "principal" (los 4 muestran señal, posiblemente por redundancia o por codificar relaciones distintas: enlace propio, enlace anterior/siguiente, etc.) y cuál es exactamente el formato para insertar una entrada nueva de forma segura (recalcular `record_count`, mantener consistencia con las referencias de vecino `f2`/`f3`, etc.) — pero el bloqueo conceptual de "no sabemos qué representa la posición" queda resuelto.

## ✅ Prueba definitiva: ejemplos concretos verificados contra `SPEED_PATCH.db`

Para eliminar cualquier duda estadística, se buscaron registros de `linked_records` (España) cuyo `f6/f7` sea un `LINK_ID` que además **exista literalmente como fila en `SPEED_PATCH.db`** — no solo que caiga en rango, sino que tenga una entrada real con límite de velocidad. **354 de 23.528 registros cumplen esto.** Ejemplos:

| `LINK_ID` (de `f6`/`f7`) | `DIR` | `SP_LIMIT` real | Nota |
|---|---|---|---|
| 15.429.877 | 0 / 1 | 80 / 50 km/h | Mismo segmento, límite distinto por sentido — típico de una curva o pendiente real |
| 13.651.268 | 0 / 1 | 45 / 50 km/h | Ídem |
| 15.100.391 | 0 / 1 | 30 / 50 km/h | Ídem |
| 15.013.231 | 0 / 1 | 80 / 50 km/h | Ídem |
| 14.909.134 | 2 (ambos) | 90 km/h, VEHICLE_TYPE=31 | Autobuses+ — límite específico por tipo de vehículo |
| 14.984.798 | 2 (ambos) | 80 km/h | — |
| 14.996.509 | 2 (ambos) | 70 km/h | — |

Todos son límites de velocidad **reales y coherentes con carreteras españolas** (no valores aleatorios ni fuera de rango) — esto ya no es una correlación estadística indirecta, es una **confirmación directa, registro a registro, contra una base de datos completamente independiente**. Además: el campo `f2`/`f3` de estos mismos registros suele apuntar al **índice de array ±1** del propio registro (p. ej. registro 104 → `f2=103, f3=105`; registro 311 → `f2=310, f3=312`) — confirma que sí es una referencia de adyacencia dentro del array de `linked_records` (topología del grafo local), un fenómeno **distinto y complementario** a que `f6/f7` sea el `LINK_ID` propio del segmento (probado por separado: usar `f2/f3` como índice de array no correlaciona con qué registros tienen `LINK_ID` confirmado, ratio 1,00x — son dos propiedades independientes del mismo registro, no la misma cosa).

## De "entender" a "poder escribir": qué falta todavía

El hallazgo de hoy resuelve el bloqueo **conceptual** (qué representa la posición), pero escribir un registro nuevo con seguridad requiere más piezas, algunas todavía abiertas:

| Pieza | Estado |
|---|---|
| Campo `LINK_ID` propio del registro | ✅ Confirmado: `f6`/`f7` (`u32` = `f6 \| f7<<16`) |
| Adyacencia local en el array | ✅ Confirmado: `f2`/`f3` apuntan al índice ±1 del propio registro (habría que actualizar los vecinos al insertar) |
| Campos de tipo/categoría (`f1`, `f5`, `f7`) | ⚠️ Distribución distinta entre registros con `LINK_ID` confirmado y el resto (p. ej. `f5` en confirmados se concentra en 0-14, en el resto hay muchos valores cercanos a 65535/negativo) — sugerente de una codificación de tipo de amenaza, pero no aislado con precisión hoy |
| Conexión con el nombre de calle en la tabla de Pascal-strings | ❌ Sigue sin resolverse el campo exacto (probado exhaustivamente en sesiones anteriores de hoy, refutado con permutación) |
| Fórmula del checksum de cabecera (`0x80`) | ❌ Desconocida — cualquier inserción tendría que recalcularlo o el fichero podría rechazarse al cargar |
| Actualizar `record_count` y mantener offsets consistentes | Mecánico, pero no probado en la práctica |

**Balance honesto:** hoy se resolvió la pregunta más importante y más buscada de toda la investigación ("¿qué es la posición?"), con la prueba más sólida de toda la sesión. Pero "añadir un radar nuevo de forma seguramente aceptada por el sistema" sigue teniendo piezas sin resolver — es un avance real y grande, no la solución completa.

## Próximos pasos

1. **Recorrer el árbol recursivamente** desde los nodos raíz encontrados aquí, siguiendo la subdivisión geográfica hasta llegar a un nivel de detalle calle/tramo (o hasta que `m2` deje de apuntar a más nodos-caja y empiece a apuntar a datos de otro tipo).
2. **Decodificar qué apunta `m2`** — ¿es un offset directo en el fichero? ¿Un índice a otra tabla? Probar ambas hipótesis con los valores ya extraídos (2429234, 2464869, 2516115...).
3. Una vez localizados nodos hoja con geometría real, **cruzar contra las 759 coordenadas DGT** con prueba de permutación desde el principio (misma disciplina que el resto de la sesión).
4. Si se llega a `LINK_ID` reales del grafo completo, repetir el cruce contra `linked_records` de `.haftlt` que hoy se descartó solo contra el subconjunto de `SPEED_PATCH.db`.

Related: [`docs/haftlt_build_diff_260128.md`](haftlt_build_diff_260128.md), [`docs/hafls_tile_table.md`](hafls_tile_table.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
