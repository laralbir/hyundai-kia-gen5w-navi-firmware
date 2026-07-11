#!/usr/bin/env bash
# Convierte un directorio con un rootfs extraído (p.ej. mango-rootfs.tar.gz ya
# descomprimido) en una imagen de disco ext4 arrancable por QEMU vía virtio-blk.
# macOS no tiene mkfs.ext4 nativo, así que se hace dentro de un contenedor Linux
# privilegiado (necesita loop devices reales).
set -euo pipefail

SRC_DIR="${1:?Uso: build_rootfs_image.sh <directorio-rootfs-extraido> [salida.img] [tamaño]}"
OUT_IMG="${2:-rootfs.img}"
SIZE="${3:-4G}"

SRC_DIR="$(cd "$SRC_DIR" && pwd)"
OUT_DIR="$(cd "$(dirname "$OUT_IMG")" && pwd)"
OUT_NAME="$(basename "$OUT_IMG")"

qemu-img create -f raw "$OUT_DIR/$OUT_NAME" "$SIZE"

docker run --rm --privileged --platform linux/amd64 \
  -v "$SRC_DIR":/src:ro \
  -v "$OUT_DIR":/out \
  debian:bookworm bash -c "
    apt-get update -qq && apt-get install -y -qq e2fsprogs >/dev/null
    mkfs.ext4 -q /out/$OUT_NAME
    mkdir -p /mnt/r
    mount -o loop /out/$OUT_NAME /mnt/r
    cp -a /src/. /mnt/r/
    umount /mnt/r
    echo DONE
  "

echo "OK: $OUT_DIR/$OUT_NAME listo. Arrancar con boot.sh apuntando root=/dev/vda"
