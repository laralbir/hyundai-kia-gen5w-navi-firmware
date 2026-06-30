#!/usr/bin/env bash
# Wrapper para update-patcher — parchea mango-rootfs.tar.gz con wideopen.service + Engineering Mode bypass
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
PATCHER_DIR="$TOOLS_DIR/update-patcher"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo "=== Fase 3: Parche del rootfs ==="

# Verificar rootfs
ROOTFS="$SCRIPT_DIR/update/mango-rootfs.tar.gz"
[[ -f "$ROOTFS" ]] || fail "Falta update/mango-rootfs.tar.gz — copiar desde phase2_decrypt/ota_files/decrypted/"

# Verificar que es gzip válido
MAGIC=$(xxd "$ROOTFS" | head -1 | awk '{print $2$3}')
[[ "$MAGIC" == "1f8b"* ]] || fail "update/mango-rootfs.tar.gz no parece ser gzip válido (magic: $MAGIC). ¿Está descifrado?"
ok "Rootfs válido: $(du -h "$ROOTFS" | awk '{print $1}')"

# Verificar patcher repo
[[ -d "$PATCHER_DIR" ]] || fail "Repo update-patcher no clonado — ejecutar ../setup.sh"

# Copiar archivos necesarios al repo del patcher (espera la estructura update/mango-rootfs.tar.gz)
echo "Copiando rootfs al directorio de trabajo del patcher..."
cp "$ROOTFS" "$PATCHER_DIR/update/mango-rootfs.tar.gz"
mkdir -p "$PATCHER_DIR/update/output"

echo ""
echo "Construyendo imagen Docker del patcher..."
cd "$PATCHER_DIR"
docker compose build --progress=plain

echo ""
echo "Ejecutando parche (puede tardar 5-15 minutos)..."
echo "El patcher:"
echo "  - Extrae el rootfs"
echo "  - Instala wideopen.service"
echo "  - Parchea QML para desbloquear Engineering Mode"
echo "  - Crea symlink dropbear (SSH)"
echo "  - Reempaqueta en formato ustar"
echo ""
docker compose up

# Copiar resultado de vuelta
RESULT="$PATCHER_DIR/update/output/mango-rootfs.tar.gz"
if [[ -f "$RESULT" ]]; then
    cp "$RESULT" "$SCRIPT_DIR/update/output/mango-rootfs.tar.gz"
    SIZE=$(du -h "$SCRIPT_DIR/update/output/mango-rootfs.tar.gz" | awk '{print $1}')
    ok "Rootfs parcheado: tools/phase3_patch/update/output/mango-rootfs.tar.gz ($SIZE)"
else
    fail "El patcher no generó el archivo de salida"
fi

echo ""
echo "=== Verificando parche ==="

# Verificar wideopen.service
if tar -tzf "$SCRIPT_DIR/update/output/mango-rootfs.tar.gz" 2>/dev/null | grep -q "wideopen.service"; then
    ok "wideopen.service presente en el rootfs"
else
    warn "wideopen.service NO encontrado en el rootfs"
fi

# Verificar parche QML
QML_CHECK=$(tar -xzf "$SCRIPT_DIR/update/output/mango-rootfs.tar.gz" \
    -O ./app/share/AppEngineerMode/AppEngineerMode_PinCodeKeypad.qml 2>/dev/null | \
    grep -c "== 21\|== 11" || echo 0)
if [[ "$QML_CHECK" -eq 0 ]]; then
    ok "QML Engineering Mode parcheado correctamente"
else
    warn "QML todavía contiene checks de PIN (enterMenu == 21/11)"
fi

echo ""
echo "Rootfs parcheado listo en: tools/phase3_patch/update/output/mango-rootfs.tar.gz"
echo ""
echo "Para instalar en el HU, copiar al USB en la estructura OTA:"
echo "  USB:/HU/images/mango-rootfs.tar.gz"
echo ""
echo "O explorar el rootfs descifrado con: cd ../phase4_explore/"
