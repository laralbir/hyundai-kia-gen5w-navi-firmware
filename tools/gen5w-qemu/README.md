# gen5w-qemu — Virtualización gráfica del HU (alternativa a gen5w-docker/chroot)

## ¿Esto muestra la UI real del HU (Kia/Hyundai)?

**No, todavía no.** Lo que este directorio arranca y muestra por pantalla, probado hasta ahora, es
la **consola de texto genérica de Linux** (el log de arranque del kernel + un prompt de shell) —
no `AppNavi`, `AppEngineerMode` ni ninguna app Qt/QML real del HU. Esas apps viven dentro del
`mango-rootfs` real, que sigue cifrado (ver [`../README.md`](../README.md) fases 1-2).

Lo que SÍ está confirmado con una captura de pantalla real (no solo logs):

- El framebuffer gráfico (`virtio-vga` + driver DRM `virtio_gpu`) funciona de verdad — resolución
  1280×800, consola del kernel renderizando en pantalla. Ver
  [`../../docs/assets/qemu_framebuffer_proof.png`](../../docs/assets/qemu_framebuffer_proof.png).
- Qt5/QML **compila y enlaza sin errores** contra las mismas librerías (`Quick`, `Qml`, `Gui`) que
  usaría el HU real, y un binario Qt de prueba arranca sin errores ni crashes sobre este mismo
  framebuffer.
- Lo que **no** se ha podido confirmar visualmente todavía: que el render de esa app Qt aparezca en
  el screendump headless. Causa más probable: `eglfs_kms` hace *modesetting* atómico en un plano DRM
  separado que no se refleja en la superficie VGA heredada que lee el `screendump` de QEMU (a
  diferencia de la consola de texto del kernel, que sí usa esa superficie). Esto **no es evidencia de
  que Qt falle** — es una limitación conocida del método de captura headless. Con `-display cocoa`
  (ventana real, lo que usa `run_graphical.sh` por defecto) debería verse; no se ha podido verificar
  en este entorno porque el trabajo se hizo por terminal sin sesión gráfica interactiva.

**Conclusión práctica:** el mecanismo (kernel real + rootfs real + framebuffer real) está probado.
Si el `mango-rootfs` real arranca aquí y sus apps Qt/QML se lanzan solas (como harían en el HU real
vía systemd), lo lógico es que aparezcan en la ventana — pero eso solo se confirma con el rootfs real
en la mano, no con datos sintéticos.

## Por qué existe esto

`gen5w-docker` (chroot) comparte el kernel del host: no hay arranque real de systemd ni framebuffer
real (limitación que el propio proyecto documenta). Este directorio arranca el `mango-rootfs` en
**QEMU en modo sistema completo** (kernel propio, no el del host), con dispositivos `virtio-*` como
sustituto de los periféricos automotrices que de todas formas no vamos a tener (CAN, pantalla táctil
real, DAB). No es un emulador 100% fiel — es un sistema que arranca de verdad, con systemd real y
framebuffer real, aceptando que algunos servicios fallarán al no encontrar su hardware específico.

**No es una vía para saltarse el cifrado.** Sigue haciendo falta el `mango-rootfs.tar.gz` descifrado
(exploit `navi_extended`, ver [`../README.md`](../README.md)) — esto solo cambia qué hacemos con él
una vez lo tenemos.

## Guía rápida — arrancar en modo gráfico

```bash
cd tools/gen5w-qemu/

# Con el rootfs real ya descifrado (directorio extraído o el .tar.gz directamente):
./run_graphical.sh --rootfs /ruta/a/mango-rootfs-descifrado/
# o
./run_graphical.sh --rootfs /ruta/a/mango-rootfs.tar.gz

# Se abre una ventana real (macOS) con el framebuffer. Ciérrala para salir.
```

Esto hace, en un solo paso: extrae el tar si hace falta, descarga un kernel x86_64 genérico
(cacheado, solo la primera vez), convierte el rootfs a una imagen de disco arrancable, y lanza QEMU
con `virtio-vga` como pantalla.

### Opciones

| Flag | Qué hace |
|---|---|
| `--rootfs PATH` | Directorio ya extraído o `.tar.gz` del rootfs (obligatorio) |
| `--init PATH` | Init del guest. Por defecto `/sbin/init` (el real, systemd) — usa `/bin/bash` para depurar sin arranque completo |
| `--headless` | Sin ventana: arranca ~25s, captura un `screendump` real a `screenshot.png` y sale. Útil en CI/SSH sin sesión gráfica |
| `--force-rebuild` | Reconstruye la imagen ext4 aunque ya exista (por defecto se reusa `work/rootfs.img` entre ejecuciones) |

### Modo headless (sin ventana, por ejemplo por SSH)

```bash
./run_graphical.sh --rootfs /ruta/a/mango-rootfs/ --headless
open screenshot.png   # macOS
```

Este es el método ya validado con captura real (ver arriba) — funciona incluso sin sesión gráfica
interactiva en el host.

## Los tres scripts por separado

Si prefieres controlar cada paso a mano en vez de `run_graphical.sh`:

```bash
# 1. Convertir el rootfs extraído a una imagen de disco ext4 (macOS no tiene mkfs.ext4
#    nativo, se usa un contenedor Linux privilegiado con loop devices reales)
./build_rootfs_image.sh /ruta/a/mango-rootfs-descifrado/ rootfs.img

# 2. Conseguir un kernel x86_64 genérico con soporte DRM/virtio
./fetch_generic_kernel.sh   # extrae vmlinuz+initrd de un linux-image-amd64 de Debian vía Docker

# 3. Arrancar (ventana real por defecto; QEMU_DISPLAY_ARG=none para headless)
./boot.sh rootfs.img vmlinuz initrd.img
```

## Nota sobre el driver de framebuffer

El módulo `virtio_gpu.ko` vive en `/lib/modules/<versión>/` **dentro del rootfs**, no en el initrd
inicial (no hace falta para montar la raíz, solo para la pantalla). Con systemd + udev reales (como
trae el `mango-rootfs` real) se carga solo al detectar el dispositivo PCI — no hace falta ningún
paso manual con `--init /sbin/init`. Solo hace falta `modprobe virtio_gpu` a mano si arrancas con
`--init /bin/bash` para depurar sin systemd.

## El problema pendiente: qué kernel usar

El kernel real del HU vive dentro de `iasImage*` (formato no resuelto — ver
[`../../docs/estructura_ficheros.md`](../../docs/estructura_ficheros.md), probable *Image
Authentication Subsystem*, no U-Boot/FIT estándar). Dos caminos, no mutuamente excluyentes:

1. **Resolver `iasImage`** y extraer el kernel real → arranque más fiel, pero es RE nuevo y no
   resuelto todavía.
2. **Usar un kernel x86_64 genérico** (el que descarga `fetch_generic_kernel.sh`, un
   `linux-image-amd64` de Debian) para arrancar el `mango-rootfs` real. No es el kernel "correcto",
   pero systemd y las apps de userspace (Qt/QML, dropbear, etc.) no dependen de que el kernel sea
   bit-a-bit el original — solo hace falta una ABI razonablemente compatible. Los servicios que
   dependan de hardware automotriz específico (CAN, GPS, DAB) fallarán al arrancar — **exactamente
   el nivel de "periféricos al 100%" que no hace falta** para inspeccionar binarios, UI o lógica de
   arranque.

`run_graphical.sh` usa la vía 2 por defecto — no bloquea en `iasImage`.

## Validado con datos sintéticos (2026-07-11, macOS Apple Silicon, sin KVM)

| Prueba | Resultado |
|---|---|
| Arranque de un kernel x86_64 real (Debian `linux-image-amd64`) bajo TCG puro (sin aceleración) | ~2,3 s hasta shell |
| `root=` real vía `virtio-blk` (imagen ext4, no bind-mount/chroot) | Arranque completo con filesystem raíz independiente, confirmado leyendo un fichero de prueba |
| Compartir directorio del host sin convertir a imagen (`virtio-9p`) | Falla con el kernel/initrd genérico de Debian: módulos `9p`/`9pnet_virtio` no incluidos en su initrd — limitación de ese kernel de prueba, no de QEMU |
| Framebuffer real (`virtio-vga` + rootfs Debian completo con `virtio_gpu.ko`) | **✅ Confirmado visualmente** — `/dev/dri/card0` presente, `fb0` a 1280×800, consola gráfica capturada con `screendump` real |
| Qt5/QML compilado nativo sobre el mismo framebuffer | Compila y arranca sin errores; render no confirmado visualmente vía `screendump` headless (ver explicación arriba) |
| `run_graphical.sh` de punta a punta (kernel + imagen + arranque headless + captura) | **✅ Validado** con rootfs sintético (busybox estático) |

## Limitaciones conocidas

- Sin KVM en Apple Silicon (host ARM64, guest x86_64) — todo corre por TCG (traducción de software).
  El arranque en sí es rápido, pero cargas sostenidas (renderizado Qt continuo) serán más lentas que
  en `gen5w-docker` (que corre vía Rosetta en Docker Desktop). En un host x86_64 con Linux, esto
  correría acelerado por KVM.
- El `initrd` genérico de Debian no trae todos los módulos `virtio-*` por defecto (caso `virtio-9p`,
  ver tabla arriba) — no afecta a `run_graphical.sh` (usa `virtio-blk`, sí soportado).
- Render de apps Qt/QML no confirmado visualmente en modo headless (ver arriba) — probar con
  `-display cocoa` (ventana real) si el screendump headless no muestra nada tras arrancar el
  `mango-rootfs` real.
- Nada de esto sustituye el requisito de tener el rootfs real descifrado.
