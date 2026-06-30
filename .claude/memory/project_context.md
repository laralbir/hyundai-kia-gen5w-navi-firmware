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

**Hallazgo clave de RE:** Cifrado confirmado como **AES/Rijndael** (vía `COPYRIGHT.TXT` del paquete de mapas HERE). La clave reside en el HU físico — el binario `DecryptToPIPE` (en `/Bin/` del HU) la usa con `decryption_key.der` para descifrar el OTA.

**Único archivo en formato estándar (gzip real):** `mango-vr_fixed.tar.gz` (vrau y vreu) — ya explorado y documentado en [[vr-engine]].

**Ruta de descifrado conocida (gen5w exploit):** exploit `navi_extended` en HU físico → extrae `DecryptToPIPE` + `decryption_key.der` → Docker `update_decryptor` descifra todos los archivos OTA en PC. Ver [[gen5w-exploit]] y `docs/gen5w_exploit_ecosystem.md`.

**Why:** Todo el paquete OTA está encriptado con AES; la clave solo existe en el HU físico. El exploit gen5w es el único camino conocido para obtenerla.

**How to apply:** Cuando se proponga analizar archivos del paquete, recordar que solo `mango-vr_fixed.tar.gz` es accesible directamente sin HU. Con acceso físico al HU, seguir el flujo gen5w para descifrar el resto.

Related: [[file-details]] · [[haf-format]] · [[vr-engine]] · [[re-findings]]
