# Fase 1 — Exploit USB (extracción de claves)

## Objetivo

Ejecutar código arbitrario en el HU via USB para extraer `DecryptToPIPE` y `decryption_key.der`, los dos archivos necesarios para descifrar todos los archivos OTA en el PC.

## Prerequisitos

- USB formateado en **exFAT** (≥ 32 GB recomendado)
- Repos gen5w clonados (`../setup.sh`)
- HU encendido con la pantalla de navegación visible (vehículo en posición ACC/ON)
- HU en estado sin parchear (o ya parcheado con wideopen instalado — en ese caso ir directo a [Fase 2](../phase2_decrypt/README.md))

## Mecanismo del exploit

`navi_extended` es una aplicación C# que reemplaza el binario de AppNavi en el HU. Cuando AppNavi arranca, en su lugar se ejecuta navi_extended, que busca en todos los USB conectados un archivo `main_loop.sh` en la raíz y lo ejecuta en un bucle.

El flujo de ejecución en el HU:

```
AppNavi (reemplazado por navi_extended)
    └── main_loop.sh (bucle cada 10 seg)
            └── main_loop_code.sh (dispatcher)
                    └── INITIAL_SETUP_SCRIPTS/extract_keys.sh (si no hay STAGE2_DONE)
```

## Flujo de extracción de claves (extract_keys.sh)

El script opera en **dos fases separadas por un reinicio**:

### Fase 1A
1. Verifica que `STATUS_FLAGS/STAGE1_DONE` NO existe.
2. Remonta el rootfs del HU en modo read-write: `mount -o remount,rw /`.
3. Crea backup: `/app/share/AppUpgrade/DecryptToPIPE` → `DecryptToPIPE_OG`.
4. Copia `DecryptToPIPE_FK` del USB → `/app/share/AppUpgrade/DecryptToPIPE`.
5. Crea `STATUS_FLAGS/STAGE1_DONE`.
6. Reinicia el HU (`reboot`).

### (HU reinicia — DecryptToPIPE_FK se ejecuta durante el arranque)

`DecryptToPIPE_FK` es una versión modificada del binario original que, en lugar de solo descifrar, también vuelca la clave (`decryption_key.der`) en el USB.

### Fase 1B (post-reinicio)
1. Verifica que `STATUS_FLAGS/STAGE1_DONE` existe.
2. Verifica que `decryption_key.der` existe en el USB.
3. Restaura el original: `DecryptToPIPE_OG` → `DecryptToPIPE`.
4. Crea `STATUS_FLAGS/STAGE2_DONE`.
5. Reinicia el HU.

## Preparar el USB

```bash
# Montar el USB y ejecutar:
./prepare_usb.sh /Volumes/USB        # macOS
./prepare_usb.sh /mnt/usb            # Linux
```

El script copia todos los archivos necesarios desde el repo navi_extended clonado.

## Ejecutar en el HU

1. Insertar USB en el puerto de datos del HU.
2. **No desconectar el USB** durante todo el proceso.
3. Esperar aproximadamente **10-15 minutos** y 3 ciclos de reinicio.
4. Cuando la pantalla de navegación vuelva a arrancar normalmente, verificar el USB.

## Verificar éxito

En la raíz del USB deben aparecer:

```
USB:/
├── decryption_key.der       ← ✅ LA CLAVE (guardar en lugar seguro)
├── loop_output.txt          ← log de ejecución
└── STATUS_FLAGS/
    ├── STAGE1_DONE          ← ✅ fase 1A completada
    └── STAGE2_DONE          ← ✅ proceso completo
```

**Si `STAGE2_DONE` no aparece pero `STAGE1_DONE` sí:**
El reinicio ocurrió pero `DecryptToPIPE_FK` no produjo la clave. Posibles causas:
- La variante `_FK` no es compatible con este hardware — probar `DecryptToPIPE_RC` en lugar de `_FK`.
- Ver `loop_output.txt` para detalles del error.

## Después de extraer las claves

```bash
# Copiar al PC:
cp /Volumes/USB/decryption_key.der  ../phase2_decrypt/keys/
cp /Volumes/USB/DecryptToPIPE       ../phase2_decrypt/keys/   # el original del HU

# Ir a la siguiente fase:
cd ../phase2_decrypt/
```

## Nota sobre el punto de entrada inicial

> ¿Cómo llega navi_extended al HU por primera vez?

Ver [docs/engineering_mode.md](../../docs/engineering_mode.md) para el análisis completo. En resumen:
- En versiones antiguas del firmware, AppNavi ejecutaba scripts USB por defecto.
- En versiones actuales, se necesita acceso a Engineering Mode o una ruta alternativa (UART/JTAG).
- Una vez instalado el parche (wideopen.service), el HU siempre ejecutará scripts USB en el arranque.
