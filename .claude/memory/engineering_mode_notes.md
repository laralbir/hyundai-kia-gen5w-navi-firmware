---
name: engineering-mode-notes
description: "Engineering Mode en gen5w: bloqueos en MASS_PRODUCT (SOP check + PIN QML enterMenu==21/11), SoC x86-64 confirmado, rutas alternativas de acceso"
metadata:
  type: project
---

## SoC x86-64 — CONFIRMADO

El payload assembly (`appnavi_payload_injector_patch/payload.s`) usa syscalls Linux x86-64:
- fork = syscall 57
- execve = syscall 59 (0x3b)
- exit = syscall 60

La plataforma **mango/S5W es x86-64**, no ARM. Confirma también el Dockerfile: `--platform=${PLATFORM:-linux/amd64}`.

## Engineering Mode — PIN y secuencia táctil (Standard Gen5W = nuestro sistema)

### PIN confirmado por análisis QML
El QML `AppEngineerMode_PinCodeKeypad.qml` compara `enterMenu` (valor numérico del PIN introducido):
- **PIN principal: `21`** → check `enterMenu == 21`
- **PIN sub-menú: `11`** → check `enterMenu == 11`

### Secuencia táctil para llegar al teclado PIN (Método A — más confirmado)
1. All menus → Settings (o botón Setup)
2. Pantalla Sound → opciones **Digital – Analogue – None**
3. Tocar **debajo** de las opciones en orden: D, A, N, A, D, A, N (**7 toques**)
4. Aparece teclado PIN → introducir `21`

### Método B (alternativo)
1. Settings → System Information
2. Tocar 5 veces a la izquierda del botón "Update", 1 vez a la derecha
3. Teclado PIN → `21`

### Dos capas de bloqueo en MASS_PRODUCT

**Capa 1 (principal):** `checkSOPVersion()` en QML — siempre falla en MASS_PRODUCT → EM bloqueado aunque el PIN sea correcto.
Parche: `checkSOPVersion() ===` → `checkSOPVersion() !==` y `: AppEngineerModeEngine.checkSOPVersion()` → `: false`

**Capa 2:** PIN `21` — bloqueado adicionalmente. Parche: `enterMenu == 21` → `enterMenu`

### PIN para Premium AVNT (NO nuestro sistema, referencia)
- Firmware EUR 251204 (nuestro build): PIN 8 dígitos `19480717` (17 julio 1948, constitución Corea del Sur)
- Firmware EUR 250226: PIN `19190301`
- Estos aplican al sistema Premium AVNT (Android/Linux premium), no al Standard Gen5W

## Rutas de acceso sin parchear

1. **Firmware pre-noviembre 2021** — sin SOP check, PIN `21` funciona directamente
2. **UART en PCB** — puerto serie debug en la PCB del HU (115200 baud, login root)
3. **GDS (Global Diagnostic System)** — herramienta de concesionario Kia/Hyundai para OBD
4. **AppNavi antiguo** — versiones que ejecutan scripts USB nativamente (base del exploit gen5w)

## Rutas internas del HU (confirmadas por scripts gen5w)

| Archivo | Ruta |
|---|---|
| AppNavi | `/navi/Bin/AppNavi` y `/navi2/Bin/AppNavi` |
| DecryptToPIPE | `/app/share/AppUpgrade/DecryptToPIPE` |
| DecryptToPIPE backup | `/app/share/AppUpgrade/DecryptToPIPE_OG` |
| Engineering Mode QML | `/app/share/AppEngineerMode/` |
| wideopen.service | `/etc/systemd/system/wideopen.service` |
| SSH (dropbear) | `/usr/sbin/dropbearmulti` (symlink → dropbear) |

**Why:** El firmware MASS_PRODUCT bloquea Engineering Mode a nivel de QML. Entender estos bloqueos es esencial para saber qué esperar al conectar el HU.

**How to apply:** Si el usuario menciona intentar acceder a Engineering Mode en un HU stock, recordar que es imposible sin parchear el QML (o tener firmware antiguo/UART/GDS).

Related: [[gen5w-exploit]] · [[re-findings]] · [[project-context]]
