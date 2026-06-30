#!/usr/bin/env bash
# Clona todos los repos gen5w en tools/ y verifica dependencias.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo "=== gen5w RE setup ==="

# Verificar dependencias
for dep in git docker; do
    command -v "$dep" &>/dev/null && ok "$dep found" || fail "$dep not found — install it first"
done

for dep in pv dialog xxd; do
    command -v "$dep" &>/dev/null && ok "$dep found" || warn "$dep not found (optional but recommended)"
done

# Clonar repos gen5w
declare -A REPOS=(
    ["navi_extended"]="https://gitlab.com/g4933/gen5w/navi_extended.git"
    ["update_decryptor"]="https://gitlab.com/g4933/gen5w/update_decryptor.git"
    ["update-patcher"]="https://gitlab.com/g4933/gen5w/update-patcher.git"
    ["gen5w-docker"]="https://gitlab.com/g4933/gen5w/gen5w-docker.git"
    ["update_fetcher"]="https://gitlab.com/g4933/gen5w/update_fetcher.git"
)

for name in "${!REPOS[@]}"; do
    url="${REPOS[$name]}"
    if [[ -d "$name/.git" ]]; then
        ok "$name already cloned — pulling latest"
        git -C "$name" pull --ff-only 2>/dev/null || warn "$name: could not pull (offline?)"
    else
        echo "Cloning $name..."
        git clone "$url" "$name" && ok "$name cloned" || fail "Could not clone $name"
    fi
done

# Verificar que los archivos clave están presentes
echo ""
echo "=== Verifying key files ==="

check_file() {
    local f="$1"
    [[ -f "$f" ]] && ok "$f" || warn "Missing: $f"
}

check_file "navi_extended/USB_FILES/main_loop.sh"
check_file "navi_extended/USB_FILES/main_loop_code.sh"
check_file "navi_extended/USB_FILES/INITIAL_SETUP_SCRIPTS/extract_keys.sh"
check_file "navi_extended/USB_FILES/INITIAL_SETUP_SCRIPTS/restore_appnavi.sh"
check_file "navi_extended/USB_FILES/DecryptToPIPE_FK"
check_file "navi_extended/USB_FILES/DecryptToPIPE_RC"
check_file "update_decryptor/Dockerfile"
check_file "update_decryptor/entrypoint.sh"
check_file "update-patcher/Dockerfile"
check_file "update-patcher/update_patcher.sh"
check_file "gen5w-docker/docker-compose.yaml"

echo ""
echo "=== Setup complete ==="
echo "Next step: read tools/README.md for the full guide"
echo "To prepare the USB for key extraction: ./phase1_usb/prepare_usb.sh"
