#!/usr/bin/env bash
# Extrae un kernel x86_64 genérico (vmlinuz + initrd) usando el gestor de paquetes
# de Debian dentro de un contenedor Docker — evita descargar binarios sueltos de
# terceros y deja que apt resuelva la URL/firma del paquete oficial.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

docker run --rm -v "$SCRIPT_DIR":/out --platform linux/amd64 debian:bookworm bash -c '
  apt-get update -qq
  apt-get install -y -qq linux-image-amd64 >/dev/null
  cp /boot/vmlinuz-* /out/vmlinuz
  cp /boot/initrd.img-* /out/initrd.img
'

echo "OK: vmlinuz + initrd.img en $SCRIPT_DIR"
echo "Nota: este initrd genérico no trae módulos virtio-9p — para 9p hay que"
echo "reconstruirlo con update-initramfs incluyendo 9p/9pnet_virtio, o usar"
echo "solo virtio-blk (root=/dev/vda) como en boot.sh."
