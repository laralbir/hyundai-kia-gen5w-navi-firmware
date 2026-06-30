---
name: file-details
description: "Tamaños, accesibilidad y magic bytes de todos los archivos del paquete Rio MY22 EU"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2f9fdbd7-182d-499f-807a-20ce446fa9ba
---

## Estado de accesibilidad por archivo

| Archivo | Tamaño | Accesible | Magic bytes | Nota |
|---------|--------|-----------|-------------|------|
| `Rio_MY22_EU.ver` | 2.5 KB | ✓ texto plano | — | Manifiesto pipe-delimited |
| `AppUpgrade` | 10.3 MB | ✗ cifrado | `f3 e4 2a 10` | No es directorio; propietario |
| `update.tar.gz` | 40.2 MB | ✗ cifrado | `b8 52 5a 8d` | No es gzip (`1f 8b`) |
| `frontkey/Checksum.txt` | 76 B | ✓ texto plano | — | CRC32 hex de los .bin |
| `MKBD_2_1f_00_NX4.bin` | 192 KB | ✓ binario ARM | `d8 00 ff ff` | ARM Cortex-M, ISP offset 0 |
| `MKBD_2_22_00_US4.bin` | 192 KB | ✓ binario ARM | `d8 00 ff ff` | CRC32=0xBCFCC65D |
| `modem_eu.tar.gz` | 151.3 MB | ✗ cifrado | no-gzip | Módem EU estándar |
| `modem_eu_le22.tar.gz` | 331.1 MB | ✗ cifrado | no-gzip | Módem LTE EU chipset LE rev.22 |
| `modem_au_le22.tar.gz` | 121.9 MB | ✗ cifrado | no-gzip | Módem LTE AU chipset LE rev.22 |
| `iasImage` (×12) | 6.0–6.1 MB | ✗ cifrado | `d8 e3 57 0d` | No es U-Boot (`27 05 19 56`) ni FIT |
| `mango-rootfs.tar.gz` | 838.4 MB | ✗ cifrado | `52 b4 33 00` | No es gzip |
| `mango-rwdata.tar.gz` | 16.0 MB | ✗ cifrado | no-gzip | Config user RW |
| `new_gui.tar.gz` | 1.99 GB | ✗ cifrado | no-gzip | GUI completa |
| `mustwithcopy` | 0 B | ✓ vacío | — | Flag para el instalador OTA |
| `appnavi.tar` | 487 MB | ✗ cifrado | `e1 30 0e d0` | No es TAR POSIX |
| `S5W_MAP_ALL_EUR_*.zip` | 16.66 GB | ✗ cifrado probable | — | Mapas HERE Europa |
| `EUR.*_md5.txt` | 73 B | ✓ texto plano | — | MD5 del ZIP de mapas |
| `mango-vr.tar.gz` (vrau) | 43.2 MB | ✗ cifrado | `fe 8e 43 ff` | Original propietario |
| `mango-vr.tar.gz` (vreu) | 62.9 MB | ✗ cifrado | `6e 61 69 eb` | Original propietario |
| `mango-vr_fixed.tar.gz` (vrau) | 544 MB | **✓ gzip real** | `1f 8b 08 00` | Post-build fix; explorable |
| `mango-vr_fixed.tar.gz` (vreu) | 2.20 GB | **✓ gzip real** | `1f 8b 08 00` | Post-build fix; explorable |
| `md5sum.txt` (vr*) | 200 B | ✓ texto plano | — | Incluye ruta completa del build server |

## Tamaños totales por componente
| Componente | Tamaño |
|------------|--------|
| Mapas HERE Europa | 16.66 GB |
| VR Europa (fixed) | 2.20 GB |
| GUI nueva | 1.99 GB |
| Root filesystem | 838.4 MB |
| VR Australia (fixed) | 544 MB |
| Aplicación navegación | 487 MB |
| Módem EU LE22 | 331.1 MB |
| Módem EU estándar | 151.3 MB |
| Módem AU LE22 | 121.9 MB |
| Firmware principal HU | 40.2 MB |
| VR Europa (original) | 62.9 MB |
| VR Australia (original) | 43.2 MB |
| Datos RW | 16.0 MB |
| AppUpgrade | 10.3 MB |
| iasImages (×12) | ~73.8 MB |
| Frontkey MCU (×2) | ~384 KB |
| **TOTAL** | **~22.5 GB** |

## iasImage — variantes (12 ficheros)
Los `*_sub` tienen exactamente 16,420 bytes menos que sus homólogos principales.
Mismo tamaño → MD5 distinto (contenido diferente).
- `iasImage` / `iasImage_sub` — base, default resolution
- `iasImage_1280` / `iasImage_1280_sub` — base, 1280px
- `iasImage_1920_12` / `iasImage_1920_12_sub` — base, 1920px 1.2"
- `iasImage_p5` / `iasImage_p5_sub` — platform p5, default
- `iasImage_p5_1280` / `iasImage_p5_1280_sub` — p5, 1280px
- `iasImage_p5_1920_12` / `iasImage_p5_1920_12_sub` — p5, 1920px 1.2"

IAS = probable **Image Authentication Subsystem** (arranque seguro firmado). Si es Qualcomm, probar `fwunpack` o scripts de Snapdragon.

## .ver manifiesto — primera línea
```
+|19328|YB_22.EUR.S5W_L.001.001.251204|KM|Rio_MY22_EU|1565|1
```
`KM` = Kia Motors. Record IDs: 308413–308447.

Related: [[project-context]] · [[re-findings]]
