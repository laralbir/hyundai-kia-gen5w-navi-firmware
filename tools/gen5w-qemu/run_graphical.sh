#!/usr/bin/env bash
# Orquestador: prepara y arranca el mango-rootfs (o cualquier rootfs extraído)
# en QEMU con salida gráfica real (virtio-vga), en un solo comando.
#
# Uso:
#   ./run_graphical.sh --rootfs /path/a/mango-rootfs-descifrado/
#   ./run_graphical.sh --rootfs /path/a/mango-rootfs.tar.gz
#
# Opciones:
#   --rootfs PATH       Directorio ya extraído o .tar.gz del rootfs (obligatorio)
#   --init PATH         Init a usar dentro del guest (por defecto /sbin/init — el
#                        real de systemd; usa /bin/bash para depurar sin arranque completo)
#   --headless          En vez de ventana (-display cocoa), usa -display none +
#                        captura un screendump a screenshot.png y sale (útil en CI/SSH)
#   --force-rebuild      Reconstruye la imagen ext4 aunque ya exista
#
# Qué hace exactamente, en orden:
#   1. Si --rootfs es un .tar.gz, lo extrae a ./work/rootfs_extracted/
#   2. Si no hay kernel genérico descargado aún, lo obtiene (fetch_generic_kernel.sh)
#   3. Convierte el rootfs a imagen ext4 arrancable (build_rootfs_image.sh), si no
#      existe ya o se pide --force-rebuild
#   4. Arranca con boot.sh
#
# IMPORTANTE — lee esto antes de asumir que "se ve la UI del HU":
#   Lo que arranca aquí es el rootfs real con SU systemd real, así que si
#   AppNavi/AppEngineerMode están configurados para lanzarse solos al arrancar,
#   deberían intentarlo de verdad. Pero nunca se ha confirmado visualmente que
#   una app Qt/QML real (ni siquiera una de prueba) llegue a la pantalla en
#   este entorno — ver "Limitaciones conocidas" en README.md. Si no aparece
#   nada tras el arranque, no asumas que el mecanismo entero es inútil: puede
#   ser justo esa brecha conocida (DRM master / plano EGLFS vs superficie VGA
#   heredada), no un fallo del rootfs real.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ROOTFS=""
INIT="/sbin/init"
HEADLESS=0
FORCE_REBUILD=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rootfs) ROOTFS="$2"; shift 2 ;;
    --init) INIT="$2"; shift 2 ;;
    --headless) HEADLESS=1; shift ;;
    --force-rebuild) FORCE_REBUILD=1; shift ;;
    *) echo "Opción desconocida: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$ROOTFS" ]]; then
  echo "Uso: $0 --rootfs <directorio-o-tar.gz-del-rootfs> [--init /sbin/init] [--headless] [--force-rebuild]" >&2
  exit 1
fi

mkdir -p work

# 1. Extraer si es un tar.gz
ROOTFS_DIR="$ROOTFS"
if [[ -f "$ROOTFS" && "$ROOTFS" == *.tar.gz ]]; then
  echo "==> Extrayendo $ROOTFS ..."
  ROOTFS_DIR="$SCRIPT_DIR/work/rootfs_extracted"
  rm -rf "$ROOTFS_DIR"
  mkdir -p "$ROOTFS_DIR"
  tar -xzf "$ROOTFS" -C "$ROOTFS_DIR"
fi

if [[ ! -d "$ROOTFS_DIR" ]]; then
  echo "ERROR: '$ROOTFS_DIR' no es un directorio válido." >&2
  exit 1
fi

# 2. Kernel genérico (cacheado)
if [[ ! -f vmlinuz || ! -f initrd.img ]]; then
  echo "==> No hay kernel genérico todavía, lo descargo (fetch_generic_kernel.sh)..."
  ./fetch_generic_kernel.sh
else
  echo "==> Reusando kernel genérico ya presente (vmlinuz + initrd.img)."
fi

# 3. Imagen ext4
IMG="work/rootfs.img"
if [[ ! -f "$IMG" || $FORCE_REBUILD -eq 1 ]]; then
  echo "==> Construyendo imagen ext4 desde $ROOTFS_DIR ..."
  SIZE_MB=$(du -sm "$ROOTFS_DIR" | cut -f1)
  SIZE_GB=$(( (SIZE_MB * 3 / 2 / 1024) + 1 ))  # margen x1.5 + redondeo
  ./build_rootfs_image.sh "$ROOTFS_DIR" "$IMG" "${SIZE_GB}G"
else
  echo "==> Reusando imagen ext4 ya construida en $IMG (usa --force-rebuild para regenerarla)."
fi

# 4. Arrancar
if [[ $HEADLESS -eq 1 ]]; then
  echo "==> Arrancando en modo headless — se guardará screenshot.png al terminar."
  echo "    (Ctrl+C para salir antes; el screendump se captura a los 20s)"
  DISPLAY_MODE=none
else
  echo "==> Arrancando con ventana gráfica real (cierra la ventana de QEMU para salir)."
  DISPLAY_MODE=cocoa
fi

QEMU_DISPLAY_ARG="$DISPLAY_MODE" ./boot.sh "$IMG" vmlinuz initrd.img "$INIT"
