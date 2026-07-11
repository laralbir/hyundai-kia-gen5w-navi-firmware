#!/usr/bin/env bash
# Genera un rootfs Debian completo de PRUEBA (systemd + driver virtio_gpu real)
# para verificar que todo el pipeline gen5w-qemu funciona en tu máquina antes
# de tener el mango-rootfs real descifrado. NO es el rootfs del HU — es solo
# para comprobar que la ventana gráfica se abre y arranca de verdad.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUT_DIR="test_rootfs"
rm -rf "$OUT_DIR" "$OUT_DIR.tar"
mkdir -p "$OUT_DIR"

echo "==> Creando contenedor Debian de prueba con systemd + virtio_gpu (~1-2 min)..."
docker rm -f gen5w_qemu_test_rootfs >/dev/null 2>&1 || true
docker create --platform linux/amd64 --name gen5w_qemu_test_rootfs debian:bookworm sleep infinity >/dev/null
docker start gen5w_qemu_test_rootfs >/dev/null
docker exec gen5w_qemu_test_rootfs bash -c '
  apt-get update -qq
  apt-get install -y -qq linux-image-amd64 kmod systemd systemd-sysv udev >/dev/null 2>&1
'

echo "==> Exportando el filesystem..."
docker export gen5w_qemu_test_rootfs -o "$OUT_DIR.tar"
docker rm -f gen5w_qemu_test_rootfs >/dev/null

tar -xf "$OUT_DIR.tar" -C "$OUT_DIR"
rm -f "$OUT_DIR.tar"

echo ""
echo "OK: rootfs de prueba listo en $SCRIPT_DIR/$OUT_DIR"
echo ""
echo "Ahora arranca con:"
echo "  ./run_graphical.sh --rootfs $OUT_DIR --init /bin/bash"
echo ""
echo "Dentro de la ventana (login como root sin contraseña, o directamente shell"
echo "si usaste --init /bin/bash), prueba:"
echo "  modprobe virtio_gpu && ls /dev/dri/"
