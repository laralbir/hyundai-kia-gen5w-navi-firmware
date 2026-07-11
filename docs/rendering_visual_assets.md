# Assets visuales y renderizado del mapa — `.skn`, `VIT_EUR_CE_THEME_IMAGE.bin`, `.hafmma` de tema

**Fecha:** 2026-07-10/11
**Objetivo:** ángulo distinto a las sesiones anteriores (que buscaban coordenadas/geometría de `LINK_ID` en `.hafr`/`.hafp`, ver [`hafr_spatial_index.md`](hafr_spatial_index.md) y [`hafp_geometry_search.md`](hafp_geometry_search.md), con rendimientos decrecientes). Aquí se investiga el **"cómo se ve"** el mapa en pantalla: temas de color, iconografía, e imágenes de guiado — no el "dónde está cada calle". Primer hallazgo de toda la investigación que produce **imágenes reales, visualizables**, extraídas directamente del paquete — y el primero que llega a un **formato de píxel completamente resuelto y verificado por render** (el atlas de texturas `VIT_EUR_CE_THEME_IMAGE.bin`), no solo estructura de contenedor.

## Resumen de hallazgos

| Fichero | Formato interno | Contenido |
|---|---|---|
| `RES/SKIN/VIT_EUR_CE_THEME_*.skn` (5 archivos, 121.492 B c/u) | Propio, magic `REDSKIN#` | Manifiesto de tema: referencias a 3 recursos externos + tabla de ~800+ registros de estilo de 32 bytes |
| `RES/SKIN/VIT_EUR_CE_THEME_IMAGE.bin` (84,5 MB) | Propio, índice de 64 bytes/registro | 🎯 Atlas de texturas RGB/RGBA sin comprimir, **pixel format resuelto y verificado por render** |
| `MAP/VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma` (~780 KB c/u) | HAF + tabla de offsets + **WebP embebido** | 136 imágenes reales de guiado de salida/carril (ilustraciones esquemáticas 3D), 3 paletas de color |
| `MAP/VIT_EUR_SYMBOL_48.hafmma` (19,5 MB) | HAF + tabla de offsets, contenido NO es WebP/PNG | Iconos de POI/símbolos de mapa — **confirmado que NO es ASTC** (0 coincidencias de magic); RGBA sin comprimir organizado por categoría con nombre (ej. `LAND\COMMON`) |
| `MAP/VIT_EUR_3D_LANDMARK_ASTC.hafmma` (379 MB) | HAF + tabla de offsets + **ASTC embebido** | 🎯🎯 **ASTC confirmado y decodificado**: texturas reales de fachadas de edificios para landmarks 3D (ventanas, columnas, tejados) |
| `GlobalImage/**/*.png` | PNG estándar | Iconos de UI ya directamente visualizables sin ingeniería inversa (banderas, popups, límites de velocidad, peajes, viñetas) |

## 1. `.skn` — formato de tema/skin

Cabecera: magic ASCII `REDSKIN#` (8 bytes) + `01 0e cc cc` + padding a cero hasta offset `0x20`.

A partir de `0x20` hay dos bloques de 16 bytes (8×`u16`) que parecen rectángulos `(x, y, w, h)` — posiblemente cajas de layout de UI antes de la tabla de recursos:
```
0x20: (278, 502, 127, 41, 121, 84, 32, 178)
0x40: (286, 502, 132, 41, 192, 179, 32, 185)
```

Después, tres referencias a ficheros externos como texto **UTF-16LE**, cada una alineada a un offset fijo:

| Offset | Referencia |
|---|---|
| `0x60` | `VIT_EUR_CE_THEME_IMAGE.bin` — atlas de texturas 2D |
| `0xc4` | `model_sym.bin` — modelos 3D de símbolos (no está en el paquete EUR actual; puede ser interno a otro contenedor) |
| `0x128` | `model_bld.bin` — modelos 3D de edificios (landmarks) |
| `0x190` | `description` (metadato, sin datos asociados vistos) |

### Tabla de estilos (offset ~`0x3e0` en adelante)

**807 registros consecutivos** de 32 bytes cada uno (`IDs` de estilo `19`–`825`), con un patrón muy regular de 16 campos `u16`:

```
[cccc][0000][0000][TYPE][0000][cc00][cccc][ID][0001][0001][REF][0001][cccc][0000][0000][0000]
```

- `0xCCCC` (52.428), `0xCC00` (52.224): **constantes sentinela** que delimitan el registro (mismo valor que aparece en la cabecera del fichero — probablemente un "magic" de alineación/versión de la toolchain HERE, ya visto como patrón genérico en otros ficheros HAF de esta investigación).
- `TYPE`: normalmente `5377` (`0x1501`), a veces `15873` (`0x3E01`) o `3585` (`0x0E01`) — probable código de categoría de estilo (p. ej. tipo de vía, tipo de POI, tipo de área).
- `ID`: **contador secuencial estricto**, incrementa exactamente en 1 por registro — es el índice/clave del registro dentro de la tabla.
- `REF`: campo que **no es secuencial**, salta en incrementos variables (ej. `8772 → 8773 → 8777 → 8976 → 8977...`) — candidato fuerte a **índice hacia un color, sprite o entrada del atlas de texturas** (`VIT_EUR_CE_THEME_IMAGE.bin`), de forma análoga al mecanismo de puntero ya visto en `.hafr` (`m0`/`m1`).

Al final de estos 807 registros (offset `0x68c0`), la estructura cambia a un layout más compacto mantiacndo los mismos sentinelas `0xCCCC` — una segunda sección de tabla, sin decodificar, que ocupa los ~94 KB restantes del fichero.

**Interpretación de conjunto**: `.skn` es el fichero de **configuración de tema** — enlaza IDs de estilo (posiblemente por tipo de feature del mapa: autopista, calle secundaria, agua, parque, edificio, POI) con referencias a recursos visuales (texturas 2D del atlas, modelos 3D de edificios/símbolos). Los 5 archivos (`BLACK`, `SIMPLEBROWN`, `SIMPLENIGHT`, `SIMPLEWHITE`, `SMARTBROWN`) comparten exactamente el mismo tamaño (121.492 B) — coherente con ser la **misma tabla de IDs de estilo con distintos valores de `REF`/color** por tema, no estructuras distintas.

## 2. `VIT_EUR_CE_THEME_IMAGE.bin` — atlas de texturas (84,5 MB) 🎯 RESUELTO

Cabecera propia (no sigue el formato HAF estándar): primer `u32` = `420` — número de entradas del índice.

**Índice de 64 bytes por registro**, a partir de offset `0x10` (confirmado localizando la posición exacta de un contador secuencial `1,2,3,...` por búsqueda de fase, no asumido):
```
[24 bytes reservados/cero][u32 seq][u32 size][u32 reservado][u32 data_offset][28 bytes reservados/cero]
```
`size` es el tamaño exacto en bytes del payload de esa textura, y `data_offset` es un **offset absoluto de fichero** (no relativo al índice) — verificado con precisión exacta: `data_offset[i] + size[i] == data_offset[i+1]` para toda la muestra probada. El primer `data_offset` (26.896 = `0x6910`) coincide exactamente con el final calculado del índice (`0x10 + 420×64`).

**Cada payload de textura tiene a su vez una cabecera propia de 32 bytes (8×`u32`)**, verificada exacta contra los datos reales:
```
[u32 0x30][u32 0x31][u32 width][u32 height][u32 channels][u32 mip_levels][u32 gl_format][u32 gl_format2]
```
- `channels=3` → `gl_format=6407` = **`GL_RGB`** (enum real de OpenGL, `0x1907`)
- `channels=4` → `gl_format=6408` = **`GL_RGBA`** (enum real de OpenGL, `0x1908`)
- `mip_levels` = `log2(max(width,height)) + 1` exacto en todos los casos probados (ej. 512×512 → 10 niveles, 32×32 → 6 niveles) — **cadena de mipmaps completa hasta 1×1**, coherente con carga directa a GPU vía Mesa3D/OpenGL ES sin decodificación en tiempo real (confirma la hipótesis de `COPYRIGHT.TXT`).
- Los 32 bytes de cabecera van seguidos directamente de `width×height×channels` bytes de píxeles sin comprimir (más los niveles de mip subsiguientes, no verificados individualmente pero coherentes en tamaño total).

**Verificado renderizando 5 texturas reales** (128×128 RGB, 256×128 RGB, 32×32 RGB, 512×512 RGB, 64×64 RGBA) — todas decodifican a imágenes visualmente coherentes con una UI de navegación: una de 512×512 es un **gradiente de cielo verdoso con nubes** (fondo de panel, probablemente modo "Eco"), otra 128×128 es un panel casi blanco liso (fondo de UI). Confirma sin ambigüedad el formato — ya no es hipótesis.

## 3. `.hafmma` de renderizado — `VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma` 🎯

**El hallazgo principal de esta sesión.** Cabecera HAF estándar (`FORMAT_VERSION_01.04.04`, `DATA_VERSION_2023.06.01.17`). A partir de offset `0x100` hay una **tabla de 204 offsets `u32`** (sentinela `0xFFFFFFFF` en la primera entrada), que indexan registros de tamaño variable a partir de `base = 0x100 + 204×4 = 0x430`.

**Cada registro es (o contiene) una imagen WebP real** (`RIFF....WEBP`, algunas con chunk `ALPH` de canal alfa). Se extrajeron y decodificaron con éxito **136 imágenes WebP** de cada uno de los 3 ficheros (LATTE/MILK/MOCHA), verificado con Pillow y `dwebp`.

### Contenido de las imágenes — confirmado visualmente

Las imágenes son **ilustraciones esquemáticas en perspectiva 3D de bifurcaciones de autopista/salida** (una calzada recta con una rampa curva desviándose), del tipo que se muestra en el panel de "próxima maniobra" de un sistema de navegación — no fotos reales (eso es el rol de `VIT_EUR_JunctionExitView_BI.hafmma`, 295 MB, "BI" = probablemente *Bird's-eye Image* o *Bitmap Image*, fotos reales de salidas).

- Tamaño dominante: **640×720 px** (70 de las 136 imágenes) — el fondo/escena completa de la bifurcación.
- Tamaños menores (188×361, 188×362, 375×451, etc.) — variantes o recortes, algunas con **canal alfa real**: una de ellas (`188×361`, tema LATTE, imagen aparentemente en blanco al aplanar sobre fondo blanco) resultó ser un **overlay de resalte de carril con transparencia** — al componer sobre un fondo gris se revela un trazo de carril en degradado blanco, pensado para superponerse sobre la escena base y resaltar la ruta a seguir.
- **Confirmado el propósito de las 3 paletas**: mismo índice de imagen (p. ej. `000`) entre LATTE/MILK/MOCHA muestra la **misma escena con distinto grado de contraste/luminosidad** — LATTE (fondo tierra/beige, tono día), MILK (fondo casi blanco/gris claro), MOCHA (tonos más oscuros/cálidos, noche/atardecer) — coincide exactamente con la descripción ya registrada en memoria ("paletas de renderizado: intensidades de contraste").

Esta es la **primera vez en toda la investigación** (5+ sesiones) que se extrae y visualiza contenido real y con significado claro del paquete de mapas, más allá de nombres de calle y límites de velocidad en texto/SQLite.

## 4. `.hafmma` de símbolos — `VIT_EUR_SYMBOL_48.hafmma` (19,5 MB) — ASTC descartado

Mismo esqueleto de contenedor (cabecera HAF + tabla de offsets a partir de `0x100`), pero **el contenido de los registros no es WebP ni PNG** — no se encontró ningún magic `RIFF`/`\x89PNG` en todo el fichero. Cabecera: campo en `0x74`=21, `0x88`=255 (posibles sub-conteos), tabla de offsets con deltas grandes (~1,2 MB) al principio y luego mucho más pequeños (~10 KB) — sugiere una tabla jerárquica de dos niveles (grupos de iconos → iconos individuales), análoga a la de `.hafls` ya documentada.

**❌ Hipótesis ASTC descartada, con evidencia directa**: cero coincidencias del magic ASTC estándar (`13 AB A1 5C`) en todo el fichero — a diferencia de `VIT_EUR_3D_LANDMARK_ASTC.hafmma` (ver más abajo), donde el mismo magic aparece 342 veces solo en los primeros 2 MB. En su lugar, el primer bloque de datos (offset `0x154`) contiene una **cadena de texto legible**: `"LAND\COMMON"` — un nombre de categoría/carpeta de iconos — seguida de una tabla de sub-entradas con pares de dimensiones pequeñas (del orden de 30-70 px, típico de iconos de POI) y, más adelante en el fichero, **secuencias largas de valores RGBA de 4 bytes idénticos repetidos** (ej. `80 80 80 ff` gris, `11 27 65 ff` azul, `0a 87 2d ff` verde, con transiciones a blanco/transparente en los bordes) — la firma inconfundible de **rellenos de color plano sin comprimir con antialiasing**, coherente con iconos/marcadores de POI de color sólido. **Conclusión: es un atlas RGBA sin comprimir organizado por categoría con nombre, no ASTC** — mismo principio que `VIT_EUR_CE_THEME_IMAGE.bin`, pero con un esquema de índice por categoría en vez del índice plano de 64 bytes/textura.

**Intento de reconstrucción raster — sin resolver.** Se intentó reconstruir el icono como imagen 2D asumiendo ancho fijo (probando 48 px, sugerido por el propio nombre del fichero, y un barrido sistemático de 192 offsets candidatos alrededor del run de color verde) — **ningún offset probado produjo una imagen coherente** (todos dan bandas horizontales, señal de desalineación de stride). La longitud real del run de color sólido encontrado (94 repeticiones de 4 bytes) tampoco es múltiplo limpio de 48. Los campos de la tabla de sub-entradas cercana a `"LAND\COMMON"` (valores tipo `114/40/38`, `140/41/35`) se probaron como candidatos a `(stride, width, height)` sin que ninguna combinación encajara de forma consistente entre entradas. **Queda como pendiente genuino** — la existencia de datos RGBA reales está confirmada, pero no el ancho/stride exacto por icono.

## 4b. `VIT_EUR_3D_LANDMARK_ASTC.hafmma` (379 MB) — ASTC confirmado y decodificado 🎯🎯

Muestreados los primeros 2–10 MB (lectura parcial de la entrada ZIP, sin extraer los 379 MB completos). Cabecera HAF estándar (`DATA_VERSION_2025.06.11.15`), campo `0x74`=7.524 (probable nº de landmarks/texturas).

**Confirmado sin ambigüedad**: el magic estándar de fichero ASTC de un solo nivel, `13 AB A1 5C` (little-endian de `0x5CA1AB13`, el magic real de la especificación Khronos ASTC), aparece **342 veces en los primeros 2 MB** (1.451 en los primeros 10 MB). Decodificando la cabecera ASTC completa (magic + block_x + block_y + block_z + xsize[3] + ysize[3] + zsize[3], 16 bytes) de las primeras 8 ocurrencias:

```
block 10×10×1, tamaños: 256×256 → 128×128 → 64×64 → 32×32 → 16×16 → 8×8 → 4×4 → 2×2 (→ 1×1 implícito)
```

Cadena de mipmaps completa, formato de bloque 10×10 (uno de los modos de compresión ASTC de tasa de bits más baja, ~1,2 bpp).

**🎯 Decodificado con éxito**: se compiló `ARM-software/astc-encoder` desde fuente (no disponible vía Homebrew; requirió instalar `cmake` y compilar con soporte NEON) y se decodificaron varias texturas base de 256×256 con `astcenc -dl`. **El contenido son texturas reales de fachadas de edificios** — ventanas en fila, columnas clásicas, molduras, tejados y puertas, en el estilo de mapeado UV típico de un atlas de fachada para un modelo 3D de landmark (edificio emblemático renderizado en 3D en el mapa, p. ej. un palacio o edificio institucional europeo con planta de patio visible en una de las texturas). Confirma con total certeza que `.hafmma` con sufijo `_ASTC` contiene las **texturas reales aplicadas a los modelos 3D de landmarks** del mapa — el primer contenido 3D/arquitectónico real visualizado de toda la investigación.

## 5. `GlobalImage/**/*.png` — ya directamente accesibles

No requieren ingeniería inversa: son PNG estándar, extraíbles directamente del ZIP. Confirman visualmente lo ya documentado en `haf_format.md`:
- `SpeedLimit/speed_limit_{0-9}.png` y `_red_{0-9}.png` — dígitos individuales compuestos en pantalla para formar el círculo de velocidad.
- `Popup/`, `Toll/`, `Vignette/` — iconos de aviso con variantes `day`/`night` y `_d` (probable "disabled"/"dark").
- `NationFlag/` — banderas de países/regiones para selección de país en el buscador.

## Próximos pasos

~~1. Resolver el pixel format exacto de `VIT_EUR_CE_THEME_IMAGE.bin`~~ → **resuelto**: índice de 64 B + cabecera de textura de 32 B con enums reales de OpenGL (`GL_RGB`/`GL_RGBA`), verificado renderizando 5 texturas reales.
~~2. Confirmar si `VIT_EUR_SYMBOL_48.hafmma` es ASTC~~ → **resuelto, descartado**: 0 coincidencias de magic ASTC; es RGBA sin comprimir organizado por categoría con nombre (`LAND\COMMON`), pero el stride/ancho por icono no se logró aislar (ver intento fallido en la sección 4).
~~3. Instalar/compilar un decodificador ASTC~~ → **resuelto**: `ARM-software/astc-encoder` compilado desde fuente y usado con éxito para decodificar texturas reales de `VIT_EUR_3D_LANDMARK_ASTC.hafmma` (fachadas de edificios landmark).

**Lo que sigue abierto:**

1. **Aislar el stride/ancho exacto por icono en `VIT_EUR_SYMBOL_48.hafmma`** — confirmado que hay datos RGBA reales (colores planos con antialiasing en los bordes), pero el barrido de offsets candidatos con ancho fijo (incl. 48 px, sugerido por el nombre del fichero) no produjo ninguna imagen coherente. Probablemente el ancho varía por icono (codificado en la tabla de sub-entradas junto al nombre de categoría) en vez de ser fijo — pendiente de decodificar esa tabla con precisión antes de reintentar el raster.
2. **Cruzar el campo `REF` de la tabla de estilos de `.skn`** contra el campo `seq`/`type` del índice de `VIT_EUR_CE_THEME_IMAGE.bin` — si coinciden en rango/distribución, confirmaría el enlace estilo→textura.
3. **Decodificar la segunda sección de `.skn`** (tras offset `0x68c0`, ~94 KB, mismo sentinela `0xCCCC` pero layout distinto) — no abordado en esta sesión.
4. **Decodificar más texturas de `VIT_EUR_3D_LANDMARK_ASTC.hafmma`** a escala (las 7.524 declaradas en cabecera) y, si se aísla el índice landmark→texturas, cruzarlas con nombres de edificio conocidos.
5. Extraer y decodificar `VIT_EUR_3D_MODEL_SYM.hafmma` / `VIT_EUR_3D_MODEL_SYM_CCIC.hafmma` (modelos 3D referenciados desde `.skn` como `model_sym.bin`/`model_bld.bin`) — el índice de offsets de estos ficheros **no sigue el mismo esquema monótono** que los ficheros de imagen (probado y descartado en esta sesión); es un formato de malla 3D (vértices/UV/índices) genuinamente distinto, sin explorar todavía.

## Herramienta de visualización

[`tools/map_render_viewer/`](../tools/map_render_viewer/) genera una galería HTML autocontenida con los tres formatos resueltos arriba (guiado WebP, atlas RGB/RGBA, landmarks ASTC), trabajando directamente sobre el ZIP de mapas. Verificado contra el ZIP real: 500 imágenes embebidas (80 del atlas + 408 de guiado + 12 de landmarks) con los valores por defecto. El HTML generado no se commitea (ver aviso en el README de la herramienta).

## Nota sobre datos extraídos

Las imágenes WebP/PNG extraídas en esta sesión (136 por tema × 3 temas, más las de `GlobalImage`) son propiedad de HERE/Kia y **no se han incluido en este repositorio** — el trabajo de extracción se hizo en un directorio temporal fuera del árbol del proyecto. Este documento describe la estructura y el contenido observado, no adjunta las imágenes en sí.

Related: [`hafr_spatial_index.md`](hafr_spatial_index.md), [`hafp_geometry_search.md`](hafp_geometry_search.md), [`hafls_tile_table.md`](hafls_tile_table.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
