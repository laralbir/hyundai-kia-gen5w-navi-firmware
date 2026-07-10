# Análisis técnico y de negocio — Paquete de mapas HERE Europa

**Fichero:** `HU/images/navi_eu/S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip`  
**Tamaño:** 16.66 GB comprimido · ~32 GB descomprimido  
**Proveedor:** HERE Maps  
**Región:** Europa — 47 países  
**Versión cartográfica:** `EUR.18.49.56.023.631.5`  
**Fecha datos:** Julio–Septiembre 2025  
**MD5:** `b00d66e5536ba37297bd6c3e1b7e0993`

---

## 1. Estructura general del ZIP

El paquete contiene 1.335 ficheros organizados en 4 secciones raíz:

| Sección         | Tamaño descomprimido | Descripción                              |
|-----------------|----------------------|------------------------------------------|
| `Data/`         | ~31.4 GB             | Datos cartográficos, configuración, UI   |
| `vr/`           | ~763 MB              | Datos de reconocimiento de voz para POI  |
| `GlobalImage/`  | ~185 KB              | Assets UI globales (iconos, banderas)    |
| `Text.Info/`    | ~140 KB              | Licencias de componentes de terceros     |

Dentro de `Data/`, toda la información de Europa está bajo `Data/Nation/EUR/` y se divide en:

```
Data/Nation/EUR/
├── MAP/        Ficheros cartográficos binarios (HAF format)
├── NI/         Navigation Intelligence — configuración JSON
├── RES/        Recursos: skins, sonidos, tráfico
└── SEARCH/     Categorías de búsqueda de puntos de interés
```

---

## 2. Formato HAF (HERE Automotive Format)

Todos los ficheros binarios propietarios de HERE comparten un formato de cabecera común:

```
Bytes 0x00–0x1F:  "FORMAT_VERSION_XX.XX.XX\0..." (32 bytes, null-padded)
Bytes 0x40–0x5F:  "DATA_VERSION_YYYY.MM.DD.HH\0..." (32 bytes, null-padded)
Bytes 0x80+:      Payload binario específico del tipo de fichero
```

La extensión del fichero identifica el tipo de datos:

| Extensión  | Significado probable                              | Tamaño en este paquete |
|------------|---------------------------------------------------|------------------------|
| `.hafp`    | HAF Partition — datos cartográficos principales   | ~10.6 GB (14 partes)   |
| `.hafr`    | HAF Route — datos de routing/topología            | 921 MB                 |
| `.hafaip`  | HAF ADAS Info Partitions — datos ADAS/horizonte   | ~2.86 GB (4 partes)    |
| `.hafgsi`  | HAF Global Spatial Index — índice espacial global | 274 MB                 |
| `.hafls`   | HAF Local Safety — cámaras de velocidad           | 80 MB                  |
| `.haftlt`  | HAF Traffic Local Threats — radares por país      | 2–11 MB por país       |
| `.hafmma`  | HAF MultiMedia Assets — imágenes/modelos 3D       | varios                 |
| `.hafwmd`  | HAF World Map Data — mapa mundo a baja resolución | 2.7 MB                 |
| `.hafbc`   | HAF Basic Conditions — límites genéricos de vel.  | 3.6 KB                 |
| `.hafcc`   | HAF Country Configuration — config por país       | 299 KB                 |

Todos los ficheros HAF binarios se crean con la toolchain interna de HERE y no tienen decodificadores públicos. El formato varía ligeramente por tipo de datos, pero la cabecera es común a todos.

---

## 3. Datos cartográficos principales

### 3.1 Particiones de mapa (`VIT_EUR.hafp`, `hafp01`–`hafp13`)

El mapa base de Europa está dividido en 14 ficheros de partición. Cada partición contiene tiles geoespaciales con:

- Geometría de carreteras (trazado vectorial de calles, autopistas, caminos)
- Nombres de calles, ciudades y puntos de referencia en múltiples idiomas
- Restricciones de giro y dirección de tráfico
- Atributos de carreteras: número de carriles, tipo de vía, peaje, velocidad permitida base
- Datos de búsqueda de puntos de interés (POI)

La partición de un país complejo como Alemania o Francia ocupa varios GB en las particiones principales.

### 3.2 Routing (`VIT_EUR.hafr` · 921 MB)

Contiene el grafo de navegación: la red de arcos y nodos que usa el motor de cálculo de rutas. Es un grafo dirigido donde cada arco representa un segmento de carretera con su coste de traversal (tiempo, distancia, peaje, restricciones horarias).

Separado del mapa visual para poder actualizar la cartografía sin recalcular el routing, y viceversa.

### 3.3 Índice espacial global (`VIT_EUR.hafgsi` · 274 MB)

Índice R-tree o similar que mapea coordenadas geográficas (lat/lon) a offsets dentro de las particiones `.hafp`. Permite al motor de navegación encontrar en tiempo real qué tile cargar cuando el vehículo está en una posición determinada.

### 3.4 Mapa mundial (`VIT_EUR_WORLDMAP.hafwmd` / `VIT_EUR_WORLDMAP_IMAGE.hafmma`)

- **`.hafwmd`** (2.7 MB): Datos vectoriales del mapa-mundo para la vista de zoom máximo (continentes, países, capitales). Actualizado el 25 de julio de 2025.
- **`.hafmma`** (341 MB): Imagen rasterizada del mapa-mundo para la vista satélite/general. Fecha de 2019 — este asset raramente cambia.

---

## 4. Límites de velocidad

El sistema gestiona los límites de velocidad mediante tres capas complementarias:

### 4.1 `VIT_EUR.hafbc` — Límites base por país (3.6 KB · texto plano)

Fichero ASCII con los límites de velocidad por defecto para cada uno de los 47 países europeos. Formato de columnas fijas:

```
ID  CODIGO  PREFIJO  ITV  VEL_AUTOPISTA  VEL_CARRETERA  VEL_URBANO  RADARES_LEG  ISO  ...
1000000 ALB    355     1        110             80              40          0      AL  110  80  40  ...
3000000 AUT     43     1        130            100              50          1      AT  130 100  50  ...
```

Campos relevantes:
- `VEL_AUTOPISTA / VEL_CARRETERA / VEL_URBANO`: límites genéricos en km/h para cada tipo de vía
- `RADARES_LEG` (campo booleano): `1` = las alertas de radar son legales en ese país, `0` = ilegales
- Los valores `-1` indican "sin límite legal" (p.ej. autopistas alemanas sin restricción)

Países con alertas de radar legales (`1`): Austria, Bulgaria, Chequia, Suiza, Hungría, Finlandia, Lituania, Suecia, entre otros.

### 4.2 `SPEED_PATCH.db` — Parches de velocidad por segmento (160 MB descomprimido · SQLite 3)

Base de datos SQLite que sobreescribe los límites del mapa base con valores específicos por segmento de carretera. Es el nivel más granular del sistema.

**Versión:** formato `1.0.1.0`, datos `2025072316` (generado el 23 de julio de 2025 a las 16:00h)

**Esquema:**
```sql
CREATE TABLE VERSION_INFO (
    FORMAT_VERSION TEXT,
    DATA_VERSION   TEXT
);

CREATE TABLE SPEED_PATCH (
    LINK_ID      INT64,   -- ID del segmento de carretera en la base cartográfica HERE
    DIR          INT,     -- Dirección: 0=sentido A→B, 1=sentido B→A, 2=ambos
    SP_LIMIT     INT,     -- Límite de velocidad en km/h
    VEHICLE_TYPE INT,     -- Máscara de bits: tipos de vehículo a los que aplica
    PRIMARY KEY (LINK_ID, DIR, VEHICLE_TYPE)
) WITHOUT ROWID;
```

**Estadísticas:**
- **10.353.101 registros** — cubre segmentos en toda Europa
- Límite más frecuente: **50 km/h** (3.77M registros) — velocidad urbana predominante
- Otros frecuentes: 30 km/h (1.48M), 90 km/h (1.36M), 80 km/h (957K)

**Decodificación de `VEHICLE_TYPE`** (máscara de bits acumulativa):

| Valor | Tipos de vehículo cubiertos                          |
|-------|------------------------------------------------------|
| `0`   | Todos los vehículos (regla universal)                |
| `7`   | Coche + Moto + Ciclomotor                            |
| `15`  | Anterior + Vehículos pesados ligeros                 |
| `23`  | Anterior + Camiones                                  |
| `31`  | Anterior + Autobuses                                 |
| `55`  | Anterior + Vehículos de emergencia                   |
| `63`  | Todos excepto categorías especiales                  |
| `127` | Todos los tipos de vehículo                          |

Los registros con `VEHICLE_TYPE=7` (solo coches/motos) son los más frecuentes para zonas donde los camiones tienen límites distintos.

**Decodificación de `DIR`:**
- `0` = sentido de digitalización del segmento (A→B)
- `1` = sentido contrario (B→A)
- `2` = ambas direcciones (vías de doble sentido con mismo límite)

### 4.2.1 ⚠️ El esquema cambia entre builds (descubierto 2026-07-10)

La versión de mapas `18.52.70.012.632.5` (build `260128`) usa un esquema **sin** `VEHICLE_TYPE`:

```sql
CREATE TABLE SPEED_PATCH (LINK_ID INT64, DIR INT, SP_LIMIT INT,
    PRIMARY KEY(LINK_ID, DIR)) WITHOUT ROWID;
-- 8.311.861 filas (frente a 10.353.101 en 18.49.56.023.631.5)
```

Cualquier herramienta que consulte esta tabla debe comprobar el esquema real
(`PRAGMA table_info(SPEED_PATCH)`) en vez de asumir la columna `VEHICLE_TYPE`
— ver `tools/camera_editor` para una implementación que se adapta a ambas
variantes automáticamente.

---

## 5. Datos de radares y seguridad vial

### 5.1 `HAFTLT/VIT_EUR_XXX.haftlt` — Radares por país

13 ficheros binarios en formato HAF v1.04.02, uno por país, fechados el 16 de julio de 2025:

| Fichero                   | País           | Tamaño       | Cobertura estimada      |
|---------------------------|----------------|--------------|-------------------------|
| `VIT_EUR_DEU.haftlt`      | Alemania       | 10.94 MB     | ~3.500 cámaras fijas    |
| `VIT_EUR_ITA.haftlt`      | Italia         | 11.25 MB     | ~3.600 cámaras          |
| `VIT_EUR_FRA.haftlt`      | Francia        | 9.46 MB      | ~4.000 cámaras (legales)|
| `VIT_EUR_GBR.haftlt`      | Reino Unido    | 9.47 MB      | ~7.000 cámaras          |
| `VIT_EUR_SPN.haftlt`      | España         | 5.49 MB      | ~2.000 cámaras          |
| `VIT_EUR_CZE.haftlt`      | Chequia        | 5.71 MB      | alta densidad relativa  |
| `VIT_EUR_CHE.haftlt`      | Suiza          | 4.11 MB      |                         |
| `VIT_EUR_NOR.haftlt`      | Noruega        | 3.94 MB      |                         |
| `VIT_EUR_SWE.haftlt`      | Suecia         | 3.75 MB      |                         |
| `VIT_EUR_AUT.haftlt`      | Austria        | 2.71 MB      |                         |
| `VIT_EUR_DNK.haftlt`      | Dinamarca      | 2.18 MB      |                         |
| `VIT_EUR_BEL.haftlt`      | Bélgica        | 1.82 MB      |                         |
| `VIT_EUR_NLD.haftlt`      | Países Bajos   | 1.93 MB      |                         |

El formato interno es binario comprimido. La cabecera contiene versión de formato y fecha. El sufijo `TLT` probablemente significa **Traffic Local Threats**, la terminología HERE para cámaras de velocidad fijas y tramos de control de velocidad media.

La ausencia de países como Polonia, Portugal, Grecia o Rumanía en esta carpeta no significa que carezcan de datos de radar — pueden estar incluidos en `VIT_EUR.hafls` (la capa pan-europea).

### 5.2 `VIT_EUR.hafls` — Safety layer europeo (80 MB)

Fichero HAF v1.00.01 de cobertura pan-europea, actualizado el 17 de julio de 2025. El sufijo `ls` corresponde a **Local Safety** (capa de seguridad local). Complementa los ficheros `.haftlt` por país, posiblemente incluyendo:

- Países no cubiertos individualmente en `HAFTLT/`
- Zonas de control de velocidad media (tramos)
- Semáforos con cámara

### 5.3 Sonidos de alerta de radar (`RES/SOUND/CT000009_*.wav`)

```
CT000009_HIGH.wav  41.538 B   Pitido agudo — alerta próxima/urgente
CT000009_LOW.wav   41.538 B   Pitido grave — alerta lejana
CT000009_MID.wav   41.538 B   Pitido medio — alerta a distancia media
```

El prefijo **`CT`** significa muy probablemente **Camera Trap**. Los tres ficheros tienen idéntico tamaño, lo que indica la misma duración con distintas frecuencias de tono. El sistema genera una progresión LOW→MID→HIGH a medida que el vehículo se aproxima a la cámara.

Otros sonidos del sistema:

| Fichero         | Probable función                                  |
|-----------------|---------------------------------------------------|
| `BR015.wav`     | Alerta de límite de velocidad superado (BR=Break) |
| `GD1000xx.wav`  | Instrucciones de guía de navegación (GD=Guidance) |
| `SE014.wav`     | Alerta de seguridad general (SE=Safety/Emergency) |

---

## 6. Datos ADAS (Advanced Driver Assistance Systems)

### 6.1 `VIT_EUR_ADAS.hafaip` + `hafaip01/02/03` (~2.86 GB total)

Formato HAF v1.07.01, datos del 16 de julio de 2025. El sufijo `aip` significa **ADAS Information Partitions**.

Contiene el **mapa de horizonte electrónico** (Electronic Horizon): datos de la carretera por delante del vehículo, utilizados por los sistemas ADAS para anticipar la geometría de la vía. Incluye:

- **Pendientes** (inclinación del perfil longitudinal) — para el control predictivo de crucero
- **Curvas** (radio de curvatura) — para ajuste anticipado de velocidad en curvas
- **Límites de velocidad** enlazados al segmento — capa alternativa al `SPEED_PATCH.db`
- **Atributos de vía** avanzados: número de carriles, intersecciones, ceda el paso

El tamaño (~2.86 GB) supera al propio archivo de routing (921 MB), lo que indica una densidad de datos muy alta: resolución submétrica en la geometría de carreteras.

Estos datos alimentan directamente funciones del Kia Rio MY22 como:
- **SCC (Smart Cruise Control)** con control predictivo de pendientes
- **LKAS (Lane Keeping Assist)** en combinación con la geometría de carril
- **ISA (Intelligent Speed Assistance)** — detección del límite legal en tiempo real

---

## 7. Tráfico histórico (`RES/TRAFFIC/VIT_XXX_YYY.alt`)

Para cada uno de los 24 países cubiertos hay dos ficheros `.alt`:
- `VIT_XXX_IMP.alt` — unidades imperiales (mph)
- `VIT_XXX_MET.alt` — unidades métricas (km/h)

**Formato interno** (confirmado por cabecera):
```
Magic:   "ALERT_C\0"   (8 bytes)
País:    "DEU\0..."    (24 bytes)
Unidad:  "IMP\0..."    (24 bytes)
Fecha:   "Jul 14 2021" (16 bytes)
Payload: datos binarios de velocidades históricas por tramo
```

Todos estos ficheros tienen fecha de **14 de julio de 2021** — son datos históricos de tráfico estadístico (patrones de velocidad real por hora del día y día de la semana), no en tiempo real. Se usan para el cálculo de ETAs y rutas más realistas cuando no hay cobertura de tráfico en tiempo real.

Los 24 países con datos de tráfico histórico son: Bulgaria, Chequia, Dinamarca, Alemania, España, Finlandia, Francia, Gran Bretaña, Grecia, Croacia, Hungría, Italia, Corea, Países Bajos, Noruega, Polonia, Portugal, Rumanía, Rusia, Eslovaquia, Eslovenia, Suecia, Turquía, Ucrania.

---

## 8. Interfaz de usuario y recursos visuales

### 8.1 Temas visuales (`RES/SKIN/VIT_EUR_CE_THEME_*.skn`)

5 temas de mapa disponibles, todos de 118 KB (mismo tamaño → misma estructura, diferente paleta):

| Fichero                             | Tema              |
|-------------------------------------|-------------------|
| `VIT_EUR_CE_THEME_BLACK.skn`        | Oscuro total      |
| `VIT_EUR_CE_THEME_SIMPLENIGHT.skn`  | Noche simplificada|
| `VIT_EUR_CE_THEME_SIMPLEBROWN.skn`  | Tierra simplificada|
| `VIT_EUR_CE_THEME_SIMPLEWHITE.skn`  | Día simplificado  |
| `VIT_EUR_CE_THEME_SMARTBROWN.skn`   | Tierra inteligente|

El fichero de imágenes asociadas (`VIT_EUR_CE_THEME_IMAGE.bin`, 80.6 MB) contiene los sprites y texturas compartidos por todos los temas.

Adicionalmente, los ficheros `.hafmma` de rendering (`LATTE`, `MILK`, `MOCHA`) son tres paletas de color para el renderizado del mapa 2D. Los nombres (cafés con leche, leche, café con leche oscuro) corresponden a intensidades de contraste del fondo del mapa.

### 8.2 Señales y símbolos

| Fichero                           | Contenido                                        |
|-----------------------------------|--------------------------------------------------|
| `VIT_EUR_SYMBOL_48.hafmma`        | Iconos POI 48×48 px (gasolineras, restaurantes…) |
| `VIT_EUR_EXTSYMBOL.hafmma`        | Iconos POI extendidos (marcas específicas)       |
| `VIT_EUR_EXTSYMBOL_ALL.hafmma`    | Versión completa de iconos de marcas             |
| `VIT_GOOGLE_LOGO_SYMBOL_48.hafmma`| Logo Google para resultados de búsqueda Google   |
| `VIT_HERE_LOGO_SYMBOL_48.hafmma`  | Logo HERE Maps                                   |

### 8.3 Señales de límite de velocidad (`GlobalImage/SpeedLimit/`)

20 imágenes PNG para mostrar el límite de velocidad en pantalla:
- `speed_limit_0.png` a `speed_limit_9.png` — dígitos 0–9 en fondo blanco (modo día)
- `speed_limit_red_0.png` a `speed_limit_red_9.png` — dígitos 0–9 en rojo (modo superación de límite)
- `bg_border_cross_speedlimit.png` — icono de cruce de frontera con cambio de límite

El HU compone el número de velocidad dígito a dígito usando estas imágenes.

### 8.4 Assets 3D

| Fichero                               | Contenido                                       |
|---------------------------------------|-------------------------------------------------|
| `VIT_EUR_3D_LANDMARK_ASTC.hafmma`     | Modelos 3D de monumentos/edificios emblemáticos |
| `VIT_EUR_JunctionExitView_BI.hafmma`  | Vistas reales de salidas de autopista (JEV)     |
| `VIT_EUR_3D_MODEL_SYM.hafmma`         | Modelos 3D de símbolos de carretera             |
| `VIT_EUR_3D_MODEL_SYM_CCIC.hafmma`   | Variante CCIC (Connected Car Integration)       |

Los **ASTC** (Adaptive Scalable Texture Compression) son texturas comprimidas específicas para GPUs móviles/embebidas — confirma que el HU usa una GPU compatible con OpenGL ES / Vulkan con soporte ASTC.

La **Junction Exit View** muestra fotografías reales de la salida de autopista en pantalla antes de llegar a ella — una funcionalidad premium de HERE presente en este sistema.

### 8.5 Elevación digital (`RES/SKIN/DEM/VIT_AREA_DATA_HM.cad` · 877 MB)

DEM = Digital Elevation Model. El fichero `.cad` contiene el mapa de altitudes en formato raster para toda Europa. Se usa para:
- Sombreado de relieve en el mapa 3D
- Visualización de montañas y valles
- Cálculos de pendiente para el sistema ADAS

---

## 9. Reconocimiento de voz para POI

### 9.1 Sección `vr/` (763 MB total)

Datos para que el sistema de voz del HU reconozca nombres de puntos de interés (POI) hablados por el usuario. Organizado en dos subsecciones:

**`vr/CATEGORY/`** — Categorías de POI reconocibles por voz, en 7 idiomas:
- ENG (Inglés), DUN (Neerlandés), FRF (Francés), GED (Alemán), ITI (Italiano), RUR (Ruso), SPE (Español)
- Cada idioma tiene: `CATEGORY_LIST.txt` + `[LANG]_vde.json` (Visual Display Entries)

**`vr/POI/LEX/`** — Diccionarios fonéticos para búsqueda de POI por nombre:
- Un fichero `.LEX.DAT` por país e idioma
- Ejemplos: `DEU.GED.LEX.DAT` (87 MB) — todos los nombres de POI en Alemania pronunciados en alemán
- `HOUSENUMBER.[LANG].LEX.DAT` — pronunciación de números de portal

El tamaño de estos diccionarios es enorme porque codifican fonéticamente cada nombre de calle, ciudad y POI para el ASR (Automatic Speech Recognition).

### 9.2 `vr/SDCARD_ENV.ini`

```
[ENV]
SDCARD=1
```

Flag que indica al sistema de VR que los datos están en tarjeta SD/almacenamiento externo (no en la partición interna del HU).

---

## 10. Configuración de negocio (JSONs de NI/)

### 10.1 Opciones de ruta (`RpOption.json` v23, actualizado 2025-02-18)

5 criterios de cálculo de ruta, disponibles para vehículos en Europa (`"EU": 7`):

| key | Nombre         | Descripción                                             |
|-----|----------------|---------------------------------------------------------|
| 31  | Fastest        | Menor tiempo de trayecto                                |
| 32  | Recommended    | Balance tiempo/distancia, priorizando vías anchas       |
| 33  | Economic       | Menor coste económico (combustible + peajes)            |
| 34  | Prefer motorway| Prioriza autopistas aunque sea más largo                |
| 35  | Avoid tolls    | Rutas sin peaje                                         |

### 10.2 Opciones de evitación (`RpAvoidOption.json`)

| key | Evitar                   |
|-----|--------------------------|
| 11  | Autopistas               |
| 12  | Vías con vignette        |
| 13  | Ferrys                   |
| 14  | Vías con restricción horaria |
| 15  | Vías de peaje            |
| 16  | Túneles                  |
| 17  | Carriles HOV/compartidos |
| 18  | Vías sin asfaltar        |

Existe una variante `_AAOS` (Android Automotive OS) para cada fichero, con un subconjunto diferente de opciones — indicando compatibilidad dual con el SO nativo del HU y con Android Automotive.

Turquía tiene sus propias variantes de evitación (`RpAvoidOption_Turkey.json`), por requisitos legales específicos.

### 10.3 Categorías de POI (`SEARCH/CATEGORY_EU.json` v1.2.8)

Define qué categorías de puntos de interés son buscables. Las marcas del grupo Hyundai Motor tienen categorías dedicadas:
- **Genesis** (símbolo `0xE080`) — concesionarios y servicios Genesis
- **Hyundai** (símbolo `0xC080`) — concesionarios, servicios y cargadores Hyundai
- **Kia** (símbolo `0xD080`) — concesionarios y servicios Kia

Otras categorías relevantes: EV charging stations, petrol stations, service areas, rest areas.

El sistema tiene soporte especial para **cargadores de vehículo eléctrico** con múltiples redes (Shell Recharge, ChargePoint, etc.) — coherente con que el Kia Rio MY22 comparte plataforma con variantes EV/HEV.

### 10.4 Conectividad y servidores (`ServerURL.json`)

Define tres tipos de servicios online, tanto para Hyundai como para Kia:

| Tipo | Función                             |
|------|-------------------------------------|
| GIS  | Geographic Information Service      |
| TIS  | Traffic Information Service         |
| TIT  | Traffic Information Transmission    |

**Todos los campos `EU_URL` están vacíos** — este paquete es completamente offline. Las URLs se configuran a través de un mecanismo separado (probablemente el `mango-rwdata.tar.gz` o la configuración del módem/conectividad). El campo `EU_SSL: 1` confirma que cuando se usan, la comunicación es HTTPS.

### 10.5 NaviVision (`NaviVisionSchedule.json`)

Controla cuándo se activa la superposición de cámara en tiempo real sobre el mapa (función de realidad aumentada de la navegación):

- **Plataforma:** `ccNC` (Connected Car Navigation Computer — la plataforma gen. anterior al mango)
- **Vehículos compatibles:** `MV1` y `SX2 EV`
- **Ventanas de activación:** 00:00–00:30, 01:00–05:30, 15:10–23:50

Las ventanas de activación excluyen las horas punta (08–15 y parte de la tarde) — posiblemente para reducir carga de procesamiento en condiciones de conducción intensa.

### 10.6 Popups y mensajes al usuario (`Popup.json`)

Mensajes informativos multi-idioma que el sistema muestra durante la navegación, incluyendo:
- Rutas alternativas disponibles
- Aumento/disminución de distancia por recálculo
- Avisos de rodeos y bypasses

---

## 11. Componentes de software de terceros

El fichero `Text.Info/COPYRIGHT.TXT` revela los componentes open source integrados en el motor de navegación:

| Componente                  | Función                                          |
|-----------------------------|--------------------------------------------------|
| **Rijndael (AES)**          | Cifrado de los ficheros del paquete OTA          |
| **SQLite**                  | Motor de base de datos para `SPEED_PATCH.db`     |
| **Anti-Grain Geometry 2.4** | Renderizado 2D vectorial del mapa                |
| **libpng**                  | Decodificación de imágenes PNG                   |
| **Mesa3D**                  | API OpenGL para renderizado 3D del mapa          |
| **TinyXML**                 | Parsing de configuraciones XML internas          |
| **STLPort**                 | Implementación STL para compilación embebida     |
| **Boost**                   | Utilidades C++ (v1.0 license)                    |
| **Zlib**                    | Compresión/descompresión interna                 |

**Implicación clave para RE:** La presencia de **Rijndael/AES** confirma que el cifrado de los otros archivos del paquete OTA (`mango-rootfs.tar.gz`, `update.tar.gz`, etc.) usa AES. La clave debe residir en el firmware del HU (probablemente hardcodeada o derivada del VIN/IMEI).

---

## 12. Diagrama funcional del sistema

```
┌─────────────────────────────────────────────────────────────────┐
│                    Motor de Navegación (appnavi)                 │
├───────────┬──────────────┬───────────────┬──────────────────────┤
│  ROUTING  │   DISPLAY    │   SAFETY      │    ADAS/HORIZON      │
│           │              │               │                      │
│ .hafr     │ .hafp*       │ .haftlt       │ .hafaip*             │
│ (grafo)   │ (tiles mapa) │ (radares x    │ (geometría vía,      │
│           │              │  país)        │  pendientes)         │
│           │ .hafmma      │               │                      │
│           │ (assets 3D,  │ .hafls        │                      │
│           │  símbolos,   │ (safety       │                      │
│           │  texturas)   │  pan-EU)      │                      │
│           │              │               │                      │
│           │ .hafgsi      │ SPEED_PATCH.db│                      │
│           │ (índice      │ (vel. x       │                      │
│           │  espacial)   │  segmento)    │                      │
│           │              │               │                      │
│           │ DEM/.cad     │ .hafbc        │                      │
│           │ (elevación)  │ (vel. x país) │                      │
├───────────┴──────────────┴───────────────┴──────────────────────┤
│                   CONFIGURACIÓN / NI JSON                        │
│  RpOption · RpAvoidOption · POIType · ServerURL · Alternative    │
├─────────────────────────────────────────────────────────────────┤
│                   RECONOCIMIENTO DE VOZ                          │
│              vr/POI/LEX/ + vr/CATEGORY/ + mango-vr_fixed.tar.gz │
├─────────────────────────────────────────────────────────────────┤
│                 TRÁFICO HISTÓRICO (.alt x país)                  │
│              Usado en ETA y cálculo de rutas evitando atascos    │
└─────────────────────────────────────────────────────────────────┘
```

---

## 13. Resumen ejecutivo

| Aspecto                    | Detalle                                                              |
|----------------------------|----------------------------------------------------------------------|
| **Proveedor de mapas**     | HERE Maps (datos cartográficos, routing, ADAS, radares)             |
| **Versión cartográfica**   | EUR.18.49.56.023.631.5 — datos a julio 2025                         |
| **Cobertura**              | 47 países europeos                                                   |
| **Marcas soportadas**      | Kia, Hyundai y Genesis (configuración diferenciada por marca)        |
| **Formato principal**      | HAF (HERE Automotive Format) — propietario, sin spec pública         |
| **Cifrado OTA**            | AES/Rijndael (clave en firmware del HU)                              |
| **Radares**                | `.haftlt` (13 países) + `.hafls` (pan-EU) — formato binario HAF      |
| **Límites de velocidad**   | SQLite `SPEED_PATCH.db` con 10.3M registros por segmento+dirección+vehículo |
| **ADAS**                   | Mapa de horizonte electrónico para SCC predictivo y LKAS             |
| **Voz/POI**                | Diccionarios fonéticos para 7 idiomas + motor LPTE TTS v1.5.1        |
| **Conectividad**           | Offline completo; GIS/TIS/TIT configurados para conexión futura      |
| **3D/AR**                  | Texturas ASTC, modelos de monumentos, Junction Exit View, Mesa3D     |
| **Tráfico**                | Histórico estadístico (2021) — no en tiempo real en este paquete     |
