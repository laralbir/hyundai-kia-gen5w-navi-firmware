# Fase 4 — Exploración del rootfs

## Objetivo

Explorar el `mango-rootfs.tar.gz` descifrado para:
- Analizar binarios del sistema (x86-64 Linux)
- Encontrar el mecanismo de descifrado OTA (`DecryptToPIPE`)
- Mapear la arquitectura del sistema de navegación HERE
- Identificar claves hardcodeadas, configuraciones y servicios

## Prerequisitos

- `mango-rootfs.tar.gz` descifrado (de Fase 2)
- Repo `gen5w-docker` clonado (`../setup.sh`)
- Docker instalado
- `binwalk`, `strings`, `file`, `ghidra` (opcionales para RE profundo)

## Opción A — Extracción local (más simple)

```bash
./explore.sh ../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz
```

Extrae el rootfs en `rootfs_extracted/` y muestra el árbol de directorios con tamaños.

## Opción B — Chroot con gen5w-docker

```bash
cd ../gen5w-docker/

# Copiar el rootfs descifrado:
cp ../phase2_decrypt/ota_files/decrypted/mango-rootfs.tar.gz ./

# Entrar en el entorno:
docker compose build
docker compose run mango /chroot.sh    # chroot completo con /mango como raíz
# o
docker compose run mango               # shell sin chroot (para comparar paths)
```

Cambios en `/mango` dentro del contenedor persisten en el host (bind mount).

## Objetivos de RE prioritarios

### 1. DecryptToPIPE — mecanismo de descifrado

```bash
# En el rootfs extraído:
ls rootfs_extracted/app/share/AppUpgrade/
file rootfs_extracted/app/share/AppUpgrade/DecryptToPIPE
strings rootfs_extracted/app/share/AppUpgrade/DecryptToPIPE | grep -E "key|cert|aes|rsa|der|pem|\.bin" -i
```

### 2. Servicios systemd activos

```bash
ls rootfs_extracted/etc/systemd/system/
ls rootfs_extracted/etc/systemd/system/multi-user.target.wants/
cat rootfs_extracted/etc/systemd/system/*.service | grep -E "ExecStart|User|After"
```

### 3. AppNavi — la app de navegación

```bash
file rootfs_extracted/navi/Bin/AppNavi
# Esperado: ELF 64-bit LSB executable, x86-64
strings rootfs_extracted/navi/Bin/AppNavi | grep -i "nds\|here\|haf\|map\|tile" | head -30
```

### 4. Configuración del sistema

```bash
cat rootfs_extracted/etc/version        # versión del SW
cat rootfs_extracted/etc/platform       # nombre de la plataforma (mango)
cat rootfs_extracted/etc/hostname
ls rootfs_extracted/etc/
```

### 5. Claves hardcodeadas

```bash
# Buscar posibles claves AES en binarios
find rootfs_extracted/ -type f -executable | while read f; do
    strings "$f" | grep -E "[0-9a-fA-F]{32,}" | head -3
done 2>/dev/null
```

### 6. Comunicación CAN bus

```bash
find rootfs_extracted/usr/bin/ -type f | xargs file | grep ELF
strings rootfs_extracted/usr/bin/* 2>/dev/null | grep -i "can\|obd\|uds\|kwp" | head -20
```

### 7. Arquitectura del filesystem (confirmación x86-64)

```bash
find rootfs_extracted/ -name "*.so" -o -name "AppNavi" | head -5 | xargs file
# Todos deben mostrar: ELF 64-bit LSB, x86-64
```

## Análisis con Ghidra (RE profundo)

```bash
# Importar DecryptToPIPE en Ghidra:
# Language: x86 / 64-bit / gcc / LE
# Buscar función main(), seguir XRefs a funciones de crypto
# Palabras clave: AES, EVP_*, decrypt, OpenSSL
```

## Mapa de rutas internas del HU

| Ruta | Contenido |
|---|---|
| `/navi/Bin/AppNavi` | App de navegación principal |
| `/navi2/Bin/AppNavi` | Copia de AppNavi (partición secundaria) |
| `/app/share/AppUpgrade/` | Binarios de actualización OTA |
| `/app/share/AppUpgrade/DecryptToPIPE` | Desencriptador OTA |
| `/app/share/AppEngineerMode/` | UI de Engineering Mode (QML) |
| `/etc/systemd/system/` | Servicios del sistema |
| `/usr/sbin/dropbearmulti` | SSH server (dropbear) |
| `/usr/bin/` | Binarios del sistema |
| `/etc/` | Configuración |
