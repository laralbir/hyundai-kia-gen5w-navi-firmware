---
name: version-diff-260128
description: "Comparación ciphertext-level entre build 251204 (repo) y 260128 (nueva descarga): qué ficheros cambiaron de contenido real vs. solo re-firmado"
metadata: 
  node_type: memory
  type: project
  originSessionId: aa0804c4-fa35-4402-bdfd-cb13dc0ae451
---

## Nueva versión descargada

`YB_22.EUR.S5W_L.001.001.260128` (2026-01-28), en `/Users/carlos/Downloads/NaU/Rio_MY22_EU`, comparada contra la `251204` ya presente en el repo. Análisis completo en `docs/diff_version_260128.md`.

## Hallazgo clave: técnica de "prefix/suffix leak" sin clave

Comparando dos builds del mismo fichero cifrado (mismo tamaño en `.ver`, checksum distinto), se puede localizar offset del primer byte divergente (`cmp`) para saber si el cambio es:
- **Solo un trailer final** (~16.417 bytes, entropía 7,98/8 bits, sin ASN.1/DER) → payload idéntico, solo re-firmado. Aplica a: `modem_eu*.tar.gz`, `modem_au_le22.tar.gz`, `vrau/mango-vr.tar.gz`.
- **Cabecera fija + resto 100% distinto** → contenido real cambiado. Aplica a: `iasImage*` (cabecera ~14KB), `AppUpgrade` (cabecera 640B), `.lge.upgrade.xml` (cabecera 112B).
- **Diverge desde byte 0** → recifrado/contenido completo distinto. Aplica a `update.tar.gz`.

## Ficheros SIN cambio de contenido entre 251204 y 260128

- Firmware frontkey (`Checksum.txt`, ambos `MKBD_*.bin`) — checksum idéntico.
- `vrau/mango-vr_fixed.tar.gz` — checksum idéntico, byte a byte.
- `vreu/mango-vr_fixed.tar.gz` — accesible sin descifrar (gzip real); listado interno (`tar tzvf`) con 351 entradas: **mismos nombres y tamaños exactos** en ambas versiones. Solo cambia el `mtime` interno del tar (23 sept 2025 → 10 dic 2025, fecha de reempaquetado) y 63 bytes de contenedor gzip. Ningún asset de voz vreu cambió.
- Módems (`modem_eu*`, `modem_au_le22`) y `vrau/mango-vr.tar.gz` (original) — payload idéntico, solo cambia un trailer de firma de 16.417 bytes al final.

## Ficheros CON cambio de contenido real (candidatos prioritarios si se logra descifrar)

`update.tar.gz`, `mango-rootfs.tar.gz` (+108KB), `mango-rwdata.tar.gz` (+8KB), `new_gui.tar.gz` (+720KB), `appnavi.tar` (+860KB), `vreu/mango-vr.tar.gz` (original, no el fixed, −11KB), `iasImage*`, `AppUpgrade`, `.lge.upgrade.xml`, `.whatsnew.tar.gz`, y el ZIP de mapas HERE (nueva versión `18.52.70.012.632.5`, +26,7MB).

**Why:** Sin acceso físico al HU no se puede descifrar nada — pero comparar ciphertext entre dos builds permite priorizar esfuerzo de descifrado futuro y confirmar que trabajo de RE ya hecho (p.ej. sobre `mango-vr_fixed.tar.gz`) sigue vigente sin reanálisis.

**How to apply:** Ante cada nueva versión descargada, repetir este diff `.ver` + `cmp` por offsets antes de invertir tiempo en descifrado — permite saber de antemano qué ficheros vale la pena descifrar primero.

Related: [[re-findings]] · [[project-context]] · [[vr-engine]] · [[gen5w-exploit]] · [[file-details]]
