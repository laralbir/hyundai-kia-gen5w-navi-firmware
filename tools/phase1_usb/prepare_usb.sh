#!/usr/bin/env bash
# Prepara el USB exFAT con los scripts necesarios para la extracción de claves.
# Uso: ./prepare_usb.sh <mount_point>
# Ejemplo macOS: ./prepare_usb.sh /Volumes/USB
# Ejemplo Linux: ./prepare_usb.sh /mnt/usb
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="$(dirname "$SCRIPT_DIR")"
NAVI_USB="$TOOLS_DIR/navi_extended/USB_FILES"

USB="${1:-}"
if [[ -z "$USB" ]]; then
    echo "Uso: $0 <punto_de_montaje_del_USB>"
    echo "Ejemplo: $0 /Volumes/USB"
    exit 1
fi

[[ -d "$USB" ]] || { echo "ERROR: $USB no existe o no está montado"; exit 1; }

# Verificar que los repos están clonados
[[ -d "$NAVI_USB" ]] || { echo "ERROR: Repo navi_extended no encontrado. Ejecuta primero: ../setup.sh"; exit 1; }

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

echo "=== Preparando USB en $USB ==="

# Verificar formato exFAT
FS_TYPE=$(diskutil info "$USB" 2>/dev/null | grep "File System" | awk '{print $NF}' || df -T "$USB" 2>/dev/null | tail -1 | awk '{print $2}' || echo "unknown")
echo "Formato detectado: $FS_TYPE"
if [[ "$FS_TYPE" != *"exFAT"* && "$FS_TYPE" != *"exfat"* ]]; then
    warn "El USB no parece ser exFAT (detectado: $FS_TYPE). El HU requiere exFAT."
    read -rp "¿Continuar de todas formas? [s/N] " resp
    [[ "$resp" =~ ^[sS]$ ]] || exit 1
fi

# Limpiar STATUS_FLAGS anteriores si existen
[[ -d "$USB/STATUS_FLAGS" ]] && rm -rf "$USB/STATUS_FLAGS" && warn "STATUS_FLAGS anteriores eliminados"

# Copiar scripts principales
echo "Copiando scripts..."
cp "$NAVI_USB/main_loop.sh"      "$USB/"  && ok "main_loop.sh"

# main_loop_code.sh del repo upstream navi_extended es una PLANTILLA VACÍA (solo hace `ls`,
# nunca llama a extract_keys.sh — verificado leyendo el fuente el 2026-07-11). Si se copiara
# tal cual, el HU no haría nada útil en bucle. Escribimos aquí la versión que sí despacha a
# extract_keys.sh, en vez de editar el clon de terceros (no rastreado por este repo, se
# perdería en un re-clone de ../setup.sh).
cat > "$USB/main_loop_code.sh" <<'DISPATCH'
#!/bin/bash

USB_PATH=$(dirname $0)
cd $USB_PATH

printf "\n----- Caller:($(ps -o comm= $PPID)) - PID:($PPID) - At($(date)) -----\n" ;

# extract_keys.sh es idempotente (usa sus propios flags en STATUS_FLAGS/ para no repetir
# pasos ya hechos) — es seguro llamarlo en cada iteración del bucle de 10s.
if [ -f "./INITIAL_SETUP_SCRIPTS/extract_keys.sh" ]; then
    bash ./INITIAL_SETUP_SCRIPTS/extract_keys.sh
fi

printf "\n----- END Caller:($(ps -o comm= $PPID)) - PID:($PPID) - At($(date)) END -----\n" ;
DISPATCH
chmod +x "$USB/main_loop_code.sh"
ok "main_loop_code.sh (versión corregida — la del repo upstream no llama a extract_keys.sh)"

# Copiar scripts de setup inicial
mkdir -p "$USB/INITIAL_SETUP_SCRIPTS"
cp "$NAVI_USB/INITIAL_SETUP_SCRIPTS/extract_keys.sh"  "$USB/INITIAL_SETUP_SCRIPTS/" && ok "extract_keys.sh"
cp "$NAVI_USB/INITIAL_SETUP_SCRIPTS/restore_appnavi.sh" "$USB/INITIAL_SETUP_SCRIPTS/" && ok "restore_appnavi.sh"

# Copiar sonido de completado si existe
[[ -f "$NAVI_USB/INITIAL_SETUP_SCRIPTS/completed_setup_sound_mp3" ]] && \
    cp "$NAVI_USB/INITIAL_SETUP_SCRIPTS/completed_setup_sound_mp3" "$USB/INITIAL_SETUP_SCRIPTS/" && ok "completed_setup_sound_mp3"

# Copiar DecryptToPIPE variants
cp "$NAVI_USB/DecryptToPIPE_FK" "$USB/" && ok "DecryptToPIPE_FK"
cp "$NAVI_USB/DecryptToPIPE_RC" "$USB/" && ok "DecryptToPIPE_RC"

# Copiar scripts de wideopen (persistencia)
cp "$NAVI_USB/install_wideopen_service.sh"    "$USB/" && ok "install_wideopen_service.sh"
cp "$NAVI_USB/wideopen.service"               "$USB/" && ok "wideopen.service"
cp "$NAVI_USB/wideopen_service.sh"            "$USB/" && ok "wideopen_service.sh"
cp "$NAVI_USB/wideopen_service_first_run.sh"  "$USB/" && ok "wideopen_service_first_run.sh"

# Copiar scripts EXTREMELY_RISKY (para emergencias)
mkdir -p "$USB/EXTREMELY_RISKY_BECAREFUL"
cp "$NAVI_USB/EXTREMELY_RISKY_BECAREFUL/"* "$USB/EXTREMELY_RISKY_BECAREFUL/" && ok "EXTREMELY_RISKY scripts"

# Binario navi_extended compilado (build linux-x64 self-contained), si existe.
# El mecanismo real de instalación inicial (menú "Update AppNavi from USB" dentro de
# Engineering Mode) no está confirmado con precisión — ver aviso en README.md de esta
# carpeta. Se copia en dos ubicaciones candidatas por si acaso; verificar en el HU real
# cuál (si alguna) recoge el menú de actualización.
NAVI_BUILD="$TOOLS_DIR/navi_extended/bin/Release/net6.0/linux-x64/publish/navi_extended"
if [[ -f "$NAVI_BUILD" ]]; then
    cp "$NAVI_BUILD" "$USB/AppNavi" && ok "AppNavi (navi_extended compilado, candidato raíz USB)"
    mkdir -p "$USB/navi_eu"
    cp "$NAVI_BUILD" "$USB/navi_eu/AppNavi" && ok "navi_eu/AppNavi (candidato alternativo, imita estructura OTA real)"
else
    warn "navi_extended no está compilado — ejecuta primero: cd ../navi_extended && dotnet publish -c Release -r linux-x64 --self-contained true"
fi

# Crear directorio de status
mkdir -p "$USB/STATUS_FLAGS"

# Sincronizar
sync
echo ""
echo "=== USB listo ==="
echo ""
echo "Contenido del USB:"
ls -la "$USB/"
echo ""
echo "Estructura esperada del USB:"
cat <<'EOF'
USB:/
├── AppNavi                          ← navi_extended compilado (candidato para reemplazar AppNavi; sin confirmar)
├── navi_eu/AppNavi                  ← mismo binario, ruta alternativa (imita estructura OTA real)
├── main_loop.sh                     ← script lanzador (ejecutado por navi_extended una vez instalado)
├── main_loop_code.sh                ← dispatcher CORREGIDO (llama a extract_keys.sh; el del repo upstream no lo hacía)
├── DecryptToPIPE_FK                 ← versión que extrae la clave (standard)
├── DecryptToPIPE_RC                 ← versión alternativa de hardware
├── install_wideopen_service.sh      ← instala el servicio de persistencia
├── wideopen.service                 ← servicio systemd
├── wideopen_service.sh              ← script del servicio
├── wideopen_service_first_run.sh    ← primer arranque post-instalación
├── INITIAL_SETUP_SCRIPTS/
│   ├── extract_keys.sh              ← EXTRAE DecryptToPIPE + un fichero *_key_*.der
│   └── restore_appnavi.sh           ← restaura el AppNavi oficial (requiere appnavi.tar + la clave)
├── EXTREMELY_RISKY_BECAREFUL/       ← solo en emergencias
│   ├── spoof_decrypttopipe.sh
│   ├── restore_decrypttopipe_og.sh
│   └── update_navi_manually.sh
└── STATUS_FLAGS/                    ← flags de progreso (se crean durante ejecución)
EOF
echo ""
echo "IMPORTANTE: Copia también el OTA oficial al USB si vas a hacer restore_appnavi:"
echo "  cp /path/to/appnavi.tar $USB/HU/images/navi_eu/appnavi.tar"
echo ""
echo "⚠️  Punto de entrada sin confirmar: cómo hacer que el HU ejecute AppNavi/navi_extended"
echo "    por primera vez sigue siendo incierto (bloqueo de Engineering Mode) — ver la sección"
echo "    '⚠️ El verdadero bloqueante' en README.md de esta carpeta antes de conectar el USB."
echo ""
echo "Siguiente: conecta el USB al HU y espera 3 ciclos de reinicio (~10-15 min)"
echo "Luego verifica que aparecen en el USB: un fichero *_key_*.der + STATUS_FLAGS/EXTRACT_KEYS_STAGE_2_FLAG"
