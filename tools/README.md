# Tools — Guía completa de acceso y RE del Head Unit Gen5W

**Plataforma objetivo:** mango / S5W (x86-64 Linux embebido)  
**Dispositivo:** Kia Rio MY22 EU — Standard Gen5W Navigation  
**Fuente upstream:** `gitlab.com/g4933/gen5w` (grupo público)

---

## Arquitectura del sistema

Antes de empezar, puntos críticos confirmados por RE:

| Hecho | Fuente |
|---|---|
| SoC **x86-64** (no ARM) | payload.s usa syscalls Linux x86-64: fork=57, execve=59 |
| SO **Linux embebido** con systemd | `wideopen.service` systemd; `dropbearmulti` SSH |
| AppNavi vive en `/navi/Bin/AppNavi` y `/navi2/Bin/AppNavi` | restore_appnavi.sh |
| `DecryptToPIPE` vive en `/app/share/AppUpgrade/DecryptToPIPE` | restore_decrypttopipe_og.sh |
| El rootfs se monta **read-only**; se remonta rw con `mount -o remount,rw /` | múltiples scripts |
| Engineering Mode bloqueado por `checkSOPVersion()` en MASS_PRODUCT | update_patcher.sh QML patches |
| UI construida en **Qt/QML** | AppEngineerMode_PinCodeKeypad.qml |
| `dropbear` SSH disponible en el rootfs | update_patcher.sh symlink |

---

## Resumen de las fases

```
┌─────────────────────────────────────────────────────────────────┐
│ FASE 0 — Prerequisitos                                          │
│ Verificar versión del HU, preparar entorno, clonar repos gen5w  │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ FASE 1 — Exploit USB (navi_extended)                            │
│ USB exFAT con main_loop.sh → ejecuta código en el HU           │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ FASE 2 — Extracción de claves                                   │
│ extract_keys.sh → DecryptToPIPE_FK → decryption_key.der en USB │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ FASE 3 — Descifrado OTA (PC)                                    │
│ update_decryptor Docker → carpeta decrypted/ con todo el OTA   │
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ FASE 4 — Parche del rootfs (PC)                                 │
│ update_patcher Docker → mango-rootfs.tar.gz con wideopen.service│
└──────────────────────────┬──────────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────────┐
│ FASE 5 — Exploración del rootfs (PC)                           │
│ gen5w-docker chroot → análisis de binarios, filesystem, configs │
└─────────────────────────────────────────────────────────────────┘
```

---

## Fase 0 — Prerequisitos

### 0.1 Clonar todos los repos gen5w

```bash
# Desde la raíz del proyecto
cd tools/
git clone https://gitlab.com/g4933/gen5w/navi_extended.git
git clone https://gitlab.com/g4933/gen5w/update_decryptor.git
git clone https://gitlab.com/g4933/gen5w/update-patcher.git
git clone https://gitlab.com/g4933/gen5w/gen5w-docker.git
git clone https://gitlab.com/g4933/gen5w/update_fetcher.git
```

O usar el script:
```bash
./setup.sh
```

### 0.2 Dependencias en el PC

```bash
# macOS
brew install docker pv dialog

# Linux
apt install docker.io pv dialog
```

### 0.3 Estado del HU — ¿Parcheado o sin parchear?

| Estado | Síntoma | Acción |
|---|---|---|
| **Sin parchear** (stock) | Engineering Mode bloqueado, AppNavi oficial | Sigue desde Fase 1 |
| **Parcheado** (wideopen instalado) | Engineering Mode libre, SSH activo | Puedes ir directo a Fase 2 |

Para verificar si el HU tiene wideopen instalado: intenta conectar por SSH al HU (IP del HU en red local, puerto 22).

### 0.4 Preparar USB

- Formato: **exFAT** (obligatorio — el HU no monta FAT32 ni NTFS para scripts)
- Tamaño recomendado: mínimo 32 GB (para copiar archivos OTA completos)
- Partición: una sola partición primaria

---

## Fase 1 — Exploit USB (navi_extended)

> **Requiere:** HU en estado inicial (sin wideopen) con una versión de AppNavi que soporte ejecución de scripts USB. Ver [engineering_mode.md](../docs/engineering_mode.md) para detalles sobre el punto de entrada inicial.

### 1.1 Compilar navi_extended (C# .NET)

```bash
cd tools/navi_extended/
# Requiere .NET SDK instalado
dotnet publish -c Release -r linux-x64 --self-contained true
# El binario resultante es el ejecutable para el HU (x86-64 Linux)
```

O descargar el binario precompilado si el repo lo proporciona:
```bash
ls navi_extended/USB_FILES/   # buscar binario AppNavi precompilado
```

### 1.2 Preparar el USB (fase de extracción de claves)

```bash
# Usar el script de preparación:
./phase1_usb/prepare_usb.sh /dev/diskX   # macOS: /dev/disk2, Linux: /dev/sdb
```

Estructura que debe quedar en la raíz del USB:
```
USB:/
├── AppUpgrade           ← directorio (o binario navi_extended como AppNavi)
├── main_loop.sh         ← script lanzador (desde navi_extended/USB_FILES/)
├── main_loop_code.sh    ← dispatcher de lógica
├── INITIAL_SETUP_SCRIPTS/
│   ├── extract_keys.sh       ← extractor de claves (2 fases)
│   └── restore_appnavi.sh    ← restaura AppNavi real parcheada
├── DecryptToPIPE_FK     ← versión modificada que vuelca la clave (del repo)
└── STATUS_FLAGS/        ← se crea solo durante la ejecución
```

Copiar desde el repo:
```bash
cp navi_extended/USB_FILES/main_loop.sh /Volumes/USB/
cp navi_extended/USB_FILES/main_loop_code.sh /Volumes/USB/
cp -r navi_extended/USB_FILES/INITIAL_SETUP_SCRIPTS/ /Volumes/USB/
cp navi_extended/USB_FILES/DecryptToPIPE_FK /Volumes/USB/
cp navi_extended/USB_FILES/DecryptToPIPE_RC /Volumes/USB/   # alternativa según HW
```

**¿FK o RC?**
- `DecryptToPIPE_FK` — versión estándar (la mayoría de unidades)
- `DecryptToPIPE_RC` — variante de hardware alternativa

### 1.3 Conectar USB al HU y esperar ejecución

1. Conectar el USB al puerto USB del vehículo (no la consola central — el USB de datos, normalmente en guantera o bajo la pantalla).
2. Esperar que la pantalla de navegación reinicie (puede tardar 2-5 minutos).
3. El HU ejecutará varios ciclos:
   - **Ciclo 1:** Reemplaza `DecryptToPIPE` con la versión FK → reinicio automático
   - **Ciclo 2:** DecryptToPIPE_FK vuelca la clave a `decryption_key.der` en el USB → reinicio
   - **Ciclo 3:** Restaura `DecryptToPIPE` original → reinicio final
4. Mantener el USB conectado durante TODO el proceso (3 reinicios).

### 1.4 Verificar éxito

Revisar la raíz del USB después del proceso. Deben aparecer:
```
USB:/
├── decryption_key.der   ← ¡LA CLAVE! Guardar en lugar seguro
├── STATUS_FLAGS/
│   ├── STAGE1_DONE
│   └── STAGE2_DONE
└── loop_output.txt      ← log de ejecución
```

> **CRÍTICO:** Copiar `decryption_key.der` al PC inmediatamente. Sin este archivo, no se puede descifrar ningún OTA. También copiar el `DecryptToPIPE` original del HU (lo copia `extract_keys.sh` al USB).

---

## Fase 2 — Descifrado OTA en PC

### 2.1 Preparar el directorio de trabajo

> **⚠️ Corrección (validada con dry-run 2026-07-11, ver [docs/gen5w_exploit_ecosystem.md](../docs/gen5w_exploit_ecosystem.md#validación-práctica-del-pipeline-dry-run-sin-hu-físico)):**
> `DecryptToPIPE` y `decryption_key.der` **NO se montan como volumen en runtime** — el `Dockerfile` de `update_decryptor` hace `COPY ./ /` en tiempo de build, así que se incrustan en la imagen. El volumen `-v keys:/DecryptToPIPE_dir` de versiones anteriores de esta guía **no tenía ningún efecto** (ruta muerta, `entrypoint.sh` busca `/DecryptToPIPE` y `/decryption_key.der` en la raíz). Hay que **reemplazar los placeholders del repo antes de construir la imagen**.

```bash
cd tools/update_decryptor/

# Sustituir los placeholders por los archivos reales obtenidos del HU:
cp /Volumes/USB/DecryptToPIPE      ./DecryptToPIPE
cp /Volumes/USB/decryption_key.der ./decryption_key.der

cd ../phase2_decrypt/
# Copiar los archivos OTA cifrados a descifrar:
cp /path/to/Rio_MY22_EU/HU/images/mango-rootfs.tar.gz       ota_files/
cp /path/to/Rio_MY22_EU/HU/images/new_gui.tar.gz            ota_files/
cp /path/to/Rio_MY22_EU/HU/firmware/update.tar.gz           ota_files/
cp /path/to/Rio_MY22_EU/HU/images/iasImage                  ota_files/
cp /path/to/Rio_MY22_EU/HU/images/navi_eu/appnavi.tar        ota_files/
# etc — todos los archivos que quieras descifrar
```

### 2.2 Ejecutar update_decryptor

```bash
# Construir la imagen (con DecryptToPIPE + decryption_key.der reales ya copiados dentro)
cd ../update_decryptor/
docker build -t gen5wdecryptor ./

# Ejecutar solo contra los archivos OTA — sin volumen de claves, ya están en la imagen
cd ../phase2_decrypt/
docker run --rm -it \
  -v $PWD/ota_files:/mnt \
  gen5wdecryptor
```

**Resultado:** directorio `ota_files/decrypted/` con todos los archivos descifrados en formato estándar (gzip, tar, etc.).

### 2.3 Verificar descifrado

```bash
file ota_files/decrypted/mango-rootfs.tar.gz
# Debe responder: gzip compressed data
# Magic bytes esperados: 1f 8b

xxd ota_files/decrypted/mango-rootfs.tar.gz | head -2
```

---

## Fase 3 — Parche del rootfs (persistencia)

Esta fase modifica `mango-rootfs.tar.gz` para añadir el servicio `wideopen.service`, que instala la persistencia del exploit y desbloquea Engineering Mode permanentemente.

### 3.1 Qué hace el parche

El `update_patcher.sh` aplica sobre el rootfs descifrado:

1. **Instala `wideopen.service`** en `/etc/systemd/system/` con enlace en `multi-user.target.wants/` → se ejecuta en cada arranque.
2. **Desbloquea Engineering Mode** — modifica el QML `AppEngineerMode_PinCodeKeypad.qml`:
   ```
   enterMenu == 21  →  enterMenu   (cualquier valor no-cero = acceso libre)
   enterMenu == 11  →  enterMenu
   ```
3. **Deshabilita el bloqueo SOP** en todos los QML:
   ```
   checkSOPVersion() ===  →  checkSOPVersion() !==   (invierte la lógica)
   : AppEngineerModeEngine.checkSOPVersion()  →  : false
   ```
4. **Habilita SSH** — symlink `dropbearmulti → dropbear` en `/usr/sbin/`.
5. **Reempaqueta** en formato **ustar** con ownership numérico.

### 3.2 Ejecutar el patcher

```bash
cd tools/update-patcher/

# Copiar rootfs descifrado al lugar esperado:
cp ../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz update/

# Construir y ejecutar:
docker compose build
docker compose up

# El rootfs parcheado aparece en:
ls update/output/mango-rootfs.tar.gz
```

### 3.3 Instalar el rootfs parcheado en el HU

**Método A — Via OTA update (recomendado):**
1. El wideopen.service en la primera ejecución activa `disableEncryptionUpdate`.
2. Copiar `mango-rootfs.tar.gz` parcheado al USB en la estructura OTA correcta.
3. El HU acepta el update sin verificación de firma.

**Método B — Via SSH (si dropbear ya está activo):**
```bash
# Conectar al HU por SSH (usuario root, sin contraseña en dev units)
ssh root@<HU_IP>
# Montar rootfs rw y reemplazar manualmente
mount -o remount,rw /
cp /media/usb/mango-rootfs-patched.tar.gz /update/
```

---

## Fase 4 — Exploración del rootfs (RE)

Una vez descifrado `mango-rootfs.tar.gz`, explorar con gen5w-docker o directamente.

### 4.1 Extracción local directa

```bash
cd tools/phase4_explore/
mkdir rootfs_extracted
tar -xzf ../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz -C rootfs_extracted/
```

### 4.2 Exploración con gen5w-docker (chroot)

```bash
cd tools/gen5w-docker/

# Copiar rootfs descifrado:
cp ../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz ./

# Construir y entrar:
docker compose build
docker compose run mango /chroot.sh    # chroot completo
# o
docker compose run mango               # shell en el entorno
```

### 4.3 Objetivos de RE en el rootfs

Una vez dentro del rootfs, buscar:

```bash
# Proceso de actualización OTA
find /app/share/AppUpgrade/ -type f
ls /app/share/AppUpgrade/

# Gestión de HERE Maps
find / -name "*.so" | xargs strings | grep -i "here\|nds\|haf"

# Configuración del sistema
cat /etc/version
cat /etc/platform

# Servicios systemd relevantes
ls /etc/systemd/system/

# Binarios clave
ls /Bin/
ls /usr/bin/ | grep -E "decrypt|update|fota|navi"

# Claves hardcodeadas
strings /app/share/AppUpgrade/DecryptToPIPE | grep -v "^.$"
```

---

## Archivos críticos del HU (rutas internas)

| Archivo | Ruta en el HU | Descripción |
|---|---|---|
| `AppNavi` | `/navi/Bin/AppNavi` y `/navi2/Bin/AppNavi` | App de navegación (2 particiones) |
| `DecryptToPIPE` | `/app/share/AppUpgrade/DecryptToPIPE` | Binario de descifrado OTA |
| `DecryptToPIPE_OG` | `/app/share/AppUpgrade/DecryptToPIPE_OG` | Backup del original |
| `wideopen.service` | `/etc/systemd/system/wideopen.service` | Servicio de persistencia (post-parche) |
| `dropbear` | `/usr/sbin/dropbear` → `dropbearmulti` | SSH server (post-parche) |
| `AppEngineerMode_PinCodeKeypad.qml` | `/app/share/AppEngineerMode/` | UI Engineering Mode |
| Update flag | `/update/disableEncryptionUpdate` | Flag para desactivar cifrado en updates |

---

## Notas de seguridad

- `EXTREMELY_RISKY/spoof_decrypttopipe.sh` — reemplaza DecryptToPIPE por la versión FK permanentemente. **No usar** a menos que extract_keys.sh haya fallado; puede dejar el HU sin capacidad de actualización.
- `EXTREMELY_RISKY/restore_decrypttopipe_og.sh` — restaura desde el backup. Usar si spoof_decrypttopipe.sh dejó la unidad en mal estado.
- `EXTREMELY_RISKY/update_navi_manually.sh` — reemplaza AppNavi manualmente. Usar solo si restore_appnavi.sh falló.
- Si el proceso se interrumpe en medio de una fase, revisar `STATUS_FLAGS/` en el USB para saber en qué punto quedó.

---

## Referencias

- [Análisis completo del ecosistema gen5w](../docs/gen5w_exploit_ecosystem.md)
- [Engineering Mode — análisis de acceso](../docs/engineering_mode.md)
- Repo upstream: `gitlab.com/g4933/gen5w`
