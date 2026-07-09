# haftlt_viewer — visualizador interactivo de radares

Genera una página HTML autocontenida para inspeccionar un fichero `VIT_EUR_XXX.haftlt`
(base de datos de radares HERE) comparando dos builds del mismo país: minimapa
navegable coloreado por región conocida, hex dump en vivo, e inspector u8/u16/u32
little-endian bajo el cursor.

No decodifica coordenadas GPS ni registros de cámara — ese formato sigue sin
resolverse (ver [`docs/haftlt_build_diff_260128.md`](../../docs/haftlt_build_diff_260128.md)).
Es una herramienta de inspección para continuar esa investigación, no un mapa de cámaras.

## ⚠️ El HTML generado NO se debe commitear

El fichero de salida embebe **ambos `.haftlt` completos en base64** — es decir, una
copia sin pérdida del dato propietario de HERE, solo re-codificada. A diferencia de
las imágenes PNG en `docs/assets/` (que son una representación agregada/con pérdida,
no reconstruible al original), este HTML sí permite reconstruir el fichero binario
exacto. El aviso legal del repositorio declara que no se distribuyen datos de mapas
con derechos de autor — así que genera el visualizador solo localmente, o publícalo
como Artifact efímero (privado) para revisarlo, pero no lo añadas a git.

## Uso

```bash
# Extraer los dos ficheros a comparar desde el ZIP de mapas (ver speed_patch_workflow.md
# para el patrón general de extracción con unzip -p)
python3 generate_viewer.py \
  ruta/VIT_EUR_SPN_251204.haftlt ruta/VIT_EUR_SPN_260128.haftlt \
  --country SPN \
  --label-old "251204 (jul 2025)" --label-new "260128 (nov 2025)" \
  -o /tmp/haftlt_viewer_spn.html

open /tmp/haftlt_viewer_spn.html   # macOS
```

## Qué muestra

| Color | Región | Estado |
|---|---|---|
| Gris neutro | Cabecera | Metadatos (versión, fechas, offsets) |
| Azul | Tabla índice | Descartada como almacén de cámaras (0 crecimiento entre builds) |
| Verde/aqua | Sección 1 | Descartada |
| Gris oscuro | Tramos sin cambios | — |
| **Rojo** | Región media | **Candidata** — crece entre builds |
| Amarillo | Secciones 2–4 | Mismo tamaño exacto, ~90% bytes distintos → ruido de renumeración de IDs, no la fuente |
| **Naranja** | Región cola | **Candidata** — crece entre builds, inserción más limpia |

La clasificación por región y el cálculo de los puntos de inserción (prefijo/sufijo
común entre builds) replican exactamente la metodología de
`docs/haftlt_build_diff_260128.md` — verificado con un harness de Node contra los
mismos números que produce el análisis en Python.

## Limitaciones conocidas

- Pensado para un único país por invocación (los tamaños de `.haftlt` por país varían
  bastante; España a resolución completa genera un HTML de ~15 MB en base64, funciona
  pero tarda unos segundos en decodificar en el navegador).
- Requiere las dos builds del mismo país ya extraídas localmente — no descarga ni
  descomprime el ZIP de mapas por sí mismo.
