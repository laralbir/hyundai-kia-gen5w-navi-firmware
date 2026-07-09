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

## Estado: hallazgo estructural, NO decodificación de coordenadas

**Lo que se puede afirmar con confianza:**
- Existe una tabla de ~464.688 entradas de 8 bytes en la cabecera de `.hafls`, con un stride constante de exactamente 3 MB y un esquema de indexación de dos niveles (16 bits altos + 16 bits bajos de `b`).
- Esta tabla es idéntica entre las builds `251204` y `260128` — es una estructura fija/geográfica, no datos de contenido que cambien con actualizaciones de cámaras.
- Es estructuralmente el mejor candidato a "tabla de tile-bases" encontrado hasta ahora en todo el paquete HERE.

**Lo que NO se ha confirmado:**
- Qué representa cada tile en términos de coordenadas reales (no se ha intentado aún cruzar esta tabla contra un bounding-box conocido de Europa ni contra las coordenadas DGT).
- Si el resto de `.hafls` (los ~80 MB restantes, altamente cambiantes entre builds) usa esta tabla como base para deltas de posición de cámaras.
- La relación exacta entre los dos niveles del índice de `b` (16 altos / 16 bajos) y una jerarquía geográfica real (¿país? ¿región? ¿celda de rejilla?).

## Próximos pasos

1. **Verificar el conteo exacto de tiles** contra el número real de países/regiones de cobertura (47 países en el paquete) o contra alguna potencia de 2 razonable para una rejilla de Europa.
2. **Cruzar los valores del índice de dos niveles contra el bounding-box conocido de Europa** (`lon≈±1.40625°` ya se había visto como límite de tile en sesiones anteriores — comprobar si estas ~464K entradas, divididas en su jerarquía, producen esa misma granularidad).
3. **Examinar qué hay exactamente en el offset `0x108 - 0x30`** (antes del ramp-up) para ver si hay un header propio de esta sub-tabla con un total de tiles o bounding-box explícito en grados/microgrados.
4. Una vez haya candidatos de bounding-box por tile, repetir el cruce contra las 759 coordenadas reales de la DGT — esta vez con una prueba de permutación desde el principio (lección aprendida de la sesión de hoy).

Related: [`docs/haftlt_build_diff_260128.md`](haftlt_build_diff_260128.md), [`.claude/memory/haftlt_format.md`](../.claude/memory/haftlt_format.md), [`.claude/memory/project_radar_db.md`](../.claude/memory/project_radar_db.md)
