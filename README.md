# Hyundai / Kia Standard Gen5W Navigation — Firmware RE

Reverse engineering of the **Standard Gen5W Navigation** head unit firmware, EU variant.  
This device is shared across multiple Hyundai and Kia models (e.g. Kia Rio MY22, and others).

---

## Device & firmware

| Field | Value |
|---|---|
| Device | Standard Gen5W Navigation (HU) |
| SoC / board | **mango** |
| SW version | **S5W** (5th gen) |
| Full version | `YB_22.EUR.S5W_L.001.001.251204` |
| Region | EUR (Europe) |
| Build type | `MASS_PRODUCT` |
| Build date | 2025-12-04 13:45:26 |
| Release | `25RU2_001` |
| OS | Embedded Linux |

---

## Repository contents

```
.
├── CLAUDE.md                        AI assistant context & project instructions
├── docs/
│   ├── estructura_ficheros.md       Full file tree with sizes, magic bytes and RE notes
│   └── analisis_mapas_here.md       Deep technical analysis of the HERE Maps package
└── .claude/memory/                  AI memory files (RE findings, formats, VR engine…)
```

> Large binary files (firmware images, maps, VR packages) are excluded via `.gitignore`.

---

## Firmware package overview

| Component | Size | Status |
|---|---|---|
| HERE Maps Europe (`S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip`) | 16.66 GB | AES encrypted |
| VR Europe — `mango-vr_fixed.tar.gz` | 2.20 GB | **gzip — accessible** |
| GUI update — `new_gui.tar.gz` | 1.99 GB | AES encrypted |
| Root filesystem — `mango-rootfs.tar.gz` | 838.4 MB | AES encrypted |
| VR Australia — `mango-vr_fixed.tar.gz` | 544 MB | **gzip — accessible** |
| Navigation app — `appnavi.tar` | 487 MB | AES encrypted |
| Modem EU LE22 | 331.1 MB | AES encrypted |
| Main firmware — `update.tar.gz` | 40.2 MB | AES encrypted |
| Boot images — `iasImage` (×12) | ~73.8 MB | AES / IAS format |
| Frontkey MCU (×2) | ~384 KB | ARM Cortex-M — accessible |
| **Total** | **~22.5 GB** | |

---

## Key RE findings

- **Encryption:** AES/Rijndael confirmed via `COPYRIGHT.TXT` inside the HERE Maps package. Decryption key is likely hardcoded or VIN/IMEI-derived inside the HU rootfs.
- **Only files accessible without decryption:** `mango-vr_fixed.tar.gz` (both regions, real gzip) and the frontkey MCU `.bin` files (ARM Cortex-M).
- **HERE Maps format:** Proprietary HAF (HERE Automotive Format). `SPEED_PATCH.db` is a standard SQLite 3 database with 10.3 million speed-limit records by road segment.
- **VR engine:** LPTE TTS v1.5.1 (likely Cerence/ex-Nuance). 24 European languages in the EU package; Korean only in the AU package.
- **iasImage format:** Probable IAS (Image Authentication Subsystem) — signed/encrypted secure boot images. Does not match U-Boot, FIT/DTB, or zImage magic bytes.

---

## Docs

- [File structure & RE notes](docs/estructura_ficheros.md) — complete file tree with sizes, magic bytes, and analysis per component.
- [HERE Maps technical analysis](docs/analisis_mapas_here.md) — HAF format, `SPEED_PATCH.db` schema, radar databases, ADAS horizon data, VR dictionaries, UI assets, and third-party software inventory.

---

## Disclaimer

This repository contains documentation and analysis only — no firmware binaries, map data, or copyrighted assets are included.  
All reverse engineering is conducted for interoperability and research purposes.
