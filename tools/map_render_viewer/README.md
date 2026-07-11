# map_render_viewer — visualizador de assets de renderizado del mapa

Genera una página HTML autocontenida (galería con pestañas) para inspeccionar
visualmente los tres formatos de imagen resueltos en
[`docs/rendering_visual_assets.md`](../../docs/rendering_visual_assets.md):

| Pestaña | Fichero origen | Formato |
|---|---|---|
| **Guiado de salida (WebP)** | `VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma` | WebP embebido, extraído directamente (magic `RIFF`) |
| **Atlas de texturas UI (RGB/RGBA)** | `VIT_EUR_CE_THEME_IMAGE.bin` | Píxeles sin comprimir; cabecera con enums reales de OpenGL (`GL_RGB`/`GL_RGBA`) |
| **Landmarks 3D (ASTC)** | `VIT_EUR_3D_LANDMARK_ASTC.hafmma` | ASTC estándar (bloque 10×10), decodificado con `astcenc` |

Trabaja **directamente sobre el ZIP de mapas** (mismo enfoque que `camera_editor`)
— no hace falta extraer nada a mano primero.

## ⚠️ El HTML generado NO se debe commitear

Igual que `tools/haftlt_viewer`: el HTML embebe imágenes reales extraídas del
paquete de mapas de HERE (en base64). El aviso legal del repositorio declara
que no se distribuyen datos de mapas con derechos de autor — genera el
visualizador solo localmente o publícalo como Artifact efímero (privado), pero
no lo añadas a git. `.gitignore` ya excluye todo lo que no esté explícitamente
permitido, así que no requiere una regla adicional.

## Requisitos

```bash
pip install pillow
```

Para la pestaña de landmarks 3D hace falta además un binario `astcenc`
(decodificador ASTC de Khronos). No hay fórmula en Homebrew — hay que
compilarlo desde fuente:

```bash
brew install cmake
git clone --depth 1 https://github.com/ARM-software/astc-encoder.git
cd astc-encoder && mkdir build && cd build
cmake -DCMAKE_BUILD_TYPE=Release ..
cmake --build . -j 8
# el binario queda en Source/astcenc-<isa>, p.ej. Source/astcenc-neon en Apple Silicon
```

Sin `astcenc` en `PATH` (o pasado con `--astcenc`), la pestaña de landmarks
sigue mostrando qué texturas se localizaron (dimensiones, tamaño de bloque)
pero sin decodificar el contenido — usa `--skip-astc` para omitir esa pestaña
por completo y ahorrar tiempo.

## Uso

```bash
python3 tools/map_render_viewer/generate_viewer.py \
  --zip HU/images/navi_eu/S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip \
  --astcenc /ruta/a/astc-encoder/build/Source/astcenc-neon \
  -o /tmp/map_render_viewer.html

open /tmp/map_render_viewer.html   # macOS
```

### Opciones relevantes

| Flag | Default | Qué controla |
|---|---|---|
| `--themes` | `LATTE,MILK,MOCHA` | Qué paletas de guiado incluir (cada una son 136 imágenes, ~780 KB de fichero fuente — barato incluir las tres) |
| `--textures-limit` | `80` | Cuántas texturas del atlas UI decodificar (`0` = las ~420 completas; el fichero pesa 84,5 MB pero solo hace falta leerlo una vez) |
| `--astc-limit` | `15` | Cuántas texturas ASTC decodificar — cada una lanza un subproceso `astcenc`, es la parte más lenta |
| `--astc-sample-mb` | `10` | Cuántos MB leer de `VIT_EUR_3D_LANDMARK_ASTC.hafmma` (379 MB completos; con 10 MB ya aparecen decenas de texturas candidatas gracias a lectura parcial de ZIP) |
| `--skip-astc` | — | Omite la pestaña de landmarks por completo (más rápido si solo interesan las otras dos) |

## Qué NO hace

- **No decodifica `VIT_EUR_SYMBOL_48.hafmma`** (iconos de POI) — confirmado que
  es RGBA sin comprimir, pero el stride/ancho exacto por icono no se resolvió
  (ver "Próximos pasos" en `docs/rendering_visual_assets.md`). Añadir esa
  pestaña requiere primero decodificar el índice jerárquico por categoría.
- **No decodifica `.skn`** como imagen — es un fichero de manifiesto/tabla de
  estilo, no contiene píxeles directamente (ver detalle en la documentación).
- **No decodifica modelos 3D** (`VIT_EUR_3D_MODEL_SYM*.hafmma`) — es malla
  (vértices/UV/índices), no textura; formato sin explorar todavía.
- La lectura de `VIT_EUR_3D_LANDMARK_ASTC.hafmma` es **parcial** (los primeros
  N MB del fichero descomprimido, no los 379 MB completos) — suficiente para
  encontrar decenas de texturas de muestra sin tener que procesar el fichero
  entero cada vez.

## Verificación

Ejecutado contra el ZIP real (17,9 GB): con los defaults (`--textures-limit 80
--astc-limit 12 --astc-sample-mb 10`) genera un HTML de ~25 MB en unos
segundos, con exactamente 500 imágenes embebidas (80 atlas + 408 WebP de
guiado + 12 landmarks ASTC), todas con base64 válido y decodificable.
