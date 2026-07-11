---
name: reference-ndsev-github
description: "Organización pública en GitHub de la NDS Association (github.com/ndsev) — implementación de referencia exacta del algoritmo de coordenadas NDS (WGS84↔Morton↔PackedTileId), BSD-3-Clause"
metadata:
  node_type: memory
  type: reference
---

`github.com/ndsev` — organización pública de la **NDS Association** (Navigation Data Standard e.V.), de la que **HERE es miembro** ("HERE Navigation Map delivers NDS promise of compatibility and interoperability", nds-association.org). 29 repositorios, licencia BSD-3-Clause en los relevantes para este proyecto.

## Repos más útiles para RE de `.hafr`/`.hafp`/`.haftlt`

- **`ndslive-math`** — implementación de referencia EXACTA (no descripción textual de patente) de:
  - WGS84 ↔ coordenadas enteras NDS (`x`=32 bits con signo para longitud, `y`=31 bits con signo para latitud)
  - Código Morton (Z-order, intercalado de bits, 63 bits útiles)
  - `PackedTileId` (tile ID de 32 bits con nivel codificado en bits altos; nivel 15 da valores negativos) — incluye `SouthWestCorner()`, `Size()`, `GetTileIdsForBoundingBox()`
  - Disponible en Python, C++, Go, Java, Rust, con vectores de prueba cruzados (`test-vectors/parity_vectors.json`) para verificar cualquier reimplementación
- **`mapget`** — cliente/servidor de datos de mapa NDS.Live en caché
- **`erdblick`** — visor de mapas NDS.Live real (mapget + deck.gl)
- **`zserio`** — framework de serialización que usa NDS (probablemente NO es lo que usa `HAF` — nuestros ficheros no tienen cabeceras zserio reconocibles — pero confirma el ecosistema)

## Cómo se usó (sesión 2026-07-11)

Se reimplementó el algoritmo de Morton/WGS84 a mano en Python (NO se ejecutó el código descargado directamente — el harness de seguridad bloqueó correctamente esa acción por ser código de terceros elegido autónomamente, no nombrado por el usuario). Verificado con roundtrip (Madrid). Probado con rigor (784 radares DGT reales, prueba de permutación) contra `linked_records`, `.hafr` y `.hafp03` — negativo en los tres, pero con certeza ahora de que el algoritmo probado es el exacto, no una aproximación. Detalle completo: `docs/nds_public_reference.md`.

## Reutilizable para

Cualquier intento futuro de decodificar coordenadas en el paquete HERE de este proyecto — usar `PackedTileId` (32 bits + delta pequeño relativo a su esquina) en vez de seguir buscando un Morton completo de 63 bits, que ya se probó exhaustivamente sin éxito.

Related: [[haf_format]] · [[project_radar_db]] · [[reference_dgt_radar_dataset]]
