# `.hafp` — búsqueda de geometría real por `LINK_ID` (en curso, sin resolver)

**Fecha:** 2026-07-10
**Objetivo:** el usuario pidió un editor visual con mapa real (pines en coordenadas reales, no solo lista de nombres). Dado que hoy se confirmó que `linked_records` de `.haftlt` referencia `LINK_ID` reales (ver [`docs/hafr_spatial_index.md`](hafr_spatial_index.md)), el siguiente paso lógico es encontrar dónde vive la geometría real (lat/lon) de cada `LINK_ID` — candidato: `.hafp` (HAF Partition, datos cartográficos principales, ~15 GB en 16 ficheros).

## Localización de la partición de España

`.hafp` está particionado geográficamente en 16 ficheros (`VIT_EUR.hafp`, `VIT_EUR.hafp01`–`VIT_EUR.hafp15`). Se tomó una muestra de 20 MB de cada partición numerada y se contaron coincidencias de palabras españolas (`Calle`, `Avenida`, `Carretera de`, `Ayuntamiento`):

| Partición | Coincidencias |
|---|---|
| **`hafp03`** | **17.571** ← España |
| `hafp01` | 209 |
| `hafp07` | 3 |
| `hafp02`, `hafp10` | 1 |
| resto (04,05,06,08,09,11-15) | 0 |

**`VIT_EUR.hafp03` (621.021.828 bytes) es la partición de España.** Confirmado además con un nombre de calle real completo: `"Calle de la Caracola"` en offset `209.098`, formato Pascal-string `[u8 length=20][u8 type=47][texto UTF-8]` — mismo esquema que `.haftlt`/`.hafr` con un byte de tipo extra.

## Diferencias estructurales con `.hafr`

- **La cabecera NO sigue el formato estándar** `FORMAT_VERSION_XX.XX.XX` de los demás ficheros HAF — es un fichero "parte" (`hafp03`, fragmento de una serie) sin la cabecera completa repetida.
- **El texto antes de un nombre de calle no son tripletas de `LINK_ID`** como en `.hafr` — parece ser datos de **transcripción fonética** (patrón con apóstrofes/guiones bajos tipo `'ka.Je&I_'s@n_'hwAn`, probablemente para el motor de voz/guiado).
- **Sí hay un patrón numérico regular en la cabecera**: un valor constante (`1.667.235.840`) se repite cada ~70 bytes, seguido de un contador que incrementa de 1 en 1 (`12.583.944` → `12.583.945`), y un **valor de longitud real y plausible: `-16,7772°`** (coherente con Canarias/costa atlántica africana, dentro del área que cubriría la partición de España+Canarias) — sugiere que esta cabecera SÍ contiene referencias geográficas reales, con una estructura de registro aún no descifrada del todo.

## Estado: sin resolver, requiere sesión dedicada

A diferencia de `.hafr` (donde el mismo patrón de "tripleta de 12 bytes + nombre" se decodificó y verificó en una sola sesión), `.hafp` tiene:
- Un formato de cabecera propio, distinto al resto de la familia HAF.
- Contenido de texto mucho más denso y distribuido (7,1 millones de fragmentos de texto solo en la partición base `VIT_EUR.hafp`, sin contar `hafp03`).
- Una estructura de registro junto a los nombres de calle que no es la misma tripleta de `LINK_ID` — parece ser datos fonéticos, no numéricos.

**No se ha logrado** en esta sesión extraer una coordenada real verificable, ni confirmar el vínculo `LINK_ID → geometría` dentro de `.hafp`. Es un hallazgo de localización (qué partición, qué formato de nombre) pero no de decodificación.

## Intentos adicionales (misma sesión) — todos sin señal

Tras localizar la partición de España, se probaron tres estrategias adicionales, ninguna con resultado:

1. **Patrón de caja delimitadora de 36 bytes** (el que sí funcionó en `.hafr`) aplicado a `.hafgsi` (Global Spatial Index, 274 MB): el primer "tramo largo" encontrado (2,77M registros) resultó ser una región enorme de **relleno con ceros**, no datos reales — falso positivo por criterio de filtro demasiado laxo. Con un filtro que exige magnitud no trivial (≥1°), no aparece ningún tramo contiguo real.
2. **Índice de tiles con stride ~12,58M** en la cabecera de `.hafgsi` (mismo tipo de mecanismo acumulativo que `m0`/`m1` en `.hafr`, campos distintos): solo cubre 512 entradas (~6 KB) antes de transicionar a otra estructura — el último valor acumulado (2.141.192.384) supera el tamaño del propio fichero, sugiriendo que podría ser un offset hacia una estructura mayor (los `.hafp` combinados, ~15 GB) pero no verificado.
3. **Búsqueda directa de `LINK_ID` reales conocidos** (ya confirmados contra `SPEED_PATCH.db`, p. ej. `13.651.268`, `14.909.134`) como valor `u32` literal dentro de `hafp03`: 2 de 7 aparecieron, pero el contexto alrededor no muestra ninguna estructura reconocible — consistente con coincidencia estadística (con 7 valores de 32 bits en 621 MB, la probabilidad de al menos 1 acierto por azar es ~14,5% por valor, así que 2/7 no es una señal por encima del azar).

## Conclusión de esta sesión

**Sin resolver.** A diferencia de `.hafr` (donde el mismo tipo de búsqueda dio una señal limpia en relativamente poco tiempo), `.hafp`/`.hafgsi` no han producido ningún ancla estructural fiable pese a probar cuatro enfoques distintos (patrón de tiles, búsqueda de cadena, índice acumulativo, búsqueda directa de valor). Es plausible que la geometría real requiera resolver primero un índice `LINK_ID`→tile que no se ha localizado, o que el camino más fiable sea leer el parser real (`appnavi`, cifrado) en vez de seguir infiriendo desde fuera — coherente con la conclusión ya alcanzada hoy para otros ficheros del paquete.

## Próximos pasos

1. ~~Decodificar el patrón de cabecera regular~~ → **hecho, sesión 2026-07-11 — descartado como fuente de coordenadas** (ver abajo).
2. **Buscar la tripleta de `LINK_ID` en otra posición** respecto al nombre de calle (no necesariamente inmediatamente antes) — puede que en `.hafp` la relación nombre↔geometría pase por un nivel de indirección adicional (índice separado, no adyacencia directa).
3. **Verificar si el dato fonético (`'ka.Je&I_'s@n_'hwAn`) tiene su propia tabla separada** de la de coordenadas — de ser así, buscar la tabla de geometría en otra región del fichero.
4. Alternativa más eficiente: en vez de seguir con `.hafp` a ciegas, considerar si `.hafgsi` (Global Spatial Index, 274 MB, cabecera ya examinada con un patrón de tiles de stride `12.582.912` = 4×3MB) es un mejor punto de entrada — parece un índice más limpio y ya muestra estructura regular en sus primeros bytes.

## Sesión 2026-07-11 — patrón de cabecera regular decodificado y descartado como coordenadas; confirmado el mismo byte de tipo `0x2f`=España que en `.hafr`

**Contexto:** tras localizar por primera vez la rama de España en `.hafr` (ver [`docs/hafr_spatial_index.md`](hafr_spatial_index.md)) usando la técnica de "el byte de tipo Pascal-string varía por país/idioma" (`0x2f`=España confirmado allí también), se retomó `.hafp03` con la misma lente.

**Confirmación cruzada del byte de tipo:** el Pascal-string de `"Calle de la Caracola"` (offset `209.098`) usa exactamente `type=0x2f` — el mismo valor confirmado hoy para España en `.hafr`. Es un dato de consistencia real entre dos ficheros de la familia HAF completamente distintos, refuerza que `0x2f` es un código de idioma/país estable en todo el ecosistema, no una coincidencia de una sesión.

**Nuevo dato: cada nombre va seguido inmediatamente de su transcripción fonética con `type=0xaf`** (`0x2f | 0x80`) — el bit alto parece ser un modificador "variante fonética" del mismo tipo base, no un tipo independiente. Confirmado en 10+ pares nombre/fonética consecutivos (`"Calle San Juan"` → `'ka.Je_'san_'xwan`, etc.). **12.696 nombres reales de tipo `0x2f` localizados en los primeros 20 MB de `hafp03`** — incluye topónimos de El Hierro (Canarias): `"Carretera de la Restinga"`, `"Ruta de Los Acantilados de El Hierro"`.

**El patrón de cabecera regular, decodificado — es un contador de dos series entrelazadas, no coordenadas:** el registro de 72 bytes que empieza con la constante `1.667.235.840` tiene 18 campos `u32`. Los campos 1 y 2 (el segundo de los cuales se había interpretado como la "longitud plausible −16,7772°") **no son un valor casi-constante con una lectura geográfica real** — son dos contadores que **alternan entre dos series intercaladas** (`12.583.944 / 12.583.945 / 12.583.945 / 12.583.944 / ...`, patrón `A,B,B,A` repetido, no monótono) — el resto de los 18 campos por registro también se agrupan en dos patrones que se repiten exactamente entre registros alternos. Es una estructura de **dos tablas entrelazadas** (posiblemente un centinela + su índice de continuación, el mismo tipo de primitiva ya catalogada en `.hafls`/`.haftlt`), no una tabla de coordenadas — el parecido con `-16,7772°` de la sesión anterior era, con alta probabilidad, coincidencia de un solo valor de muestra.

**Prueba sistemática y rigurosa (con controles), no solo lectura visual:** se extrajeron los 18 campos de **5.633 registros de 72 bytes** (primeros 20 MB de `hafp03`) y se probaron **las 306 combinaciones posibles de pares de campos** (`i≠j` de 18×18) contra el bounding-box real de El Hierro (lat 27,5–27,9°, lon −18,2 a −17,8°) en **4 escalas candidatas** (`/1e5`, `/1e6`, `/1e7`, NDS `90/2^30`) — **0 combinaciones con más de 5 coincidencias** en ninguna escala. Negativo limpio, sin necesidad siquiera de prueba de permutación (la señal ni siquiera supera el umbral mínimo para justificarla).

**Conclusión:** la pista que la sesión anterior marcó como "la más prometedora" para `.hafp` queda **descartada como fuente de coordenadas** tras decodificación completa — es un mecanismo de conteo/indexación genérico, coherente con el catálogo de primitivas ya identificado en otros ficheros HAF de este mismo paquete. La tabla de nombres+fonética de `.hafp03` es densa y real (12.696 nombres en 20 MB), pero, igual que en `.hafr`, **no lleva un identificador o coordenada numérica adyacente reconocible** — el vínculo nombre↔geometría, si existe en este fichero, requiere un nivel de indirección todavía no localizado.

Related: [`docs/hafr_spatial_index.md`](hafr_spatial_index.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
