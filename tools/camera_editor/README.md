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

Dentro de la app:
1. **Ficheros** → elegir un `.haftlt` extraído (p. ej. `VIT_EUR_SPN.haftlt`) y
   el `SPEED_PATCH.db` original (extraídos del ZIP de mapas, ver
   `.claude/memory/speed_patch_workflow.md`).
2. La app crea automáticamente una **copia editable** junto al original
   (`SPEED_PATCH_editable.db`) — todas las escrituras van ahí, nunca al
   original.
3. Buscar por `LINK_ID` exacto, listar todo paginado, o (con el aviso de
   arriba en mente) explorar por nombre de calle.
4. Añadir/editar/borrar filas con los botones de la tabla.

## Reempaquetar tras editar

La copia editable es un SQLite normal — para instalarla, sigue el workflow ya
documentado en [`.claude/memory/speed_patch_workflow.md`](../../.claude/memory/speed_patch_workflow.md):
sustituir `SPEED_PATCH.db` dentro del ZIP de mapas, recalcular MD5 y el CRC32
con signo en `Rio_MY22_EU.ver`.

## Estructura

| Fichero | Contenido |
|---|---|
| `Package.swift` | Manifiesto SPM, macOS 14+, enlaza `libsqlite3` |
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
