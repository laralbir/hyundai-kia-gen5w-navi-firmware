#!/usr/bin/env bash
# Arranca un rootfs (imagen ext4, ver build_rootfs_image.sh) en QEMU con un
# kernel x86_64 (ver fetch_generic_kernel.sh, o el real si se resuelve iasImage).
# Sin KVM en Apple Silicon (host ARM64) — corre por TCG, más lento pero funcional.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOTFS_IMG="${1:?Uso: boot.sh <rootfs.img> <vmlinuz> <initrd.img> [init=/sbin/init]}"
KERNEL="${2:?falta vmlinuz}"
INITRD="${3:?falta initrd.img}"
INIT="${4:-/sbin/init}"

# QEMU_DISPLAY_ARG=cocoa (por defecto) abre una ventana real en macOS.
# QEMU_DISPLAY_ARG=none arranca headless y guarda un screendump real
# (screenshot.png) a los ~20s vía el monitor QMP — así se verificó que el
# framebuffer funciona de verdad (ver docs/gen5w_exploit_ecosystem.md).
DISPLAY_MODE="${QEMU_DISPLAY_ARG:-cocoa}"

# console=tty1 manda la consola del kernel al framebuffer (lo que se ve en la
# ventana/captura). Usa console=ttyS0 si prefieres logs de arranque por stdio.
COMMON_ARGS=(
  -M q35 -m 2048 -smp 2
  -kernel "$KERNEL" -initrd "$INITRD"
  -append "console=tty1 root=/dev/vda rw rootfstype=ext4 init=${INIT}"
  -drive file="$ROOTFS_IMG",format=raw,if=virtio
  -device virtio-net-pci,netdev=n0 -netdev user,id=n0
  -vga none -device virtio-vga
  -no-reboot
)

if [[ "$DISPLAY_MODE" == "cocoa" ]]; then
  exec qemu-system-x86_64 "${COMMON_ARGS[@]}" -display cocoa -serial stdio
fi

# Modo headless: arranca en background, espera a que el sistema asiente,
# pide un screendump real por QMP y mata la VM. Útil en CI/SSH sin pantalla.
echo "Arrancando headless (sin ventana) — dando ~25s para que el sistema arranque..."
cd "$SCRIPT_DIR"
rm -f qmp_boot.sock screenshot.ppm
qemu-system-x86_64 "${COMMON_ARGS[@]}" \
  -display none \
  -qmp unix:./qmp_boot.sock,server,nowait \
  -serial mon:stdio -no-reboot \
  <<< "" > boot_console.log 2>&1 &
QEMU_PID=$!

sleep 25
python3 - "$SCRIPT_DIR/qmp_boot.sock" "$SCRIPT_DIR/screenshot.ppm" <<'PYEOF'
import socket, sys, time
sock_path, out_path = sys.argv[1], sys.argv[2]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
def rd():
    time.sleep(0.3)
    return s.recv(65536)
rd()
s.sendall(b'{"execute":"qmp_capabilities"}\n')
rd()
s.sendall(('{"execute":"screendump","arguments":{"filename":"%s"}}\n' % out_path).encode())
print(rd().decode(errors="replace"))
PYEOF

kill "$QEMU_PID" 2>/dev/null || true
wait "$QEMU_PID" 2>/dev/null || true

if command -v sips >/dev/null 2>&1 && [[ -f screenshot.ppm ]]; then
  sips -s format png screenshot.ppm --out screenshot.png >/dev/null
  echo "OK: captura guardada en $SCRIPT_DIR/screenshot.png"
else
  echo "OK: captura guardada en $SCRIPT_DIR/screenshot.ppm (instala 'sips' o convierte a mano para verla como PNG)"
fi
echo "Log de consola del kernel en $SCRIPT_DIR/boot_console.log"
