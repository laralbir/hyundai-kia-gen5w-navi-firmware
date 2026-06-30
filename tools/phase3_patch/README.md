# Fase 3 — Parche del rootfs

## Objetivo

Modificar `mango-rootfs.tar.gz` (descifrado) para:
1. Instalar `wideopen.service` — ejecución de scripts USB en cada arranque (persistencia).
2. Desbloquear Engineering Mode — bypass de `checkSOPVersion()` y del PIN QML.
3. Habilitar SSH — symlink `dropbear` activo.

## Prerequisitos

- `update/mango-rootfs.tar.gz` — rootfs descifrado (de la Fase 2)
- Docker instalado
- Repo `update-patcher` clonado (`../setup.sh`)
- Conexión a internet durante el build (descarga `wideopen.service` desde el repo gen5w)

## Preparar

```bash
# Copiar el rootfs descifrado:
cp ../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz update/

# Verificar que es gzip válido:
file update/mango-rootfs.tar.gz
# Debe mostrar: gzip compressed data
```

## Ejecutar el patcher

```bash
./patch.sh
```

O manualmente:

```bash
cd ../update-patcher/
docker compose build
docker compose up
```

El resultado aparece en `update/output/mango-rootfs.tar.gz`.

## Qué modifica el patcher

### 1. Instala wideopen.service

```
/etc/systemd/system/wideopen.service
/etc/systemd/system/multi-user.target.wants/wideopen.service  ← symlink
```

Contenido del servicio: ejecuta `/wideopen_service.sh` desde el USB en cada arranque. Esto permite ejecutar scripts USB sin necesidad del exploit inicial.

### 2. Desbloquea Engineering Mode (QML patches)

Modifica `app/share/AppEngineerMode/AppEngineerMode_PinCodeKeypad.qml`:

| Antes | Después | Efecto |
|---|---|---|
| `enterMenu == 21` | `enterMenu` | Cualquier entrada válida da acceso |
| `enterMenu == 11` | `enterMenu` | Idem para submenú 11 |

Modifica todos los `.qml` del rootfs:

| Antes | Después | Efecto |
|---|---|---|
| `checkSOPVersion() ===` | `checkSOPVersion() !==` | Invierte la lógica de bloqueo |
| `checkSOPVersion()===` | `checkSOPVersion()!==` | Idem (sin espacios) |
| `: AppEngineerModeEngine.checkSOPVersion()` | `: false` | Desactiva la guarda completamente |

**Resultado:** Engineering Mode accesible desde cualquier pantalla del HU sin PIN ni versión de SW específica.

### 3. Habilita SSH (dropbear)

```bash
ln -s ./dropbearmulti ./dropbear    # en /usr/sbin/
```

Tras reiniciar con el rootfs parcheado, `dropbear` estará activo y se puede conectar por SSH al HU.

### 4. Reempaqueta

El rootfs se reempaqueta en formato **ustar** con ownership numérico:
```bash
tar --format=ustar --numeric-owner -czf mango-rootfs.tar.gz ./
```

## Verificar el resultado

```bash
# Verificar que el parche es gzip válido
file update/output/mango-rootfs.tar.gz

# Verificar que wideopen.service está incluido
tar -tzf update/output/mango-rootfs.tar.gz | grep wideopen

# Verificar que el QML fue parcheado
tar -xzf update/output/mango-rootfs.tar.gz -O \
  ./app/share/AppEngineerMode/AppEngineerMode_PinCodeKeypad.qml 2>/dev/null | \
  grep "enterMenu" | head -5
# Debe NO mostrar "== 21" ni "== 11"
```

## Instalar en el HU

### Opción A — Via USB update

El HU tiene un mecanismo de actualización OTA. El archivo parcheado debe colocarse en la estructura de actualización del USB:

```
USB:/
└── HU/
    └── images/
        └── mango-rootfs.tar.gz    ← el archivo parcheado
```

El HU procesará la actualización cuando detecte el USB. **Requiere que `disableEncryptionUpdate` esté activo** (lo activa el wideopen.service en el primer arranque tras el exploit inicial).

### Opción B — Via SSH

Si ya tienes acceso SSH al HU (dropbear activo tras un parche anterior):

```bash
# Conectar por SSH (usuario root, sin contraseña en la mayoría de units)
ssh root@<HU_IP>

# En el HU:
mount -o remount,rw /
# Copiar el nuevo rootfs y reiniciar
```

## Siguiente

Una vez instalado el rootfs parcheado, el HU:
- Ejecutará `wideopen_service.sh` del USB en cada arranque
- Tendrá Engineering Mode accesible sin PIN
- Tendrá SSH activo (dropbear)
- Aceptará futuras actualizaciones sin cifrado

Explorar el rootfs descifrado: `cd ../phase4_explore/`
