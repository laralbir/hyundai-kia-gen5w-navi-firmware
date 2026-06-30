# Fase 2 — Descifrado de archivos OTA

## Objetivo

Usar `DecryptToPIPE` y `decryption_key.der` (extraídos del HU físico en Fase 1) para descifrar todos los archivos OTA del paquete en el PC.

## Prerequisitos

- `keys/DecryptToPIPE` — binario original del HU
- `keys/decryption_key.der` — clave de descifrado del HU
- Docker instalado
- Repo `update_decryptor` clonado (`../setup.sh`)
- Archivos OTA cifrados en `ota_files/`

## Estructura de directorios

```
phase2_decrypt/
├── keys/
│   ├── DecryptToPIPE        ← del HU (copiar desde USB)
│   └── decryption_key.der   ← del HU (copiar desde USB)
├── ota_files/               ← archivos OTA a descifrar
│   ├── mango-rootfs.tar.gz
│   ├── update.tar.gz
│   ├── new_gui.tar.gz
│   ├── appnavi.tar
│   ├── iasImage*
│   └── decrypted/           ← resultado (se crea automáticamente)
└── decrypt.sh               ← script wrapper
```

## Preparar los archivos

```bash
# 1. Copiar claves del USB al PC
cp /Volumes/USB/DecryptToPIPE     keys/
cp /Volumes/USB/decryption_key.der keys/

# 2. Copiar archivos OTA a descifrar
OTA_SRC="/path/to/Rio_MY22_EU/HU"
cp "$OTA_SRC/images/mango-rootfs.tar.gz"           ota_files/
cp "$OTA_SRC/firmware/update.tar.gz"               ota_files/
cp "$OTA_SRC/images/new_gui.tar.gz"                ota_files/
cp "$OTA_SRC/images/navi_eu/appnavi.tar"           ota_files/
cp "$OTA_SRC/images/iasImage"                      ota_files/
cp "$OTA_SRC/images/iasImage_sub"                  ota_files/
cp "$OTA_SRC/images/iasImage_1280"                 ota_files/
# etc.
```

## Ejecutar el descifrado

```bash
./decrypt.sh
```

O manualmente:

```bash
# Construir imagen (solo primera vez)
cd ../update_decryptor/
docker build -t gen5wdecryptor ./

# Ejecutar contra los archivos OTA
cd ../phase2_decrypt/
docker run --rm -it \
  -v "$PWD/keys/DecryptToPIPE:/DecryptToPIPE" \
  -v "$PWD/keys/decryption_key.der:/decryption_key.der" \
  -v "$PWD/ota_files:/mnt" \
  gen5wdecryptor
```

**Nota:** El Dockerfile del update_decryptor usa `--platform=${PLATFORM:-linux/amd64}` — la plataforma objetivo del HU es x86-64.

## Verificar resultados

```bash
ls ota_files/decrypted/

# Verificar magic bytes de cada archivo descifrado:
for f in ota_files/decrypted/*; do
    echo -n "$f: "
    xxd "$f" | head -1
done

# mango-rootfs.tar.gz debe mostrar: 1f 8b (gzip)
# appnavi.tar debe mostrar: 75 73 74 61 72 (ustar a offset 257)
# iasImage: formato IAS o U-Boot (27 05 19 56)
```

## Tamaños esperados tras descifrado

Los archivos descifrados deben tener tamaño similar a los cifrados (el cifrado AES es 1:1 en tamaño, con posible padding mínimo).

| Archivo | Tamaño cifrado | Magic esperado |
|---|---|---|
| `mango-rootfs.tar.gz` | 838.4 MB | `1f 8b` (gzip) |
| `update.tar.gz` | 40.2 MB | `1f 8b` (gzip) |
| `new_gui.tar.gz` | 1.99 GB | `1f 8b` (gzip) |
| `appnavi.tar` | 487 MB | ustar @257 |
| `iasImage` | ~6.1 MB | TBD (IAS/U-Boot) |

## Siguiente fase

Una vez descifrado el rootfs:

```bash
# Ir a patch del rootfs (añade wideopen.service + Engineering Mode bypass):
cp ota_files/decrypted/mango-rootfs.tar.gz ../phase3_patch/update/
cd ../phase3_patch/
```

O si solo quieres explorar sin modificar:

```bash
cd ../phase4_explore/
./explore.sh ota_files/decrypted/mango-rootfs.tar.gz
```
