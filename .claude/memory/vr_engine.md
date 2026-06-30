---
name: vr-engine
description: "Motor de reconocimiento de voz LPTE TTS v1.5.1, estructura interna de mango-vr_fixed.tar.gz, idiomas y análisis de los paquetes VR (vrau/vreu)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2f9fdbd7-182d-499f-807a-20ce446fa9ba
---

## Paquetes VR — Resumen

Dos regiones, cada una con un archivo original (cifrado/propietario) y un `_fixed` (gzip real accesible):

| Región | Original | Tamaño | Fixed | Tamaño |
|--------|----------|--------|-------|--------|
| **vrau** (Australia) | `mango-vr.tar.gz` (magic `fe 8e 43 ff`) | 43.2 MB | `mango-vr_fixed.tar.gz` | 544 MB |
| **vreu** (Europa) | `mango-vr.tar.gz` (magic `6e 61 69 eb`) | 62.9 MB | `mango-vr_fixed.tar.gz` | 2.20 GB |

El `_fixed` es un **parche post-build** que reemplaza al original para corregir un error de empaquetado o cifrado. Ambos `_fixed` son **gzip reales** (`1f 8b 08 00`) y extraíbles directamente con `tar xzf`.

## Estructura interna de mango-vr_fixed.tar.gz

```
vr_fixed/
└── LPTE/
    └── BASE/
        ├── VRM_ENV.ini           Configuración del VR Manager
        ├── JINIE.SYMBOL.DAT      Modelos de síntesis JINIE
        ├── SE.STT.ENV.DAT        Config Speech-To-Text
        ├── SE.SYMBOL.DAT         Símbolos del motor de habla
        ├── SE.TTS.ENV.DAT        Config Text-To-Speech
        ├── TIMA.ENV.DAT          Config motor TIMA
        ├── TIMA.SYMBOL.DAT       Modelos TIMA
        ├── TIMA2.ENV.DAT         Config TIMA v2
        ├── TIMA_NAVI_VR.ENV.DAT  Config TIMA para navegación
        ├── TIMA_NAVI2_VR.ENV.DAT
        ├── ASR/                  Automatic Speech Recognition por idioma
        │   ├── ENG/              (modelos acústicos .dat)
        │   ├── FRF/
        │   └── ...               (un subdirectorio por idioma)
        └── TTS/
            └── 1.5.1/
                └── languages/    TTS por idioma (modelos de voz .dat + .hdr)
```

## Motor TTS

- **LPTE v1.5.1** — motor propietario de síntesis de voz.
- Probable fabricante: **Cerence** (ex-Nuance), empresa líder en TTS para automoción.
- Motores ASR adicionales: **JINIE** y **TIMA** (incluyendo TIMA v2 y variante para navegación).

## Idiomas (vreu) — 24 idiomas europeos

| Código | Idioma | Código | Idioma |
|--------|--------|--------|--------|
| `bgb` | Búlgaro | `plp` | Polaco |
| `czc` | Checo | `ptp` | Portugués |
| `dad` | Danés | `ror` | Rumano |
| `dun` | Neerlandés | `rur` | Ruso |
| `eng` | Inglés | `hrh` | Croata |
| `fif` | Finlandés | `huh` | Húngaro |
| `frf` | Francés | `sks` | Eslovaco |
| `ged` | Alemán | `sls` | Esloveno |
| `grg` | Griego | `sws` | Sueco |
| `spe` | Español | `iti` | Italiano |
| `kok` | Coreano | `non` | Noruego |
| `trt` | Turco | `uku` | Ucraniano |

## Idiomas (vrau) — 1 idioma

- Solo `kok` (Coreano). La VR de Australia se centra en la comunidad coreana.

## md5sum.txt — dato forense

Los ficheros `md5sum.txt` (200 B) contienen la ruta completa del build server:
```
<md5>  */data001/vc.integrator/__EVENT_BUILD_s5w.25ru2.250702_MASS_PRODUCT_25RU2_001_251204134526/build-mango/BUILD/deploy/images/5w/usb/HU/images/vr[au|eu]/mango-vr_fixed.tar.gz
```
Útil para correlacionar rutas al analizar el rootfs.

## Datos VR para POI (dentro del ZIP de mapas HERE)

En `S5W_MAP_ALL_EUR_*.zip → vr/` (763 MB total):
- **`vr/POI/LEX/`**: diccionarios fonéticos `.LEX.DAT` por país e idioma para búsqueda de POI por nombre (e.g. `DEU.GED.LEX.DAT` = 87 MB — todos los POI de Alemania en alemán).
- **`vr/CATEGORY/`**: categorías de POI reconocibles por voz en 7 idiomas: ENG, DUN, FRF, GED, ITI, RUR, SPE.
- **`vr/SDCARD_ENV.ini`**: `SDCARD=1` — indica que los datos están en almacenamiento externo (SD/USB), no en la partición interna.

Related: [[project-context]] · [[haf-format]] · [[file-details]]
