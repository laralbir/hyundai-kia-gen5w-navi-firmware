---
name: haf-format
description: "HERE Automotive Format (HAF) — estructura de cabecera, extensiones de fichero, SPEED_PATCH.db schema, y análisis técnico de los mapas HERE Europa"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2f9fdbd7-182d-499f-807a-20ce446fa9ba
---

## HERE Automotive Format (HAF)

Formato propietario de HERE para datos cartográficos embebidos. Sin spec pública.

### Cabecera común a todos los ficheros HAF binarios
```
Bytes 0x00–0x1F:  "FORMAT_VERSION_XX.XX.XX\0..." (32 bytes, null-padded)
Bytes 0x40–0x5F:  "DATA_VERSION_YYYY.MM.DD.HH\0..." (32 bytes, null-padded)
Bytes 0x80+:      Payload binario específico del tipo
```

### Extensiones y contenido

| Extensión | Significado | Tamaño en este paquete |
|-----------|-------------|------------------------|
| `.hafp` | HAF Partition — tiles cartográficos principales | ~10.6 GB (14 partes) |
| `.hafr` | HAF Route — grafo de routing | 921 MB |
| `.hafaip` | HAF ADAS Info Partitions — horizonte electrónico | ~2.86 GB (4 partes) |
| `.hafgsi` | HAF Global Spatial Index — índice espacial R-tree | 274 MB |
| `.hafls` | HAF Local Safety — cámaras velocidad pan-EU | 80 MB |
| `.haftlt` | HAF Traffic Local Threats — radares por país | 2–11 MB/país |
| `.hafmma` | HAF MultiMedia Assets — 3D, texturas ASTC, sprites | varios |
| `.hafwmd` | HAF World Map Data — mapa mundo baja res | 2.7 MB |
| `.hafbc` | HAF Basic Conditions — vel. default por país | 3.6 KB (ASCII!) |
| `.hafcc` | HAF Country Configuration | 299 KB |

### Estructura del paquete de mapas
```
S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip (16.7 GB comprimido, ~32 GB descomprimido)
├── Data/Nation/EUR/
│   ├── MAP/    Ficheros .hafp, .hafr, .hafaip, .hafgsi, .hafls, .haftlt, .hafmma, .hafwmd, .hafbc, .hafcc
│   ├── NI/     Navigation Intelligence — JSONs de configuración
│   ├── RES/    Recursos: skins (.skn), sonidos (.wav), tráfico (.alt), DEM (.cad)
│   └── SEARCH/ Categorías POI
├── vr/         Diccionarios fonéticos ASR y categorías VOZ (763 MB)
├── GlobalImage/ Assets UI globales, speed limit PNGs (185 KB)
└── Text.Info/  Licencias open source (COPYRIGHT.TXT)
```

## SPEED_PATCH.db (160 MB descomprimido)

Base de datos **SQLite 3** con límites de velocidad por segmento. Directamente accesible con `sqlite3`.

- Versión formato: `1.0.1.0`; datos: `2025072316` (23 julio 2025)
- **10.353.101 registros**

```sql
CREATE TABLE VERSION_INFO (FORMAT_VERSION TEXT, DATA_VERSION TEXT);

CREATE TABLE SPEED_PATCH (
    LINK_ID      INT64,   -- ID segmento HERE (clave foránea en .hafp)
    DIR          INT,     -- 0=A→B, 1=B→A, 2=ambos sentidos
    SP_LIMIT     INT,     -- km/h
    VEHICLE_TYPE INT,     -- máscara de bits (ver tabla abajo)
    PRIMARY KEY (LINK_ID, DIR, VEHICLE_TYPE)
) WITHOUT ROWID;
```

**VEHICLE_TYPE máscara:** 0=todos, 7=coche+moto+ciclomotor, 15=+veh. pesados ligeros, 23=+camiones, 31=+autobuses, 127=todos los tipos.

**DIR:** 0=sentido digitalización A→B, 1=B→A, 2=ambos.

**Distribución de límites:**
- 50 km/h: 3.77M registros (urbano predominante)
- 30 km/h: 1.48M · 90 km/h: 1.36M · 80 km/h: 957K

## Radares y seguridad vial

**HAFTLT/** — 13 ficheros por país (formato HAF v1.04.02, julio 2025):
DEU (10.94 MB), ITA (11.25 MB), FRA (9.46 MB), GBR (9.47 MB), SPN (5.49 MB), CZE (5.71 MB), CHE (4.11 MB), NOR (3.94 MB), SWE (3.75 MB), AUT (2.71 MB), DNK (2.18 MB), BEL (1.82 MB), NLD (1.93 MB).

TLT = **Traffic Local Threats** (terminología HERE para cámaras fijas y control de velocidad media).

**VIT_EUR.hafls** (80 MB) — Safety layer pan-europeo (HAF v1.00.01, julio 2025).

**Sonidos alerta radar** (`CT000009_HIGH/MID/LOW.wav`, 41.538 B c/u): `CT` = Camera Trap. Progresión LOW→MID→HIGH según se aproxima la cámara.

## Tráfico histórico (.alt)

24 países, 2 ficheros cada uno (`_IMP.alt` mph, `_MET.alt` km/h).
Magic: `"ALERT_C\0"` (8 bytes). Todos fechados **14 julio 2021** (datos estadísticos, no tiempo real).
Países: BGR, CZE, DNK, DEU, ESP, FIN, FRA, GBR, GRC, HRV, HUN, ITA, KOR, NLD, NOR, POL, PRT, ROU, RUS, SVK, SVN, SWE, TUR, UKR.

## ADAS — Horizonte electrónico (.hafaip)

~2.86 GB total (4 particiones). HAF v1.07.01, datos 16 julio 2025.
Contiene: pendientes, radios de curvatura, límites de velocidad enlazados, atributos de vía avanzados.
Alimenta: **SCC** (crucero predictivo de pendientes), **LKAS** (asistencia de carril), **ISA** (velocidad asistida inteligente).

## Software de terceros confirmados (COPYRIGHT.TXT)

| Componente | Función relevante para RE |
|------------|--------------------------|
| **Rijndael (AES)** | Cifrado de archivos OTA — **confirma AES** |
| **SQLite** | Motor de SPEED_PATCH.db — accesible directamente |
| **Anti-Grain Geometry 2.4** | Renderizado 2D vectorial |
| **Mesa3D** | OpenGL API — GPU compatible con OpenGL ES / Vulkan |
| **Texturas ASTC** | GPU embebida soporta Adaptive Scalable Texture Compression |

## Configuración JSON (NI/)

- **`RpOption.json`** v23 (2025-02-18): 5 modos de ruta — Fastest(31), Recommended(32), Economic(33), Prefer motorway(34), Avoid tolls(35). Variante `_AAOS` para Android Automotive OS.
- **`RpAvoidOption.json`**: evitar autopistas(11), vignette(12), ferrys(13), restricciones horarias(14), peajes(15), túneles(16), HOV(17), sin asfaltar(18). Variante Turkey separada.
- **`ServerURL.json`**: URLs de GIS/TIS/TIT vacías (`EU_URL=""`) — paquete completamente offline. `EU_SSL: 1` → HTTPS cuando se configure.
- **`SEARCH/CATEGORY_EU.json`** v1.2.8: Kia(0xD080), Hyundai(0xC080), Genesis(0xE080) con categorías dedicadas. Soporte EV charging (Shell Recharge, ChargePoint, etc.).

## UI y assets visuales

- **5 temas de mapa** (.skn, 118 KB c/u): BLACK, SIMPLENIGHT, SIMPLEBROWN, SIMPLEWHITE, SMARTBROWN
- **Paletas de renderizado** (.hafmma): LATTE, MILK, MOCHA (intensidades de contraste)
- **DEM** `VIT_AREA_DATA_HM.cad` (877 MB): elevación digital para relieve 3D y cálculos ADAS de pendiente
- **Junction Exit View**: fotos reales de salidas de autopista (funcionalidad premium HERE)
- **Señales de velocidad**: `GlobalImage/SpeedLimit/speed_limit_0-9.png` + `_red_` (dígitos compuestos en pantalla)

Related: [[project-context]] · [[vr-engine]] · [[file-details]]
