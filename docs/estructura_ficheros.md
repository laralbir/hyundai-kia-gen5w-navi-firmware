# Estructura de ficheros — Rio MY22 EU

Firmware y mapas del Head Unit (HU) del Kia Rio 2022, variante Europa.  
Versión: `YB_22.EUR.S5W_L.001.001.251204` · Build: `MASS_PRODUCT` · Fecha build: 2025-12-04

---

## Árbol general

<pre>
Rio_MY22_EU/
├── <a href="#rio-ver">Rio_MY22_EU.ver</a>          (2.5 KB)    Manifiesto de todos los ficheros del update
├── <a href="#appupgrade">AppUpgrade</a>               (10.3 MB)   Paquete de actualización de aplicaciones
└── HU/
    ├── firmware/
    │   ├── <a href="#update-tar-gz">update.tar.gz</a>    (40.2 MB)   Firmware principal del HU (cifrado)
    │   └── frontkey/                    Firmware MCU del panel de botones
    │       ├── <a href="#checksum-txt">Checksum.txt</a> (76 B)      CRC32 de los .bin
    │       ├── nx4/
    │       │   └── <a href="#mkbd-nx4">MKBD_2_1f_00_NX4.bin</a>    (192 KB)  Firmware MCU variante NX4
    │       └── us4hev/
    │           └── <a href="#mkbd-us4">MKBD_2_22_00_US4.bin</a>    (192 KB)  Firmware MCU variante US4 (HEV)
    ├── firmware/modem/
    │   ├── eu/<a href="#modem">modem_eu.tar.gz</a>              (151.3 MB)  Módem estándar Europa
    │   ├── eu_le22/<a href="#modem">modem_eu_le22.tar.gz</a>     (331.1 MB)  Módem LTE Europa, chipset LE rev.22
    │   └── au_le22/<a href="#modem">modem_au_le22.tar.gz</a>     (121.9 MB)  Módem LTE Australia, chipset LE rev.22
    └── images/
        ├── <a href="#iasimage">iasImage</a>*        (6.1–6.0 MB c/u)  Imágenes de boot/kernel (12 variantes)
        ├── <a href="#mango-rootfs">mango-rootfs.tar.gz</a>  (838.4 MB)     Root filesystem Linux (cifrado)
        ├── <a href="#mango-rwdata">mango-rwdata.tar.gz</a>  (16.0 MB)      Partición datos read-write (cifrado)
        ├── <a href="#new-gui">new_gui.tar.gz</a>       (1.99 GB)      Actualización de interfaz gráfica (cifrado)
        ├── <a href="#mustwithcopy">mustwithcopy</a>         (0 B)           Fichero marcador (flag vacío)
        ├── navi_eu/
        │   ├── <a href="#appnavi">appnavi.tar</a>                (487 MB)     Aplicación de navegación (cifrado)
        │   ├── <a href="#here-maps">S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip</a>  (16.7 GB)  Mapas HERE Europa (cifrado)
        │   └── <a href="#md5-maps">EUR.18.49.56.023.631.5_md5.txt</a>          (73 B)     MD5 del ZIP de mapas
        ├── vrau/                                        Voice Recognition — Australia
        │   ├── <a href="#mango-vr">mango-vr.tar.gz</a>        (43.2 MB)   VR original (cifrado/propietario)
        │   ├── <a href="#mango-vr-fixed">mango-vr_fixed.tar.gz</a>  (544 MB)    VR con fix post-build (gzip real)
        │   └── <a href="#md5sum-vr">md5sum.txt</a>             (200 B)      MD5 de mango-vr_fixed.tar.gz
        └── vreu/                                        Voice Recognition — Europa
            ├── <a href="#mango-vr">mango-vr.tar.gz</a>        (62.9 MB)   VR original (cifrado/propietario)
            ├── <a href="#mango-vr-fixed">mango-vr_fixed.tar.gz</a>  (2.20 GB)   VR con fix post-build (gzip real)
            └── <a href="#md5sum-vr">md5sum.txt</a>             (200 B)      MD5 de mango-vr_fixed.tar.gz
</pre>

---

## Descripción detallada por fichero

<a id="rio-ver"></a>

### `Rio_MY22_EU.ver` · 2.5 KB · Texto plano

Manifiesto del paquete de actualización. Lista todos los ficheros con metadatos para verificación de integridad. Formato pipe-delimited:

```
path|filename|record_id|checksum_int32|size_bytes|flag
```

| Campo          | Descripción                                                        |
|----------------|--------------------------------------------------------------------|
| `path`         | Ruta relativa con backslashes (convención Windows del update tool) |
| `filename`     | Nombre del fichero                                                 |
| `record_id`    | ID único incremental del registro (308413–308447)                  |
| `checksum_int32` | Checksum de 32 bits con signo (puede ser negativo por overflow)  |
| `size_bytes`   | Tamaño del fichero en bytes                                        |
| `flag`         | Siempre `1` en este build                                          |

La primera línea es una cabecera especial:
```
+|19328|YB_22.EUR.S5W_L.001.001.251204|KM|Rio_MY22_EU|1565|1
```
Contiene la versión completa del paquete (`YB_22.EUR.S5W_L.001.001.251204`) y el fabricante (`KM` = Kia Motors).

---

<a id="appupgrade"></a>

### `AppUpgrade` · 10.3 MB · Binario propietario (cifrado)

Paquete de actualización de aplicaciones. A pesar de no tener extensión, es un fichero binario (no un directorio). Primeros bytes: `f3 e4 2a 10 ...` — no coincide con ningún magic number estándar.

Probable contenido: APKs o paquetes de aplicaciones propietarias del HU empaquetados con cifrado/formato propietario de Hyundai/Kia.

**RE:** Sin descifrado previo, el contenido no es accesible directamente. Buscar en el rootfs el binario que lo procesa (probablemente en `/usr/bin` o en scripts de instalación).

---

## HU/firmware/

<a id="update-tar-gz"></a>

### `update.tar.gz` · 40.2 MB · Binario cifrado

A pesar de la extensión `.tar.gz`, los primeros bytes (`b8 52 5a 8d ...`) **no son gzip** (el magic gzip es `1f 8b`). El fichero está cifrado o en un formato propietario del update system del HU.

Contiene el firmware principal del sistema (probablemente el kernel, módulos, y binarios del sistema base). Es el componente más crítico del update OTA.

**RE:** El firmware del HU debe contener la clave/lógica de descifrado. Buscar en el rootfs funciones relacionadas con el proceso de update (`update_agent`, `fota`, o similar).

---

<a id="checksum-txt"></a>

### `frontkey/Checksum.txt` · 76 B · Texto plano

Fichero de verificación de integridad para los binarios del MCU del panel frontal:
```
MKBD_2_1F_00_NX4.BIN   CRC32=0x0E969002
MKBD_2_22_00_US4.BIN   CRC32=0xBCFCC65D
```

---

<a id="mkbd-nx4"></a>

### `frontkey/nx4/MKBD_2_1f_00_NX4.bin` · 192 KB · Firmware MCU

Firmware del microcontrolador del panel frontal de botones, variante **NX4**.  
Primeros bytes: `d8 00 ff ff ff ff ...` — patrón típico de flash ARM Cortex-M en little-endian:
- Bytes 0–3: Initial Stack Pointer (posible valor: `0xFFFF00D8` en LE)
- Zonas `ff ff ff ff`: sectores de flash no programados

**RE:** Usar un desensamblador de ARM (Ghidra, IDA) con arquitectura Cortex-M. El `MKBD` del nombre sugiere "Main Key Board Driver".

---

<a id="mkbd-us4"></a>

### `frontkey/us4hev/MKBD_2_22_00_US4.bin` · 192 KB · Firmware MCU

Idéntico en estructura al NX4 pero para la variante **US4 HEV** (posiblemente un modelo con sistema Hybrid Electric Vehicle o una revisión de hardware diferente del panel).  
CRC32: `0xBCFCC65D`

---

## HU/images/ — Imágenes de boot

<a id="iasimage"></a>

### `iasImage` (y variantes) · 6.0–6.1 MB c/u · Binario cifrado/propietario

12 ficheros que implementan imágenes de arranque del sistema (kernel Linux + initrd o similar). Primeros bytes: `d8 e3 57 0d ...` — no coincide con ningún formato estándar conocido (U-Boot legacy: `27 05 19 56`; FIT/DTB: `d0 0d fe ed`; zImage: `1f 8b` o `1a d0`).

El nombre "iasImage" puede provenir de **IAS (Image Authentication Subsystem)** — un esquema de arranque seguro firmado/cifrado propio de Hyundai/Kia o del SoC subyacente.

Las 12 variantes combinan **plataforma de hardware** y **resolución de pantalla**:

| Fichero                    | Tamaño     | Plataforma | Resolución   | Pantalla    |
|----------------------------|------------|------------|--------------|-------------|
| `iasImage`                 | 6,226,728  | base       | default      | principal   |
| `iasImage_sub`             | 6,210,308  | base       | default      | secundaria  |
| `iasImage_1280`            | 6,226,728  | base       | 1280 px      | principal   |
| `iasImage_1280_sub`        | 6,210,308  | base       | 1280 px      | secundaria  |
| `iasImage_1920_12`         | 6,226,728  | base       | 1920 px 1.2" | principal   |
| `iasImage_1920_12_sub`     | 6,210,308  | base       | 1920 px 1.2" | secundaria  |
| `iasImage_p5`              | 6,226,728  | p5         | default      | principal   |
| `iasImage_p5_sub`          | 6,210,308  | p5         | default      | secundaria  |
| `iasImage_p5_1280`         | 6,226,728  | p5         | 1280 px      | principal   |
| `iasImage_p5_1280_sub`     | 6,210,308  | p5         | 1280 px      | secundaria  |
| `iasImage_p5_1920_12`      | 6,226,728  | p5         | 1920 px 1.2" | principal   |
| `iasImage_p5_1920_12_sub`  | 6,210,308  | p5         | 1920 px 1.2" | secundaria  |

**Observaciones:**
- Los 6 ficheros `*_sub` tienen exactamente 16,420 bytes menos que sus homólogos principales.
- Ficheros del mismo tamaño tienen MD5 **distintos** → contenido diferente a pesar del mismo tamaño.
- `_sub` probablemente controla una pantalla secundaria (cluster de instrumentos o pantalla trasera).
- La pantalla `_p5` es una revisión de hardware posterior (P5 = Platform 5?).

**RE:** Usar `binwalk` para buscar patrones internos. Si el formato es IAS de Qualcomm, la herramienta `fwunpack` o scripts específicos de Snapdragon pueden ayudar.

---

<a id="mango-rootfs"></a>

### `mango-rootfs.tar.gz` · 838.4 MB · Cifrado/propietario

Root filesystem Linux del HU. A pesar de la extensión `.tar.gz`, los primeros bytes (`52 b4 33 00 ...`) **no son gzip**. Cifrado con la misma clave/esquema que el resto de los archivos.

Es el componente más valioso para RE: contiene todos los binarios del sistema, librerías, scripts de arranque, configuraciones, claves, y la lógica de la HU.

**RE:** Una vez descifrado, montar con `tar xzf` y explorar `/etc/`, `/usr/bin/`, `/system/`. Buscar: procesos propietarios de Kia/Hyundai, gestión de mapas HERE, protocolos CAN bus.

---

<a id="mango-rwdata"></a>

### `mango-rwdata.tar.gz` · 16.0 MB · Cifrado/propietario

Partición de datos read-write: configuración de usuario, preferencias, datos de calibración, posiblemente claves derivadas. El sufijo `rwdata` (Read-Write Data) es estándar en sistemas embebidos Linux para separar datos persistentes del rootfs (que suele ser read-only).

---

<a id="new-gui"></a>

### `new_gui.tar.gz` · 1.99 GB · Cifrado/propietario

Actualización completa de la interfaz gráfica del HU. El gran tamaño (el fichero más pesado junto con las VR) sugiere que incluye assets gráficos, animaciones, fuentes, y posiblemente el runtime de UI (Qt, Wayland compositor, etc.).

---

<a id="mustwithcopy"></a>

### `mustwithcopy` · 0 B · Fichero marcador

Fichero vacío. Su nombre sugiere que es un **flag** para el instalador: indica que los ficheros del mismo directorio deben ser copiados obligatoriamente (sin skip condicional) durante el proceso de update. No contiene datos.

---

## HU/images/navi_eu/ — Navegación Europa

<a id="appnavi"></a>

### `appnavi.tar` · 487 MB · Cifrado/propietario

Aplicación de navegación HERE. A pesar de la extensión `.tar`, los primeros bytes (`e1 30 0e d0 ...`) no corresponden al magic de TAR POSIX (`75 73 74 61 72` a offset 257). Está cifrado o en formato propietario.

Contiene el ejecutable y recursos de la aplicación de navegación (motor de routing, renderizado de mapas, interfaz). Separado del paquete de mapas para permitir actualizar la app sin reemplazar los ~17 GB de datos cartográficos.

---

<a id="here-maps"></a>

### `S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip` · 16.7 GB · ZIP cifrado (probable)

Datos cartográficos HERE Maps para Europa. El mayor fichero del paquete.

| Campo           | Valor                                  |
|-----------------|----------------------------------------|
| Proveedor       | HERE Maps                              |
| Región          | Europa (`EUR`)                         |
| Versión HERE    | `18.49.56.023.631.5`                   |
| MD5             | `b00d66e5536ba37297bd6c3e1b7e0993`     |
| Tamaño          | 17,889,556,253 bytes (16.66 GB)        |

La extensión `.zip` podría ser real o nominal. El contenido incluye tiles vectoriales, base de datos POI, datos de tráfico, y datos de routing para todos los países europeos.

---

<a id="md5-maps"></a>

### `EUR.18.49.56.023.631.5_md5.txt` · 73 B · Texto plano

Fichero de verificación MD5 para el ZIP de mapas:
```
b00d66e5536ba37297bd6c3e1b7e0993 *S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip
```

---

## HU/images/vrau/ y vreu/ — Voice Recognition

Dos regiones: **VRAU** (Australia) y **VREU** (Europa). Cada una contiene un paquete original cifrado y un paquete `_fixed` en gzip estándar.

<a id="mango-vr"></a>

### `mango-vr.tar.gz` (vrau: 43.2 MB / vreu: 62.9 MB) · Cifrado/propietario

Paquete VR original generado por el build system. Primeros bytes no son gzip (`fe 8e 43 ff` / `6e 61 69 eb`). Posiblemente cifrado con el esquema del HU o en un formato de contenedor propietario.

<a id="mango-vr-fixed"></a>

### `mango-vr_fixed.tar.gz` (vrau: 544 MB / vreu: 2.20 GB) · **gzip real** ✓

El único fichero `.tar.gz` del paquete que **es efectivamente gzip** (magic `1f 8b 08 00`). El sufijo `_fixed` indica que fue sustituido post-build, presumiblemente para corregir un error de cifrado o de empaquetado en el original.

**Contenido** (estructura interna extraíble):

```
vr_fixed/
└── LPTE/
    └── BASE/
        ├── VRM_ENV.ini          Configuración del VR Manager
        ├── JINIE.SYMBOL.DAT     Modelos de síntesis JINIE
        ├── SE.STT.ENV.DAT       Config Speech-To-Text
        ├── SE.SYMBOL.DAT        Símbolos del motor de habla
        ├── SE.TTS.ENV.DAT       Config Text-To-Speech
        ├── TIMA.ENV.DAT         Config motor TIMA
        ├── TIMA.SYMBOL.DAT      Modelos TIMA
        ├── TIMA2.ENV.DAT        Config TIMA v2
        ├── TIMA_NAVI_VR.ENV.DAT Config TIMA para navegación
        ├── TIMA_NAVI2_VR.ENV.DAT
        ├── ASR/                 Automatic Speech Recognition por idioma
        │   ├── ENG/             (modelos acústicos .dat)
        │   ├── FRF/
        │   └── ...
        └── TTS/
            └── 1.5.1/
                └── languages/   Text-To-Speech por idioma (modelos de voz .dat + .hdr)
```

**Motor TTS**: LPTE v1.5.1 — parece un motor propietario de síntesis de voz de Cerence (ex-Nuance) o similar, con modelos de voz individuales por idioma.

**Idiomas incluidos (vreu)** — 24 idiomas europeos:

| Código | Idioma     | Código | Idioma     | Código | Idioma    |
|--------|------------|--------|------------|--------|-----------|
| `bgb`  | Búlgaro    | `fif`  | Finlandés  | `plp`  | Polaco    |
| `czc`  | Checo      | `frf`  | Francés    | `ptp`  | Portugués |
| `dad`  | Danés      | `ged`  | Alemán     | `ror`  | Rumano    |
| `dun`  | Neerlandés | `grg`  | Griego     | `rur`  | Ruso      |
| `eng`  | Inglés     | `hrh`  | Croata     | `sks`  | Eslovaco  |
| `fif`  | Finlandés  | `huh`  | Húngaro    | `sls`  | Esloveno  |
| `spe`  | Español    | `iti`  | Italiano   | `sws`  | Sueco     |
| `kok`  | Coreano    | `non`  | Noruego    | `trt`  | Turco     |
| `uku`  | Ucraniano  |        |            |        |           |

**Idiomas incluidos (vrau)** — 1 idioma: `kok` (Coreano). La VR de Australia se centra exclusivamente en coreano (KIA/Hyundai tienen fuerte presencia en la comunidad coreana de Australia).

<a id="md5sum-vr"></a>

### `md5sum.txt` · 200 B · Texto plano

MD5 del fichero `mango-vr_fixed.tar.gz`, con la ruta completa interna del build server incluida:
```
<md5>  */data001/vc.integrator/__EVENT_BUILD_s5w.25ru2.250702_MASS_PRODUCT_25RU2_001_251204134526/build-mango/BUILD/deploy/images/5w/usb/HU/images/vr[au|eu]/mango-vr_fixed.tar.gz
```

---

<a id="modem"></a>

## HU/firmware/modem/ — Firmware del módem

Tres variantes de firmware para el módulo de comunicaciones (LTE/4G):

| Directorio | Fichero                  | Tamaño    | Descripción                         |
|------------|--------------------------|-----------|-------------------------------------|
| `eu/`      | `modem_eu.tar.gz`        | 151.3 MB  | Módem estándar Europa               |
| `eu_le22/` | `modem_eu_le22.tar.gz`   | 331.1 MB  | Módem LTE Europa, chipset LE rev.22 |
| `au_le22/` | `modem_au_le22.tar.gz`   | 121.9 MB  | Módem LTE Australia, chipset LE rev.22 |

Todos empiezan con bytes no-gzip → cifrados o en formato propietario. El sufijo `le22` probablemente identifica una revisión del chipset de módem (LE = LTE chipset, 22 = versión).

La variante `eu_le22` (331 MB) es significativamente más grande que `eu` (151 MB), lo que sugiere que incluye firmware adicional para bandas de frecuencia extra u otras funcionalidades LTE avanzadas.

---

## Análisis del cifrado

La mayoría de los ficheros del paquete están cifrados o en un formato propietario. Los magic bytes iniciales no corresponden a ningún formato estándar conocido para cada tipo:

| Tipo esperado | Magic estándar | Magic observado     | Conclusión        |
|---------------|----------------|---------------------|-------------------|
| gzip          | `1f 8b`        | variable            | Cifrado           |
| TAR POSIX     | `ustar` @257   | no encontrado       | Cifrado           |
| U-Boot image  | `27 05 19 56`  | `d8 e3 57 0d`       | Cifrado/propietario |
| FIT/DTB       | `d0 0d fe ed`  | `d8 e3 57 0d`       | No aplicable      |

**Excepción:** `mango-vr_fixed.tar.gz` (vrau y vreu) son gzip reales y accesibles sin descifrado.

El proceso de cifrado/descifrado probablemente reside en el rootfs del HU. El instalador OTA lee estos ficheros y los descifra en memoria antes de escribirlos en las particiones del HU.

---

## Tamaños totales por componente

| Componente                          | Tamaño        |
|-------------------------------------|---------------|
| Mapas HERE Europa                   | 16.66 GB      |
| VR Europa (fixed)                   | 2.20 GB       |
| GUI nueva                           | 1.99 GB       |
| Root filesystem                     | 838.4 MB      |
| VR Australia (fixed)                | 544 MB        |
| Aplicación navegación               | 487 MB        |
| Módem EU LE22                       | 331.1 MB      |
| Módem EU estándar                   | 151.3 MB      |
| Módem AU LE22                       | 121.9 MB      |
| Firmware principal HU               | 40.2 MB       |
| VR Europa (original cifrado)        | 62.9 MB       |
| VR Australia (original cifrado)     | 43.2 MB       |
| Datos RW                            | 16.0 MB       |
| AppUpgrade                          | 10.3 MB       |
| iasImages (×12)                     | ~73.8 MB      |
| Frontkey MCU (×2)                   | ~384 KB       |
| **TOTAL aproximado**                | **~22.5 GB**  |
