---
name: project-context
description: "Rio MY22 EU — Kia Rio 2022 EU head unit firmware/maps reverse engineering, platform details and build context"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2f9fdbd7-182d-499f-807a-20ce446fa9ba
---

Ingeniería inversa del firmware y mapas del Head Unit del Kia Rio 2022 (variante Europa).

**Plataforma:**
- SoC/board codename: **mango**
- SW version: **S5W** (5th gen, "5w" en rutas de build)
- Versión completa: `YB_22.EUR.S5W_L.001.001.251204`
- Build type: `MASS_PRODUCT` · Fecha: 2025-12-04 13:45:26
- Release: `25RU2_001`
- Build server path: `/data001/vc.integrator/__EVENT_BUILD_s5w.25ru2.250702_MASS_PRODUCT_25RU2_001_251204134526/build-mango/BUILD/deploy/images/5w/usb/`

**Hallazgo clave de RE:** Cifrado confirmado como **AES/Rijndael** (vía `COPYRIGHT.TXT` del paquete de mapas HERE). La clave reside casi con certeza en el rootfs del HU (hardcodeada o derivada del VIN/IMEI). Sin el rootfs descifrado, los binarios del OTA no son accesibles directamente.

**Único archivo en formato estándar (gzip real):** `mango-vr_fixed.tar.gz` (vrau y vreu) — ya explorado y documentado en [[vr-engine]].

**Why:** Todo el paquete OTA está encriptado con AES; el proceso de descifrado vive en el rootfs del HU. El punto de entrada para RE es obtener/analizar ese proceso de instalación.

**How to apply:** Cuando se proponga analizar archivos del paquete, recordar que solo `mango-vr_fixed.tar.gz` es accesible directamente. Para el resto, buscar primero el `update_agent` o binario equivalente en el rootfs.

Related: [[file-details]] · [[haf-format]] · [[vr-engine]] · [[re-findings]]
