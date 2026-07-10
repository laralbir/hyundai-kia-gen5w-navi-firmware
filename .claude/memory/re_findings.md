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
- ⚠️ **Corrección (2026-07-10):** NO es ARM Cortex-M. Desensamblado real con Ghidra + módulo RL78 de terceros (`xyzz/ghidra-rl78`) confirma **Renesas RL78**: tabla de vectores de 16 bits en `0x0000-0x007E` (reset vector `0x00D8`), option bytes `0xC2-C3`, Security ID `0xC4-CE`. El binario NO está cifrado — desensamblado limpio y coherente.
- **MKBD** = Main Key Board Driver (firmware del panel de botones).
- **Lógica identificada:** 16 funciones de validación (tabla de punteros en `0xBBD0`) comparan un buffer de 8 bytes (`!0xFF680`, lectura cruda de la matriz de botones) contra tablas de calibración por botón en RAM, marcando discrepancias en un bitmap de ~40 bits (`!0xFF6B9-0xFF6BD`). Wrappers de sección crítica DI/EI con contador de anidamiento en `0x8A7F`/`0x8AA3`.
- **NX4 vs US4:** NO son el mismo código con datos distintos — 39.8% de bytes difieren en todo el fichero, ~92% dentro de la región de código analizada. Son compilaciones genuinamente distintas.
- Pendiente: localizar el protocolo de comunicación serie con el SoC principal (UART/LIN/SPI) y el origen en flash de las tablas de calibración.
- Análisis completo: [`docs/frontkey_mkbd_analysis.md`](../../docs/frontkey_mkbd_analysis.md).
- Herramientas: Ghidra 12.x + módulo RL78 (`brew install ghidra`, no incluye RL78 de fábrica).
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
4. **Para descifrar — ruta conocida (gen5w exploit):**
   - Exploit `navi_extended` en HU físico → extrae `DecryptToPIPE` + `decryption_key.der`
   - Docker `update_decryptor` con esos dos archivos descifra todos los OTA en PC
   - Ver `docs/gen5w_exploit_ecosystem.md` para el flujo completo
   - `DecryptToPIPE` es el binario del HU que actúa de `update_agent` — reside en `/Bin/` del HU
5. **SPEED_PATCH.db** (dentro del ZIP de mapas) — SQLite accesible directamente con `sqlite3`.
6. **Frontkey MCU bins** — accesibles, analizables con Ghidra + ARM Cortex-M.
7. **Comparación entre builds sin clave ("prefix/suffix leak")** — al recibir una nueva versión, comparar `cmp` offset del primer byte divergente entre builds del mismo fichero (mismo tamaño, checksum `.ver` distinto) revela si el cambio es solo un trailer de firma (~16.417 bytes, payload idéntico) o contenido real. Ver `docs/diff_version_260128.md` y [[version-diff-260128]].

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
