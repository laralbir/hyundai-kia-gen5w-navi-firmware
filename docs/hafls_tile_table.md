# `.hafls` — tabla de tiles candidata (hallazgo inicial)

**Fecha:** 2026-07-09
**Fichero analizado:** `VIT_EUR.hafls` (capa de seguridad pan-europea, 84.004.788 bytes en la build `251204`, 83.903.656 en `260128` — el único fichero HAF de todo el paquete que **decrece** entre builds, en vez de crecer).

## Por qué se investigó

Tras confirmar que `.hafls` no comparte el layout de cabecera de `.haftlt` (offsets `0x94`-`0xac` dan valores sin sentido como límites de sección) ni contiene la misma tabla de nombres de calle Pascal-string (búsqueda exhaustiva con criterios relajados, sin resultado en 84 MB), se optó por un análisis de cabecera fresco en vez de forzar el esquema de `.haftlt`.

## Diff entre builds: casi todo el fichero cambia, salvo la cabecera temprana

Primer byte divergente: offset `0x32` (igual que en `.haftlt`, zona de fecha embebida). Sufijo común: solo 3.980 bytes al final — es decir, **prácticamente todo el fichero se reescribe entre builds**, mucho más agresivo que `.haftlt` (que conservaba tabla índice y Sección 1 intactas). Esto es coherente con ser un fichero *pan-europeo* consolidado: cualquier cambio en cualquier país de Europa puede cascadear por toda la estructura.

Sin embargo, una franja específica de la cabecera (offset `0x108` en adelante) **sí es idéntica entre ambas builds** — es la región analizada aquí.

## Hallazgo: patrón de tabla de tiles en offset `0x108`+

A partir de `0x108`, en pasos de 8 bytes (`[u32 a][u32 b]`), aparece un patrón extremadamente regular:

```
0x0108: a=0x00060000  b=0x00061000
0x0110: a=0x00180000  b=0x001e1800
0x0118: a=0x00300000  b=0x004e1801   <- a=STRIDE a partir de aquí
0x0120: a=0x00300000  b=0x007e2000
0x0128: a=0x00300000  b=0x00ae2001
0x0130: a=0x00300000  b=0x00de2002
0x0138: a=0x00300000  b=0xffff2003
0x0140: a=0x0000ffff  b=0x010e2004
0x0148: a=0x00300000  b=0x013e2005
...
```

**Observaciones confirmadas:**

1. **`a` es casi siempre una constante — `0x00300000` = 3.145.728 decimal = exactamente 3 MB.** Las dos primeras entradas (`0x108`, `0x110`) tienen `a = STRIDE/8` y `a = STRIDE/2` respectivamente — un posible "ramp-up" jerárquico (¿niveles de detalle 1/8, 1/2, 1/1, como una pirámide de tiles multi-resolución?).
2. Cuando `a` no es el stride, vale exactamente `0x0000FFFF` (65.535) — el mismo centinela "sin valor" que aparece en todos los demás formatos HAF analizados en este proyecto (`haftlt`, `linked_records`).
3. **El campo `b`, leído en hexadecimal, tiene sus 16 bits altos incrementando en pasos exactos de `0x30` (48)** cada vez que `a` es el stride completo: `004e → 007e → 00ae → 00de → 010e → 013e → 016e...`. Esto **no es casualidad**: `48 × 65536 = 3.145.728` — el mismo valor que el stride `a`. Es decir, `a` es literalmente "el incremento de los 16 bits altos de `b`, desplazado 16 bits a la izquierda" — ambos campos describen el mismo esquema de direccionamiento.
4. Los 16 bits bajos de `b` forman su propio contador agrupado: `2000, 2001, ..., 2007` (8 valores), salto a `2800, 2801, ..., 281f` (32 valores), salto a `3000, 3001, ...` — sub-índices dentro de cada "fila" de nivel superior, con tamaño de grupo variable (no fijo).

Este es el primer patrón encontrado en toda la investigación (incluyendo las 3 sesiones anteriores centradas en `.haftlt`, `.hafcc` y `.hafr`) que tiene la forma exacta de lo que la teoría NDS siempre pedía: **una tabla de tile-bases con un stride/escala explícito**, en vez de un intento de coordenada absoluta de 32 bits por punto (que ya se refutó repetidas veces con datos reales).

## Extensión de la tabla

Probando la hipótesis de que el campo de cabecera `0x80` (`464.688`, constante entre builds) es el **número de entradas** de esta tabla (8 bytes cada una, empezando en `0x108`):

```
tabla_end = 0x108 + 464688 × 8 = 0x38ba88 (3.717.768)
```

Inspeccionando los bytes alrededor de ese offset calculado, el patrón `a=STRIDE/a=0xFFFF` **efectivamente deja de cumplirse** y transiciona a una estructura distinta (pares de valores incrementando en pasos de `0x80`, el mismo patrón de "tabla de umbrales" ya visto en la región cola de `VIT_EUR_AUT.haftlt` y justo antes de la tabla de nombres en `VIT_EUR_BEL.haftlt`). La coincidencia aproximada del límite apoya la hipótesis, aunque la transición no es un corte perfectamente limpio — pendiente de verificación más precisa (podría haber unos pocos bytes de relleno/alineación en el borde).

## ⚠️ Corrección (mismo día, tras escanear la tabla completa): NO es uniforme

La caracterización inicial de arriba se basó en una muestra de solo ~30 entradas al principio de la tabla — **no es representativa del resto.** Al escanear las 464.688 entradas completas:

- El patrón limpio de `a=STRIDE` solo aparece en **24 entradas** al principio (el "ramp-up" de niveles jerárquicos ya descrito), no en toda la tabla.
- La inmensa mayoría de la tabla es **relleno vacío**: pares `a=0xFFFFFFFF, b=0x00000000` — bloques enteros de miles de entradas sin datos.
- Intercalados con el relleno hay **entradas reales dispersas**, cuyo primer campo (`a`) **crece monótonamente** a medida que se avanza por la tabla: `0x0019e58e → 0x00248c06 → 0x007388ae → 0x00762788 → 0x007f8e9a → 0x00a719cc → ... → 0x01a66160 → ...` — nunca decrece. El segundo campo (`b`) en estas entradas reales es un valor mucho más pequeño (decenas a miles), posiblemente un contador o tamaño asociado a esa clave.
- Más adelante en la tabla (entrada ~300.000) aparecen bloques de datos con estructura distinta otra vez, y cerca del final (~460.000) reaparece el mismo patrón de **ID + referencia a vecino** ya confirmado en `linked_records` de `.haftlt` (un registro cuyo campo `b` coincide exactamente con el campo `a` del siguiente).

**Interpretación revisada:** esto tiene más pinta de ser una **tabla hash dispersa indexada por clave** (la clave, `a`, creciendo monótonamente en las entradas ocupadas, con huecos vacíos donde no hay clave en ese rango) que de un índice de tiles uniforme y denso. Es un patrón genuinamente distinto al resto de lo visto en el paquete HERE hasta ahora — ni el índice de 6 bytes de `.haftlt`, ni las Secciones 2-4, ni `linked_records` tienen huecos de relleno tan masivos.

**Por qué sigue siendo prometedor pese a la corrección:** una clave creciente y dispersa es exactamente el patrón esperable de un **hash de coordenada de tile** (p. ej. un código Morton/Z-order de lat/lon cuantizado) usado como clave de tabla hash — de hecho más consistente con la teoría NDS real que un simple array denso. Pero confirmar esto requiere aislar qué rango de `a` cubre qué región geográfica, trabajo no completado en esta sesión.

## Estado: hallazgo estructural, NO decodificación de coordenadas

**Lo que se puede afirmar con confianza:**
- Existe una tabla de ~464.688 entradas de 8 bytes en la cabecera de `.hafls`, con un stride constante de exactamente 3 MB y un esquema de indexación de dos niveles (16 bits altos + 16 bits bajos de `b`).
- Esta tabla es idéntica entre las builds `251204` y `260128` — es una estructura fija/geográfica, no datos de contenido que cambien con actualizaciones de cámaras.
- Es estructuralmente el mejor candidato a "tabla de tile-bases" encontrado hasta ahora en todo el paquete HERE.

**Lo que NO se ha confirmado:**
- Qué representa cada tile en términos de coordenadas reales (no se ha intentado aún cruzar esta tabla contra un bounding-box conocido de Europa ni contra las coordenadas DGT).
- Si el resto de `.hafls` (los ~80 MB restantes, altamente cambiantes entre builds) usa esta tabla como base para deltas de posición de cámaras.
- La relación exacta entre los dos niveles del índice de `b` (16 altos / 16 bajos) y una jerarquía geográfica real (¿país? ¿región? ¿celda de rejilla?).

## ⚠️ Segunda corrección: los dos bloques densos también son patrones genéricos, no datos geográficos

Escaneo completo de las 464.688 entradas (no solo muestreo): la tabla se divide en 3 categorías (`empty`=79.504, `ramp`=1.247, `real`=383.937). Los dos tramos "reales" más largos —`[116.155:320.671]` (204.516 entradas) y `[320.674:464.688]` (144.014 entradas)— cubren el 75% de la tabla sin huecos, y en un primer vistazo su clave `a` parecía crecer monótonamente (falso: eso era un artefacto del muestreo cada 200 entradas, que solo capturaba una sub-secuencia local creciente).

Al examinar el bloque `[116.155:320.671]` entrada a entrada, resulta ser **dos patrones genéricos entrelazados en proporción 2:1**, ambos ya vistos en otros ficheros de este mismo paquete durante esta sesión:

1. **Tabla de umbrales ×128** (36.805 entradas, 18%) — el mismo patrón exacto encontrado antes en la región cola de `VIT_EUR_AUT.haftlt` y justo antes de la tabla de nombres en `VIT_EUR_BEL.haftlt`: un valor pequeño (<4096) junto a un valor múltiplo de 128.
2. **Contador pequeño + cuenta variable** (167.711 entradas, 82% del resto) — un valor que incrementa suavemente (deltas 4-20) junto a un valor pequeño (0-12) — variante del mismo tipo de tabla de cuantización/distancia.

**Conclusión revisada, más importante que el hallazgo original:** los patrones "prometedores" que van apareciendo repetidamente en distintos ficheros y offsets de este paquete (tabla de tombstones/relleno vacío, tabla de umbrales ×128, ID+referencia bidireccional a vecino) son con toda probabilidad **primitivas genéricas de serialización de la toolchain de HERE** — reutilizadas en múltiples contextos (`.haftlt`, `.hafls`) para propósitos distintos — no estructuras específicas de posición de cámara. Ni la tabla dispersa completa de `.hafls`, ni sus dos sub-patrones, muestran nada con forma de coordenada geográfica tras filtrar el ruido reconocido.

**Esto tiene una implicación práctica importante:** seguir escaneando bytes en busca de "el patrón que parece prometedor" sin poder ejecutar el parser real (`appnavi`, cifrado) tiene ya rendimientos claramente decrecientes — es la tercera vez en esta sesión que un patrón visualmente interesante resulta ser la misma familia de estructura genérica ya catalogada. El camino que queda con mayor probabilidad de éxito real es descifrar `appnavi` (exploit físico `gen5w`) para leer cómo el código real interpreta estos contenedores genéricos, en vez de seguir infiriendo semántica por inspección visual.

## Próximos pasos (revisados tras la corrección)

1. **Mapear los límites reales de cada tramo** de la tabla dispersa: dónde termina el ramp-up (~entrada 24), dónde empieza/termina cada racha de relleno vacío, dónde aparece el segundo tipo de datos (~entrada 300.000) y el patrón ID+vecino (~entrada 460.000). Sin esto, cualquier hipótesis de coordenada mezclará tipos de contenido distintos, como ya pasó una vez en esta misma sesión con la corrección de `haftlt`.
2. **Aislar solo las entradas "reales" (no vacías, no ID+vecino) y extraer su clave `a`** — comprobar si decodificada como Morton/Z-order (intercalado de bits de lat/lon cuantizados) cae dentro del bounding-box de Europa.
3. Una vez haya candidatos de coordenada, repetir el cruce contra las 759 coordenadas reales de la DGT **con prueba de permutación desde el principio** (lección aprendida hoy con `SPEED_PATCH.db` y la coordenada local escalada — no fiarse de un conteo bruto de coincidencias).
4. Alternativa más barata: en vez de seguir caracterizando esta tabla a ciegas, comparar esta misma región entre las builds `251204`/`260128` (aunque la mayor parte del fichero cambia, quizá los tramos de relleno vacío sean estables y ayuden a acotar límites de sección con más precisión que el análisis de una sola build).

Related: [`docs/haftlt_build_diff_260128.md`](haftlt_build_diff_260128.md), [`.claude/memory/haftlt_format.md`](../.claude/memory/haftlt_format.md), [`.claude/memory/project_radar_db.md`](../.claude/memory/project_radar_db.md)
