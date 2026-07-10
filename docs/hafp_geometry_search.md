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

1. **Decodificar el patrón de cabecera regular** (`1.667.235.840` + contador + `-16,7772°` + centinela + hash) — parece la pista más prometedora, análoga al índice de tiles de `.hafr`.
2. **Buscar la tripleta de `LINK_ID` en otra posición** respecto al nombre de calle (no necesariamente inmediatamente antes) — puede que en `.hafp` la relación nombre↔geometría pase por un nivel de indirección adicional (índice separado, no adyacencia directa).
3. **Verificar si el dato fonético (`'ka.Je&I_'s@n_'hwAn`) tiene su propia tabla separada** de la de coordenadas — de ser así, buscar la tabla de geometría en otra región del fichero.
4. Alternativa más eficiente: en vez de seguir con `.hafp` a ciegas, considerar si `.hafgsi` (Global Spatial Index, 274 MB, cabecera ya examinada con un patrón de tiles de stride `12.582.912` = 4×3MB) es un mejor punto de entrada — parece un índice más limpio y ya muestra estructura regular en sus primeros bytes.

Related: [`docs/hafr_spatial_index.md`](hafr_spatial_index.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
