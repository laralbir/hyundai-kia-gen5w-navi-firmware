# Comparación de versiones — `251204` vs `260128`

Análisis del segundo paquete de firmware descargado (`/Users/carlos/Downloads/NaU/Rio_MY22_EU`) frente al ya presente en el repositorio.

| Campo | Versión anterior | Versión nueva |
|---|---|---|
| Versión completa | `YB_22.EUR.S5W_L.001.001.251204` | `YB_22.EUR.S5W_L.001.001.260128` |
| Fecha de build | 2025-12-04 | 2026-01-28 |
| Entradas en `.ver` | 19328 (record IDs 308413–308447) | 21246 (record IDs 341072–341106) |
| Mapa HERE EUR | `18.49.56.023.631.5` | `18.52.70.012.632.5` (+26,7 MB) |
| Ruta origen | repo (`Rio_MY22_EU/`) | `/Users/carlos/Downloads/NaU/Rio_MY22_EU` |

Ambos manifiestos `.ver` contienen los mismos 35 ficheros — sin altas ni bajas salvo el rename esperado del ZIP/MD5 de mapas por el bump de versión HERE.

## Metodología

Como ningún fichero puede descifrarse sin acceso físico al HU (ver [[gen5w-exploit]] / `docs/gen5w_exploit_ecosystem.md`), la comparación se hizo **a nivel de ciphertext**: tamaño, checksum del `.ver`, y offset del primer byte divergente entre ambas versiones de cada fichero (`cmp`), más entropía de Shannon en los tramos que cambian. Esta técnica no revela contenido, pero sí la **estructura del contenedor de cifrado** — cuánta cabecera/trailer es estable entre builds y cuánto payload varía.

## Clasificación de los 35 ficheros del `.ver`

### A. Sin cambios (mismo checksum)
- `HU/firmware/frontkey/Checksum.txt`
- `HU/firmware/frontkey/nx4/MKBD_2_1f_00_NX4.bin`
- `HU/firmware/frontkey/us4hev/MKBD_2_22_00_US4.bin`
- `HU/images/mustwithcopy` (0 B)
- `HU/images/vrau/mango-vr_fixed.tar.gz` — **checksum idéntico**, byte a byte

El firmware del MCU del panel frontal (frontkey) no ha cambiado en absoluto entre builds.

### B. Mismo tamaño, checksum distinto, pero **payload idéntico + trailer final distinto** (~16.417 bytes)

| Fichero | Tamaño | Offset primer byte distinto | Bytes de trailer |
|---|---|---|---|
| `modem/eu/modem_eu.tar.gz` | 158.663.566 | 158.647.150 | 16.417 |
| `modem/eu_le22/modem_eu_le22.tar.gz` | 347.035.946 | 347.019.530 | 16.417 |
| `modem/au_le22/modem_au_le22.tar.gz` | 127.833.765 | 127.817.349 | 16.417 |
| `images/vrau/mango-vr.tar.gz` | 45.277.108 | 45.260.692 | 16.417 |

En los cuatro casos el **99%+ del fichero es bit a bit idéntico** entre versiones; solo cambia un bloque final de exactamente 16.417 bytes. Ese trailer tiene entropía de Shannon **7,98/8 bits** (aleatorio, sin cabeceras ASN.1/DER reconocibles) — consistente con una **firma/HMAC criptográfico que se regenera en cada build** (re-sellado), no con un cambio funcional del contenido. Los binarios de módem y el paquete de voz australiano **no cambiaron funcionalmente** en esta release.

### C. Mismo tamaño, cabecera fija idéntica + resto completamente re-generado

| Fichero | Tamaño | Cabecera idéntica | Resto |
|---|---|---|---|
| `HU/images/iasImage` (y `_1280`, `_1920_12`, `_p5`) | 6.226.728 | 14.048 bytes | 100% distinto |
| `HU/images/iasImage_*_sub` | 6.210.308 | 14.122 bytes | 100% distinto |
| `AppUpgrade` | 10.803.676 | 640 bytes | 100% distinto |
| `.lge.upgrade.xml` | 17.670 | 112 bytes | 100% distinto |

Estos ficheros sí tienen contenido realmente distinto (no solo re-firmado): la cabecera fija (probablemente magic/versión de formato de contenedor, en claro o en el primer bloque cifrado con IV determinista) se mantiene, pero el cuerpo cambia por completo. Compatible con re-cifrado con nuevo IV/clave de sesión sobre contenido distinto, o con AES-CBC donde el primer bloque de texto plano (cabecera de formato) es igual en ambos builds y el resto del plaintext ya diverge.

### D. Tamaño y checksum distintos (contenido + tamaño cambiados)

| Fichero | Tamaño anterior | Tamaño nuevo | Δ |
|---|---|---|---|
| `.whatsnew.tar.gz` | 291.740 | 283.607 | −8.133 |
| `HU/firmware/update.tar.gz` | 42.115.857 | 42.117.462 | +1.605 |
| `HU/images/mango-rootfs.tar.gz` | 879.017.907 | 879.126.179 | +108.272 |
| `HU/images/mango-rwdata.tar.gz` | 16.729.521 | 16.737.478 | +7.957 |
| `HU/images/new_gui.tar.gz` | 2.091.222.091 | 2.091.942.021 | +719.930 |
| `HU/images/navi_eu/appnavi.tar` | 510.500.900 | 511.361.060 | +860.160 |
| `HU/images/vreu/mango-vr.tar.gz` | 65.932.656 | 65.921.476 | −11.180 |
| `HU/images/vreu/mango-vr_fixed.tar.gz` | 2.365.067.314 | 2.365.067.377 | +63 |
| `HU/images/navi_eu/S5W_MAP_ALL_EUR_*.zip` | 17.889.556.253 | 17.916.293.755 | +26.737.502 (nuevo mapa HERE) |

**`update.tar.gz` diverge desde el byte 0** (sin cabecera común) — cambio de contenido real, coherente con un firmware principal actualizado.

**`vreu/mango-vr_fixed.tar.gz` es el único fichero accesible sin descifrar de este grupo** (gzip real). Se comparó el listado interno (`tar tzvf`) de ambas versiones: **mismos 351 entradas, mismos nombres, mismos tamaños exactos**. La única diferencia es el `mtime` embebido en cada entrada del tar: `23 sept. 2025` → `10 dic. 2025`. Es decir, **ningún asset de voz (vreu) cambió de contenido** en esta release — el `.tar.gz` se reempaquetó (nueva fecha de build) sin tocar payload, y los 63 bytes de diferencia de tamaño son ruido del contenedor gzip (mtime del header gzip / recompresión), no datos nuevos.

## Conclusiones para la estrategia de RE

1. **Frontkey MCU y VR Australia/Europa (payload) no han cambiado** — el trabajo de RE ya hecho o pendiente sobre `mango-vr_fixed.tar.gz` (ver [[vr-engine]]) sigue siendo válido para esta versión sin reanálisis.
2. **Los binarios de módem (`modem_eu*`, `modem_au_le22`) no cambiaron funcionalmente**, solo su firma final — no es necesario re-analizarlos si se llegan a descifrar en el futuro; basta con descifrar una vez y reutilizar para ambas versiones (salvo el trailer).
3. **Cambios reales de contenido** están en: `update.tar.gz`, `mango-rootfs.tar.gz`, `mango-rwdata.tar.gz`, `new_gui.tar.gz`, `appnavi.tar`, `vreu/mango-vr.tar.gz` (original, no el fixed), `iasImage*`, `AppUpgrade`, `.lge.upgrade.xml`, `.whatsnew.tar.gz`, y el ZIP de mapas (nueva versión HERE `18.52.70.012.632.5`). Si se obtiene acceso físico al HU (`DecryptToPIPE` + `decryption_key.der`), estos son los ficheros prioritarios a descifrar y diffear — el resto es ruido de re-firmado.
4. **Técnica de "prefix/suffix leak"**: comparar dos builds del mismo contenedor cifrado (mismo tamaño, checksum distinto) permite localizar cabeceras/trailers fijos sin necesidad de la clave. Aplicable a futuras versiones para acotar rápidamente qué cambió antes de invertir en descifrado completo.
5. El número de entradas del `.ver` crece de forma constante entre builds (19328→21246, +1918) pese a tener el mismo número de ficheros de usuario (35) — sugiere que el `record_id`/índice interno del build system (`vc.integrator`) es acumulativo across todo el histórico de builds de la plataforma, no específico de este paquete.

Related: [[re-findings]] · [[project-context]] · [[vr-engine]] · [[gen5w-exploit]] · [[file-details]]
