#!/usr/bin/env bash
# Extrae y analiza el rootfs descifrado localmente.
# Uso: ./explore.sh <path/to/mango-rootfs.tar.gz>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOTFS_TGZ="${1:-../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz}"
EXTRACT_DIR="$SCRIPT_DIR/rootfs_extracted"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()      { echo -e "${GREEN}[OK]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()    { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
section() { echo -e "\n${CYAN}=== $* ===${NC}"; }

echo "=== Fase 4: Exploración del rootfs ==="
echo "Fuente: $ROOTFS_TGZ"

[[ -f "$ROOTFS_TGZ" ]] || fail "Archivo no encontrado: $ROOTFS_TGZ"

# Verificar que es gzip
MAGIC=$(xxd "$ROOTFS_TGZ" | head -1 | awk '{print $2$3}')
[[ "$MAGIC" == "1f8b"* ]] || fail "No parece ser gzip (magic: $MAGIC). ¿Está descifrado?"

# Extraer si no existe o si el usuario lo pide
if [[ -d "$EXTRACT_DIR" ]] && [[ -n "$(ls -A "$EXTRACT_DIR" 2>/dev/null)" ]]; then
    echo "Directorio $EXTRACT_DIR ya existe."
    read -rp "¿Re-extraer? (puede tardar varios minutos) [s/N] " resp
    if [[ "$resp" =~ ^[sS]$ ]]; then
        rm -rf "$EXTRACT_DIR"
    fi
fi

if [[ ! -d "$EXTRACT_DIR" ]] || [[ -z "$(ls -A "$EXTRACT_DIR" 2>/dev/null)" ]]; then
    mkdir -p "$EXTRACT_DIR"
    echo "Extrayendo rootfs (puede tardar varios minutos)..."
    tar -xzf "$ROOTFS_TGZ" -C "$EXTRACT_DIR"
    ok "Rootfs extraído en $EXTRACT_DIR"
else
    ok "Usando rootfs ya extraído en $EXTRACT_DIR"
fi

# ─── Análisis básico ───────────────────────────────────────────────────────────

section "Arquitectura y versión del sistema"
if [[ -f "$EXTRACT_DIR/etc/version" ]]; then
    echo "Versión SW:"; cat "$EXTRACT_DIR/etc/version"
fi
if [[ -f "$EXTRACT_DIR/etc/platform" ]]; then
    echo "Plataforma:"; cat "$EXTRACT_DIR/etc/platform"
fi

# Detectar arquitectura
SAMPLE_BIN=$(find "$EXTRACT_DIR/usr/bin" -type f -executable 2>/dev/null | head -1)
if [[ -n "$SAMPLE_BIN" ]]; then
    echo "Arquitectura binarios: $(file "$SAMPLE_BIN" | grep -oE 'ELF [0-9]+-bit [A-Z]+ executable, [^,]+')"
fi

section "Estructura del filesystem"
du -sh "$EXTRACT_DIR"/*/  2>/dev/null | sort -hr | head -20

section "DecryptToPIPE — binario de descifrado OTA"
DTP="$EXTRACT_DIR/app/share/AppUpgrade/DecryptToPIPE"
if [[ -f "$DTP" ]]; then
    ok "Encontrado: $DTP"
    echo "Tipo: $(file "$DTP")"
    echo "Tamaño: $(du -h "$DTP" | awk '{print $1}')"
    echo ""
    echo "Strings relevantes (primeros 30):"
    strings "$DTP" | grep -iE "key|cert|aes|rsa|der|pem|decrypt|encrypt|openssl|evp|cipher" | head -30 || echo "(ninguno)"
else
    warn "DecryptToPIPE NO encontrado en $DTP"
    echo "Buscando en todo el filesystem..."
    find "$EXTRACT_DIR" -name "*DecryptToPIPE*" -o -name "*decrypt*" 2>/dev/null | grep -v ".pyc"
fi

section "AppNavi — aplicación de navegación"
for NAVI_BIN in "$EXTRACT_DIR/navi/Bin/AppNavi" "$EXTRACT_DIR/navi2/Bin/AppNavi"; do
    if [[ -f "$NAVI_BIN" ]]; then
        ok "Encontrado: $NAVI_BIN"
        echo "Tipo: $(file "$NAVI_BIN")"
        echo "Tamaño: $(du -h "$NAVI_BIN" | awk '{print $1}')"
    else
        warn "No encontrado: $NAVI_BIN"
    fi
done

section "Servicios systemd"
ls "$EXTRACT_DIR/etc/systemd/system/" 2>/dev/null | grep "\.service$" | while read -r svc; do
    echo "  $svc"
done
echo ""
echo "Habilitados (multi-user.target.wants/):"
ls "$EXTRACT_DIR/etc/systemd/system/multi-user.target.wants/" 2>/dev/null | while read -r svc; do
    echo "  $svc"
done

section "Binarios del sistema (/usr/bin)"
find "$EXTRACT_DIR/usr/bin" -type f -executable 2>/dev/null | \
    xargs file 2>/dev/null | grep ELF | awk -F: '{print $1}' | xargs -I{} basename {} | sort | head -40

section "SSH — dropbear"
for f in "$EXTRACT_DIR/usr/sbin/dropbear" "$EXTRACT_DIR/usr/sbin/dropbearmulti"; do
    [[ -e "$f" ]] && { ok "$(file "$f")"; } || warn "No encontrado: $f"
done

section "Configuración de red"
cat "$EXTRACT_DIR/etc/network/interfaces" 2>/dev/null || echo "(no encontrado)"
find "$EXTRACT_DIR/etc" -name "*.conf" | xargs grep -l "eth\|wlan\|ip\|net" 2>/dev/null | head -5

section "Engineering Mode QML"
QML=$(find "$EXTRACT_DIR" -name "AppEngineerMode_PinCodeKeypad.qml" 2>/dev/null | head -1)
if [[ -n "$QML" ]]; then
    ok "Encontrado: $QML"
    echo ""
    echo "Checks de acceso:"
    grep -n "enterMenu\|checkSOPVersion\|SOP\|pinCode" "$QML" | head -20
else
    warn "AppEngineerMode_PinCodeKeypad.qml no encontrado"
    find "$EXTRACT_DIR" -name "*.qml" 2>/dev/null | head -10
fi

section "Resumen"
echo "Rootfs extraído en: $EXTRACT_DIR"
echo ""
echo "Próximos pasos de RE:"
echo "  1. Analizar $DTP con Ghidra (x86-64, buscar EVP_*, AES)"
echo "  2. Estudiar $EXTRACT_DIR/navi/Bin/AppNavi"
echo "  3. Ver servicios systemd para entender el arranque"
echo "  4. Buscar claves hardcodeadas: strings <binario> | grep -E '[0-9a-fA-F]{32,}'"
