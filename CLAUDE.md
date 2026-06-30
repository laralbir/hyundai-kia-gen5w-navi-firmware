# Rio MY22 EU — Kia Rio 2022 Head Unit Firmware

## Contexto del proyecto

Ingeniería inversa del firmware y mapas de la auto radio (Head Unit) de un **Kia Rio 2022, variante Europa (EU)**.
El objetivo es analizar, modificar y comprender los componentes del sistema embebido.

## Plataforma

| Campo              | Valor                                      |
|--------------------|--------------------------------------------|
| Plataforma HW      | **mango** (codename de la SoC/board)       |
| Versión SW         | **S5W** (5th gen, "5w" en rutas de build)  |
| Versión completa   | `YB_22.EUR.S5W_L.001.001.251204`           |
| Región             | EUR (Europa)                               |
| Modelo vehiculo    | YB = Kia Rio, año modelo 2022              |
| Build type         | `MASS_PRODUCT` (producción, no engineering)|
| Fecha build        | 4 de diciembre de 2025, 13:45:26           |
| Release            | `25RU2_001` (Release Update 2, build 001)  |

El sistema corre **Linux embebido**. El build system es `vc.integrator` (probablemente Yocto o similar).
Ruta interna del build server: `/data001/vc.integrator/__EVENT_BUILD_s5w.25ru2.250702_MASS_PRODUCT_25RU2_001_251204134526/build-mango/`

## Estructura de archivos

```
Rio_MY22_EU/
├── Rio_MY22_EU.ver          # Índice de todos los archivos (pipe-delimited, ver abajo)
├── AppUpgrade/              # Paquetes de actualización de aplicaciones
└── HU/
    ├── firmware/
    │   ├── update.tar.gz            # Actualización principal del firmware
    │   └── frontkey/                # Firmware del MCU del panel frontal (MKBD)
    │       ├── Checksum.txt         # CRC32 de los .bin
    │       ├── nx4/MKBD_2_1f_00_NX4.bin    # Variante de hardware NX4
    │       └── us4hev/MKBD_2_22_00_US4.bin # Variante US4 (HEV = Hybrid)
    └── images/
        ├── iasImage*                # Imágenes de boot/kernel (ver variantes abajo)
        ├── mango-rootfs.tar.gz      # Root filesystem Linux (partición principal RO)
        ├── mango-rwdata.tar.gz      # Partición de datos read-write (configuración/user)
        ├── new_gui.tar.gz           # Actualización de interfaz gráfica
        ├── mustwithcopy             # Archivo que debe copiarse (no es directorio)
        ├── navi_eu/                 # Aplicación de navegación + mapas
        │   ├── appnavi.tar                          # Aplicación de navegación
        │   ├── S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip  # Mapas HERE Europa
        │   └── EUR.18.49.56.023.631.5_md5.txt       # MD5 del zip de mapas
        ├── vrau/                    # Voice Recognition — Australia
        │   ├── mango-vr.tar.gz          # VR original
        │   └── mango-vr_fixed.tar.gz    # VR con fix post-build
        └── vreu/                    # Voice Recognition — Europa
            ├── mango-vr.tar.gz
            └── mango-vr_fixed.tar.gz
```

## Variantes de iasImage (imágenes de boot)

Los `iasImage*` son imágenes de kernel/initrd. Las variantes combinan **plataforma** y **resolución de pantalla**:

| Archivo                    | Plataforma | Resolución  | Pantalla  |
|----------------------------|------------|-------------|-----------|
| `iasImage`                 | base       | default     | principal |
| `iasImage_sub`             | base       | default     | secundaria|
| `iasImage_1280`            | base       | 1280px      | principal |
| `iasImage_1280_sub`        | base       | 1280px      | secundaria|
| `iasImage_1920_12`         | base       | 1920px 1.2" | principal |
| `iasImage_1920_12_sub`     | base       | 1920px 1.2" | secundaria|
| `iasImage_p5`              | p5         | default     | principal |
| `iasImage_p5_sub`          | p5         | default     | secundaria|
| `iasImage_p5_1280`         | p5         | 1280px      | principal |
| `iasImage_p5_1280_sub`     | p5         | 1280px      | secundaria|
| `iasImage_p5_1920_12`      | p5         | 1920px 1.2" | principal |
| `iasImage_p5_1920_12_sub`  | p5         | 1920px 1.2" | secundaria|

## Variantes de modem

| Directorio  | Descripción                          |
|-------------|--------------------------------------|
| `eu/`       | Modem estándar Europa                |
| `eu_le22/`  | Modem LTE Europa (chipset LE, rev 22)|
| `au_le22/`  | Modem LTE Australia (chipset LE, rev 22)|

## Formato del archivo .ver

`Rio_MY22_EU.ver` es el manifiesto de todos los archivos del update. Formato pipe-delimited:

```
path|filename|record_id|checksum_int32|size_bytes|flag
```

- El checksum es un entero con signo (CRC32 o similar, puede ser negativo por overflow).
- Útil para verificar integridad y detectar diferencias entre versiones.

## Mapas HERE

- Proveedor: **HERE Maps**
- Región: Europa (`EUR`)
- Versión: `18.49.56.023.631.5`
- Archivo: `S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip` (~17.9 GB)
- MD5: `b00d66e5536ba37297bd6c3e1b7e0993`
- La app de navegación es `appnavi.tar` (aplicación separada de los mapas).

## Autonomía operativa

El usuario concede **autonomía total** para tareas de investigación de RE: ejecutar todos los comandos (análisis, extracción, scripts, herramientas) sin pedir confirmación previa. Solo confirmar antes de hacer **commit o push**.

## Reglas de mantenimiento del repositorio

- **Documentación de análisis**: cualquier componente, formato o hallazgo que se analice debe quedar documentado en `docs/` (fichero propio o sección relevante) **y** registrado en `.claude/memory/` (archivo de memoria correspondiente o uno nuevo si no existe, añadido al índice `MEMORY.md`).
- **Commits y push**: hacer commit y push únicamente de los ficheros que estén en el área de stage (`git add` explícito). No usar `git add .` ni `git add -A`. Nunca incluir ficheros no staged aunque tengan cambios.
- **README.md**: actualizar siempre que cambie cualquier fichero de `docs/`. El README debe reflejar el estado actual de la documentación.
- **`.claude/memory/`**: todo hallazgo o información nueva que se añada a `docs/` debe quedar también registrado en el archivo de memoria correspondiente de `.claude/memory/`. Si no existe un archivo de memoria adecuado, crear uno nuevo y añadirlo al índice `MEMORY.md`.

## Notas de ingeniería inversa

- **Empezar por**: `mango-rootfs.tar.gz` para el sistema de archivos base; `update.tar.gz` para los binarios del update OTA.
- **Filesystem**: Linux embebido. Buscar `/etc`, `/usr/bin`, `/system`, particiones montadas.
- **mango-vr_fixed.tar.gz** vs `mango-vr.tar.gz`: la versión `_fixed` es un parche post-build; comparar ambas para identificar qué se corrigió.
- **iasImage**: formato IAS (probablemente imagen U-Boot o fitImage). Usar `binwalk` para extraer.
- **Frontkey MKBD .bin**: firmware del microcontrolador del panel de botones. CRC32 verificable con `Checksum.txt`.
- **AppUpgrade/**: directorio vacío en esta versión — podría contener APKs o paquetes de actualización diferencial en otras versiones.
- Los checksums del `.ver` son enteros de 32 bits con signo — convertir a uint32 para CRC32 estándar.
