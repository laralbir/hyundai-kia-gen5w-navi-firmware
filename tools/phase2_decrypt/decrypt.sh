#!/usr/bin/env bash
# Wrapper para update_decryptor — descifra todos los archivos OTA en ota_files/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
DECRYPTOR_DIR="$TOOLS_DIR/update_decryptor"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }

echo "=== Fase 2: Descifrado OTA ==="

# Verificar claves
[[ -f "$SCRIPT_DIR/keys/DecryptToPIPE" ]]     || fail "Falta keys/DecryptToPIPE — copiar del USB"
[[ -f "$SCRIPT_DIR/keys/decryption_key.der" ]] || fail "Falta keys/decryption_key.der — copiar del USB"

# Verificar que la clave no es el placeholder del repo
KEY_SIZE=$(wc -c < "$SCRIPT_DIR/keys/decryption_key.der")
if [[ "$KEY_SIZE" -lt 100 ]]; then
    fail "decryption_key.der parece ser el placeholder del repo (${KEY_SIZE} bytes). Usar la clave real del HU."
fi
ok "Claves encontradas (key: ${KEY_SIZE} bytes)"

# Verificar archivos OTA
OTA_COUNT=$(find "$SCRIPT_DIR/ota_files" -maxdepth 1 -type f | wc -l)
[[ "$OTA_COUNT" -gt 0 ]] || fail "No hay archivos OTA en ota_files/ — copiar desde el paquete de firmware"
ok "$OTA_COUNT archivos OTA encontrados"

# Construir imagen Docker si no existe
if ! docker image inspect gen5wdecryptor &>/dev/null; then
    [[ -d "$DECRYPTOR_DIR" ]] || fail "Repo update_decryptor no clonado — ejecutar ../setup.sh"
    echo "Construyendo imagen Docker gen5wdecryptor..."
    docker build -t gen5wdecryptor "$DECRYPTOR_DIR" || fail "Error al construir la imagen Docker"
    ok "Imagen Docker construida"
else
    ok "Imagen Docker gen5wdecryptor ya existe"
fi

# Ejecutar descifrado
echo ""
echo "Iniciando descifrado (puede tardar varios minutos por archivo)..."
echo "Los archivos descifrados aparecerán en ota_files/decrypted/"
echo ""

docker run --rm -it \
    --platform linux/amd64 \
    -v "$SCRIPT_DIR/keys/DecryptToPIPE:/DecryptToPIPE" \
    -v "$SCRIPT_DIR/keys/decryption_key.der:/decryption_key.der" \
    -v "$SCRIPT_DIR/ota_files:/mnt" \
    gen5wdecryptor

echo ""
echo "=== Verificando resultados ==="
if [[ -d "$SCRIPT_DIR/ota_files/decrypted" ]]; then
    DECRYPTED_COUNT=$(find "$SCRIPT_DIR/ota_files/decrypted" -type f | wc -l)
    ok "$DECRYPTED_COUNT archivos descifrados en ota_files/decrypted/"
    echo ""
    for f in "$SCRIPT_DIR/ota_files/decrypted/"*; do
        [[ -f "$f" ]] || continue
        MAGIC=$(xxd "$f" 2>/dev/null | head -1 | awk '{print $2,$3,$4,$5}')
        printf "  %-40s %s\n" "$(basename "$f")" "$MAGIC"
    done
else
    warn "No se creó el directorio decrypted/ — posiblemente ningún archivo fue descifrado"
    warn "Verificar que DecryptToPIPE y decryption_key.der son los correctos para este HU"
fi

echo ""
echo "Siguiente: cd ../phase3_patch/ para parchear el rootfs"
