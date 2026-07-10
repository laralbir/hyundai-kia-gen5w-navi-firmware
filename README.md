# Hyundai / Kia Standard Gen5W Navigation — Ingeniería inversa del firmware

Ingeniería inversa del firmware de la unidad de cabeza (Head Unit) **Standard Gen5W Navigation**, variante Europa.  
Este dispositivo es compartido por múltiples modelos de Hyundai y Kia (p.ej. Kia Rio MY22, entre otros).

---

## Dispositivo y firmware

| Campo | Valor |
|---|---|
| Dispositivo | Standard Gen5W Navigation (HU) |
| SoC / placa | **mango** |
| Versión SW | **S5W** (5ª generación) |
| Versión completa | `YB_22.EUR.S5W_L.001.001.251204` |
| Región | EUR (Europa) |
| Tipo de build | `MASS_PRODUCT` |
| Fecha de build | 2025-12-04 13:45:26 |
| Release | `25RU2_001` |
| SO | Linux embebido |

---

## Contenido del repositorio

```
.
├── CLAUDE.md                           Contexto e instrucciones para el asistente IA
├── docs/
│   ├── estructura_ficheros.md          Árbol completo de ficheros con tamaños, magic bytes y notas de RE
│   ├── analisis_mapas_here.md          Análisis técnico detallado del paquete de mapas HERE
│   ├── gen5w_exploit_ecosystem.md      Cadena de exploit para descifrar OTA + persistencia en el HU
│   ├── engineering_mode.md             Análisis de acceso a Engineering Mode (bloqueos SOP, PIN QML, rutas alternativas)
│   ├── diff_version_260128.md          Comparación ciphertext-level entre builds 251204 y 260128
│   ├── haftlt_build_diff_260128.md     Diff binario dirigido de .haftlt entre dos builds reales — localización de zonas de radares
│   ├── hafls_tile_table.md             Tabla de tiles candidata en .hafls (offset 0x108, stride 3MB) — mejor pista de tile-base NDS hasta ahora
│   └── hafr_spatial_index.md           🎯 Índice espacial real en .hafr + correlación a LINK_ID confirmada con permutación (p=0.0) — hallazgo principal
└── tools/                              Herramientas y guías operativas para RE del HU
    ├── README.md                       Guía maestra paso a paso (leer primero)
    ├── setup.sh                        Clona todos los repos gen5w y verifica dependencias
    ├── phase1_usb/                     Exploit USB — extracción de claves del HU
    │   ├── README.md
    │   └── prepare_usb.sh             Prepara el USB exFAT con los scripts necesarios
    ├── phase2_decrypt/                 Descifrado OTA en PC (Docker)
    │   ├── README.md
    │   └── decrypt.sh                 Wrapper para update_decryptor
    ├── phase3_patch/                   Parche del rootfs (wideopen + Engineering Mode bypass)
    │   ├── README.md
    │   └── patch.sh                   Wrapper para update-patcher
    ├── phase4_explore/                 Exploración y análisis del rootfs descifrado
    │   ├── README.md
    │   └── explore.sh                 Extrae y analiza el rootfs localmente
    ├── haftlt_viewer/                  Visualizador interactivo del fichero de radares (.haftlt)
    │   ├── README.md                   Uso y aviso: la salida NO se commitea (embebe datos HERE)
    │   └── generate_viewer.py         Genera el HTML: minimapa, hex dump e inspector u8/u16/u32
    └── haftlt_parser/                  Desempaquetado estructurado del .haftlt (CSV/JSON)
        ├── README.md                   Uso y aviso sobre *_diverging.bin (no son "bytes nuevos")
        └── parse_haftlt.py            Vuelca índice + Secciones 1-4 a CSV; --other localiza zonas candidatas
```

> Los ficheros binarios de gran tamaño (imágenes de firmware, mapas, paquetes VR) están excluidos mediante `.gitignore`.

---

## Resumen del paquete de firmware

| Componente | Tamaño | Estado |
|---|---|---|
| Mapas HERE Europa (`S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip`) | 16,66 GB | Cifrado AES |
| VR Europa — `mango-vr_fixed.tar.gz` | 2,20 GB | **gzip real — accesible** |
| Actualización GUI — `new_gui.tar.gz` | 1,99 GB | Cifrado AES |
| Sistema de archivos raíz — `mango-rootfs.tar.gz` | 838,4 MB | Cifrado AES |
| VR Australia — `mango-vr_fixed.tar.gz` | 544 MB | **gzip real — accesible** |
| Aplicación de navegación — `appnavi.tar` | 487 MB | Cifrado AES |
| Firmware módem EU LE22 | 331,1 MB | Cifrado AES |
| Firmware principal — `update.tar.gz` | 40,2 MB | Cifrado AES |
| Imágenes de arranque — `iasImage` (×12) | ~73,8 MB | Cifrado / formato IAS |
| MCU panel de botones (×2) | ~384 KB | ARM Cortex-M — accesible |
| **Total** | **~22,5 GB** | |

---

## Hallazgos principales de ingeniería inversa

- **Cifrado:** AES/Rijndael confirmado. La clave reside en el HU físico en el binario `DecryptToPIPE` + `decryption_key.der`. Existe una cadena de exploit pública (`gitlab.com/g4933/gen5w`) para extraerla del dispositivo y descifrar los OTA en PC.
- **Únicos ficheros accesibles sin exploit:** `mango-vr_fixed.tar.gz` (ambas regiones, gzip real) y los `.bin` del MCU del panel de botones (ARM Cortex-M).
- **Formato HERE Maps:** HAF (HERE Automotive Format), propietario. `SPEED_PATCH.db` es una base de datos SQLite 3 estándar con 10,3 millones de registros de límites de velocidad por segmento de carretera.
- **Motor de voz:** LPTE TTS v1.5.1 (probablemente Cerence/ex-Nuance). 24 idiomas europeos en el paquete EU; solo coreano en el paquete AU.
- **Formato iasImage:** Probable IAS (Image Authentication Subsystem) — imágenes de arranque seguro firmadas/cifradas. No coincide con los magic bytes de U-Boot, FIT/DTB ni zImage.

---

## Documentación

### Documentos principales

- [Estructura de ficheros y notas de RE](docs/estructura_ficheros.md) — árbol completo con tamaños, magic bytes y análisis por componente. Incluye iasImage, MCU frontkey, VR (mango-vr_fixed), módems y análisis del cifrado.
- [Análisis técnico de los mapas HERE](docs/analisis_mapas_here.md) — formato HAF, esquema de `SPEED_PATCH.db`, bases de datos de radares, datos ADAS de horizonte electrónico, diccionarios VR, assets de interfaz e inventario de software de terceros.
- [Ecosistema de exploits gen5w](docs/gen5w_exploit_ecosystem.md) — cadena completa para descifrar OTA: exploit USB (`navi_extended`), extracción de `DecryptToPIPE` + `decryption_key.der`, Docker `update_decryptor`, patcher de persistencia y entorno `gen5w-docker`.
- [Engineering Mode](docs/engineering_mode.md) — análisis de los dos bloqueos en firmware MASS_PRODUCT (`checkSOPVersion()` + PIN QML), PINs documentados, rutas alternativas de acceso (UART, GDS, firmware antiguo) y procedimiento recomendado.
- [Comparación de versiones 251204 vs 260128](docs/diff_version_260128.md) — análisis ciphertext-level de la nueva versión descargada: técnica de comparación entre builds sin clave, ficheros sin cambio real (frontkey, VR fixed, módems) vs. con cambio real de contenido (rootfs, update, GUI, mapas).
- [Diff binario de .haftlt entre builds reales](docs/haftlt_build_diff_260128.md) — comparación dirigida de la base de radares por país entre las versiones de mapas `18.49.56` y `18.52.70` (~4 meses de diferencia real): descarta índice y Sección 1 como almacén de cámaras, localiza las dos únicas zonas del fichero que crecen entre builds, corrige dos campos de cabecera mal etiquetados como constantes, y confirma una tabla de nombres de calle en texto UTF-8 real (primer texto legible de toda la investigación) en los 4 países probados. La conexión entre esos nombres y los registros de posición se probó exhaustivamente (offsets, índices, cruce con `LINK_ID` de `SPEED_PATCH.db`, coordenada local escalada) y quedó refutada en todos los casos con pruebas de significancia rigurosas.
- [Tabla de tiles en .hafls](docs/hafls_tile_table.md) — análisis de cabecera fresco de la capa pan-europea (layout distinto a `.haftlt`): localiza una tabla de ~464.688 entradas con stride constante de 3 MB, idéntica entre builds — el mejor candidato a tabla de tile-bases (el elemento que la teoría NDS siempre pidió) encontrado en toda la investigación. Aún sin decodificar a coordenadas reales.
- [🎯 Índice espacial y LINK_ID real en .hafr](docs/hafr_spatial_index.md) — hallazgo principal de la investigación: localiza un índice espacial verificable (bounding boxes reales de Europa) y una tabla de nombres de calle en el grafo de rutas completo, con un campo candidato a `LINK_ID` que correlaciona con `SPEED_PATCH.db` a 2,3x la densidad esperada, confirmado con prueba de permutación (p=0,0) — el primer resultado de toda la investigación (4+ sesiones) que sobrevive una prueba de significancia rigurosa.

### Investigaciones en profundidad

- [Formato binario HAFTLT](.claude/memory/haftlt_format.md) — ingeniería inversa completa del formato `VIT_EUR_*.haftlt`: cabecera, tabla índice de 6 bytes, secciones 1–4. ⚠️ El encoding de coordenadas GPS/cámara reportado en sesiones antiguas quedó **refutado** tras contraste con datos reales (radares DGT + grafo `.hafr`); el registro de cámara aún no está aislado, ver también el diff binario contra la segunda build real.
- [Análisis de la base de datos de radares](.claude/memory/project_radar_db.md) — estado del RE: qué archivos contienen realmente los datos de cámaras (`haftlt`, `hafls`), por qué `hafcc` no son cámaras GPS, mapa de viabilidad de modificación (trivial → muy difícil), y próximos pasos ordenados por factibilidad.
- [Workflow SPEED_PATCH.db](.claude/memory/speed_patch_workflow.md) — procedimiento operativo completo para modificar límites de velocidad: extracción del ZIP, operaciones SQLite, reempaquetado, recálculo de MD5 y CRC32 signed int32 para `Rio_MY22_EU.ver`.

### Contexto de ingeniería inversa (memoria IA)

- [Motor de voz VR](.claude/memory/vr_engine.md) — motor LPTE TTS v1.5.1 (Cerence), estructura interna de `mango-vr_fixed.tar.gz`, 24 idiomas EU / coreano AU, datos de voz para POI dentro del ZIP de mapas.
- [Hallazgos RE](.claude/memory/re_findings.md) — cifrado AES confirmado, tabla de magic bytes por archivo, firmware MCU ARM Cortex-M, formato iasImage, estrategia de análisis recomendada, componentes open source confirmados.
- [Formato HAF](.claude/memory/haf_format.md) — HERE Automotive Format: extensiones (`.hafp`/`.hafr`/`.hafaip`/…), esquema SQLite de `SPEED_PATCH.db`, archivos de radar, ADAS, configuración JSON y assets de UI.

---

## Aviso legal

Este repositorio contiene únicamente documentación y análisis — no se incluyen binarios de firmware, datos de mapas ni ningún activo con derechos de autor.  
Toda la ingeniería inversa se realiza con fines de interoperabilidad e investigación.
