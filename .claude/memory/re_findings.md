---
name: re-findings
description: "Hallazgos de ingeniería inversa: cifrado AES confirmado, puntos de entrada para RE, magic bytes, firmware MCU, y estrategia de análisis"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2f9fdbd7-182d-499f-807a-20ce446fa9ba
---

## Cifrado — Confirmación AES

- **`COPYRIGHT.TXT`** dentro del ZIP de mapas HERE lista **Rijndael (AES)** como componente de software.
- Todos los archivos del paquete OTA (excepto `mango-vr_fixed.tar.gz`) están cifrados con AES.
- La clave probablemente está **hardcodeada o derivada (VIN/IMEI)** en el rootfs del HU.
- El proceso de descifrado vive en el instalador OTA del HU (`update_agent`, `fota`, o similar en `/usr/bin/` del rootfs).

## Magic bytes — tabla de identificación

| Archivo (tipo) | Magic esperado | Magic observado | Estado |
|----------------|----------------|-----------------|--------|
| `mango-vr_fixed.tar.gz` | `1f 8b` (gzip) | `1f 8b 08 00` | ✓ Gzip real |
| `mango-rootfs.tar.gz` | `1f 8b` | `52 b4 33 00` | Cifrado AES |
| `update.tar.gz` | `1f 8b` | `b8 52 5a 8d` | Cifrado AES |
| `appnavi.tar` | `75 73 74 61 72` @257 | `e1 30 0e d0` | Cifrado AES |
| `AppUpgrade` | — | `f3 e4 2a 10` | Cifrado propietario |
| `iasImage*` | `27 05 19 56` (U-Boot) | `d8 e3 57 0d` | Cifrado/IAS |
| `mango-vr.tar.gz` (vrau) | `1f 8b` | `fe 8e 43 ff` | Cifrado |
| `mango-vr.tar.gz` (vreu) | `1f 8b` | `6e 61 69 eb` | Cifrado |

## Firmware MCU (frontkey)

- `MKBD_2_1f_00_NX4.bin` y `MKBD_2_22_00_US4.bin` — 192 KB cada uno.
- Magic `d8 00 ff ff ff ff`: patrón típico de flash **ARM Cortex-M** (little-endian).
  - Bytes 0–3: Initial Stack Pointer
  - Zonas `ff ff ff ff`: sectores de flash no programados
- **MKBD** = Main Key Board Driver (firmware del panel de botones).
- Herramientas: Ghidra o IDA con arquitectura ARM Cortex-M.
- CRC32 verificables con `frontkey/Checksum.txt`:
  - NX4: `0x0E969002`
  - US4: `0xBCFCC65D`

## iasImage — formato

- Nombre sugiere **IAS = Image Authentication Subsystem** (arranque seguro firmado/cifrado).
- No coincide con U-Boot (`27 05 19 56`), FIT/DTB (`d0 0d fe ed`), ni zImage.
- Si es Qualcomm IAS: probar `fwunpack` o scripts específicos de Snapdragon.
- Alternativa: `binwalk` para buscar patrones internos.
- Los 6 ficheros `*_sub` tienen 16,420 bytes menos exactos — diferencia estructural, no relleno.

## AppUpgrade

- No es un directorio — es un fichero binario de 10.3 MB.
- Magic `f3 e4 2a 10` — no coincide con ningún formato estándar.
- Probable contenido: APKs o paquetes propietarios de Hyundai/Kia.
- Sin descifrado, inaccesible. El binario que lo procesa está en el rootfs.

## Estrategia de RE recomendada

1. **Punto de entrada 1:** `mango-vr_fixed.tar.gz` — ya accesible, explorar estructura VR.
2. **Punto de entrada 2:** `mango-rootfs.tar.gz` — una vez descifrado, es el núcleo del sistema. Buscar en `/etc/`, `/usr/bin/`, `/system/`. Objetivos: `update_agent`, `fota`, gestión HERE, protocolo CAN bus.
3. **Punto de entrada 3:** `update.tar.gz` — firmware principal del sistema (kernel, módulos, binarios).
4. **Para descifrar:** el instalador OTA del HU contiene la lógica. Buscar en el rootfs los procesos de instalación que leen los archivos del USB.
5. **SPEED_PATCH.db** (dentro del ZIP de mapas) — SQLite accesible directamente con `sqlite3`.
6. **Frontkey MCU bins** — accesibles, analizables con Ghidra + ARM Cortex-M.

## Componentes de software confirmados (COPYRIGHT.TXT)

| Componente | Versión | Función RE relevante |
|------------|---------|----------------------|
| Rijndael | — | **AES** → cifrado de OTA |
| SQLite | — | SPEED_PATCH.db |
| Anti-Grain Geometry | 2.4 | Renderizado 2D del mapa |
| Mesa3D | — | OpenGL ES — GPU compatible con ASTC |
| libpng | — | PNG decoder |
| TinyXML | — | Parsing XML interno |
| STLPort | — | STL embebido |
| Boost | — | Utilidades C++ |
| Zlib | — | Compresión interna |

Related: [[project-context]] · [[file-details]] · [[haf-format]] · [[vr-engine]]
