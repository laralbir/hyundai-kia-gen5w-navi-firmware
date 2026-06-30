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
├── CLAUDE.md                        Contexto e instrucciones para el asistente IA
├── docs/
│   ├── estructura_ficheros.md       Árbol completo de ficheros con tamaños, magic bytes y notas de RE
│   └── analisis_mapas_here.md       Análisis técnico detallado del paquete de mapas HERE
└── .claude/memory/                  Archivos de memoria IA (hallazgos RE, formatos, motor VR…)
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

- **Cifrado:** AES/Rijndael confirmado mediante `COPYRIGHT.TXT` dentro del paquete de mapas HERE. La clave de descifrado probablemente está hardcodeada o derivada del VIN/IMEI dentro del rootfs del HU.
- **Únicos ficheros accesibles sin descifrado:** `mango-vr_fixed.tar.gz` (ambas regiones, gzip real) y los `.bin` del MCU del panel de botones (ARM Cortex-M).
- **Formato HERE Maps:** HAF (HERE Automotive Format), propietario. `SPEED_PATCH.db` es una base de datos SQLite 3 estándar con 10,3 millones de registros de límites de velocidad por segmento de carretera.
- **Motor de voz:** LPTE TTS v1.5.1 (probablemente Cerence/ex-Nuance). 24 idiomas europeos en el paquete EU; solo coreano en el paquete AU.
- **Formato iasImage:** Probable IAS (Image Authentication Subsystem) — imágenes de arranque seguro firmadas/cifradas. No coincide con los magic bytes de U-Boot, FIT/DTB ni zImage.

---

## Documentación

- [Estructura de ficheros y notas de RE](docs/estructura_ficheros.md) — árbol completo con tamaños, magic bytes y análisis por componente.
- [Análisis técnico de los mapas HERE](docs/analisis_mapas_here.md) — formato HAF, esquema de `SPEED_PATCH.db`, bases de datos de radares, datos ADAS de horizonte electrónico, diccionarios VR, assets de interfaz e inventario de software de terceros.

---

## Aviso legal

Este repositorio contiene únicamente documentación y análisis — no se incluyen binarios de firmware, datos de mapas ni ningún activo con derechos de autor.  
Toda la ingeniería inversa se realiza con fines de interoperabilidad e investigación.
