# camera_editor — editor nativo de macOS para límites de velocidad

App nativa de macOS (SwiftUI, Swift Package Manager) que combina lo confirmado
el 2026-07-09/10 (ver [`docs/hafr_spatial_index.md`](../../docs/hafr_spatial_index.md)):

- Tabla de nombres de calle de un `.haftlt` (Pascal-strings UTF-8)
- `linked_records` del mismo `.haftlt`, con `LINK_ID` candidato en el campo `f6/f7`
  (confirmado por permutación estadística y verificación directa contra `SPEED_PATCH.db`)
- `SPEED_PATCH.db` (SQLite) — límites de velocidad reales por `LINK_ID`

Permite **listar, buscar, añadir, editar y borrar** filas de `SPEED_PATCH.db`.

## ⚠️ Qué NO hace

- **No escribe sobre el `.haftlt` original.** El formato de escritura de ese
  binario (fórmula del checksum de cabecera, conexión exacta nombre↔registro)
  no está resuelto — ver `docs/haftlt_build_diff_260128.md`.
- **La búsqueda "por dirección" no es un enlace confirmado.** Muestra
  candidatos de `LINK_ID` por proximidad de posición en el array de
  `linked_records` respecto al nombre de calle — esa conexión se probó
  exhaustivamente y quedó **refutada** con pruebas de permutación. La app
  lo señala con un aviso visible en la interfaz; no lo trates como resultado
  fiable, solo como punto de partida para explorar.
- Solo cubre un país (`.haftlt` de un país) por sesión de la app.

## Requisitos

- macOS 14 (Sonoma) o superior
- Swift 5.9+ (viene con Xcode 15+ / Command Line Tools)

## Uso

```bash
cd tools/camera_editor
swift run
```

O abrir el paquete directamente en Xcode (`File → Open…` sobre esta carpeta,
Xcode reconoce `Package.swift` como proyecto SwiftUI).

La app trabaja **directamente sobre el ZIP de mapas** — no hace falta extraer
nada a mano con `unzip` primero.

1. **1. ZIP de mapas** → botón "Elegir ZIP…". Ruta habitual en este repo:
   `HU/images/navi_eu/S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip` (17,9 GB — la app
   solo lee las entradas necesarias, no descomprime el ZIP entero).
2. Elegir el **país** en el desplegable (se rellena leyendo el índice del ZIP)
   y pulsar "Extraer y cargar". Extrae `VIT_EUR_<PAIS>.haftlt` y
   `SPEED_PATCH.db` a una carpeta `camera_editor_cache/` junto al ZIP — solo
   la primera vez, las siguientes veces usa la caché (instantáneo).
3. La app crea automáticamente una **copia editable** de `SPEED_PATCH.db`
   dentro de esa misma caché (`SPEED_PATCH_editable.db`) — todas las
   escrituras van ahí, nunca al ZIP ni al SQLite original.
4. Buscar por `LINK_ID` exacto, listar todo paginado, o (con el aviso de
   arriba en mente) explorar por nombre de calle.
5. Añadir/editar/borrar filas con los botones de la tabla.

## Reempaquetar tras editar

Botón **"Reinyectar en el ZIP…"** en la barra lateral: actualiza la entrada
`SPEED_PATCH.db` dentro de un ZIP de destino (por defecto una **copia nueva**,
no el original — puedes elegir explícitamente el original si sabes lo que
haces). La primera vez que apuntas a una copia nueva, la app la crea copiando
el ZIP completo (varios minutos por el tamaño); las siguientes reinyecciones
sobre esa misma copia son rápidas (`zip -u` solo reescribe la entrada).

**Esto NO completa el flujo de instalación por sí solo** — sigue haciendo
falta recalcular MD5 y el CRC32 con signo en `Rio_MY22_EU.ver`, exactamente
como describe [`.claude/memory/speed_patch_workflow.md`](../../.claude/memory/speed_patch_workflow.md).
La app te lo recuerda en el mensaje de estado tras reinyectar.

## Estructura

| Fichero | Contenido |
|---|---|
| `Package.swift` | Manifiesto SPM, macOS 14+, enlaza `libsqlite3` |
| `Sources/CameraEditor/ZipTool.swift` | Envoltorio sobre `/usr/bin/unzip` y `/usr/bin/zip` (vía `Process`) — listar países, extraer entradas sin descomprimir el ZIP entero, reinyectar cambios |
| `Sources/CameraEditor/HaftltParser.swift` | Puerto a Swift del parser de `tools/haftlt_parser/parse_haftlt.py` (detector de tabla de nombres + `linked_records`) |
| `Sources/CameraEditor/SpeedPatchStore.swift` | Envoltorio sobre SQLite3 (C API) — listar paginado, buscar, añadir/editar/borrar |
| `Sources/CameraEditor/AppModel.swift` | Estado observable de la app, lógica de búsqueda |
| `Sources/CameraEditor/ContentView.swift` | Interfaz SwiftUI (`NavigationSplitView`) |
| `Sources/CameraEditor/CameraEditorApp.swift` | Punto de entrada `@main` |

## Verificación

La lógica de `HaftltParser` y `SpeedPatchStore` se verificó (sesión 2026-07-10)
contra los datos reales de España: 20.290 nombres, 23.528 registros,
`LINK_ID=15429877` → `SP_LIMIT` 80/50 km/h por sentido (coincide exactamente
con lo verificado antes en Python), paginación, y ciclo completo
añadir→editar→borrar sobre la copia editable **sin tocar el original**
(confirmado releyendo el fichero fuente tras cada prueba).

`ZipTool` se verificó por separado contra el ZIP real de 17,9 GB: listado de
los 13 países, extracción de `VIT_EUR_SPN.haftlt` (5.755.556 bytes exactos,
0,07s) y `SPEED_PATCH.db` (160.373.760 bytes exactos, 0,8s), caché en
re-extracciones (~0s), y `updateEntry` sobre un ZIP de prueba: la entrada se
actualiza con el contenido nuevo y el resto de entradas del ZIP quedan
intactas.
