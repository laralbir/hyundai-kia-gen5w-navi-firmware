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

⚠️ **Nombres de flag corregidos (2026-07-11)** — verificados leyendo `extract_keys.sh` directamente; no coinciden con los que documentaba una versión anterior de este README:

```
USB:/
├── *_key_*.der                              ← ✅ LA CLAVE — el nombre exacto lo decide el binario
│                                                DecryptToPIPE_FK (opaco, no tenemos su fuente);
│                                                extract_keys.sh solo busca el patrón comodín
│                                                "*_key_*.der", no un nombre literal.
├── loop_output.txt                          ← log de ejecución (vía main_loop.sh)
├── DecryptToPIPE_OG                         ← backup del binario original del HU (¡no perder!)
└── STATUS_FLAGS/
    ├── EXTRACT_KEYS_STAGE_1_FLAG            ← ✅ fase 1 completada (spoofing de DecryptToPIPE hecho)
    ├── EXTRACT_KEYS_STAGE_2_FLAG            ← ✅ fase 2 completada (clave encontrada + restaurado)
    └── DONE_RESTORING_DECRYPT_OG_FLAG       ← ✅ DecryptToPIPE original restaurado en el HU
```

**Si `EXTRACT_KEYS_STAGE_2_FLAG` no aparece pero `EXTRACT_KEYS_STAGE_1_FLAG` sí:**
El reinicio ocurrió pero `DecryptToPIPE_FK` no produjo ningún fichero `*_key_*.der` en el USB. Posibles causas:
- La variante `_FK` no es compatible con este hardware — probar `DecryptToPIPE_RC` en lugar de `_FK` (renombrar a `DecryptToPIPE_FK` en el USB, o adaptar `extract_keys.sh`).
- El USB se desconectó o se remontó en modo distinto entre reinicios.
- Ver `loop_output.txt` para el log completo de cada iteración del bucle.

**Bug corregido (2026-07-11):** el `main_loop_code.sh` que trae el repo upstream `navi_extended` es una plantilla vacía — nunca invoca `extract_keys.sh`. `prepare_usb.sh` ahora escribe una versión corregida directamente al preparar el USB (ver comentario en el script) — si preparaste el USB con una versión de `prepare_usb.sh` anterior a esta fecha, vuelve a ejecutarlo antes de conectar el USB al HU.

## Después de extraer las claves

```bash
# Copiar al PC:
cp /Volumes/USB/decryption_key.der  ../phase2_decrypt/keys/
cp /Volumes/USB/DecryptToPIPE       ../phase2_decrypt/keys/   # el original del HU

# Ir a la siguiente fase:
cd ../phase2_decrypt/
```

## ⚠️ El verdadero bloqueante: el punto de entrada inicial (actualizado 2026-07-11)

> ¿Cómo llega `navi_extended` al HU por primera vez, si el HU está en estado stock?

Esto — no la mecánica de extracción de claves en sí, que ya está lista — es el paso genuinamente incierto de todo el plan. Ver [docs/engineering_mode.md](../../docs/engineering_mode.md) para el análisis completo del bloqueo.

**El mecanismo real** (según el propio README de `navi_extended` upstream): instalar la app requiere entrar en **Engineering Mode → Dynamics → Navigation → Config → "Update AppNavi from USB"**. No es un backdoor genérico de "ejecutar cualquier script" — es una opción de menú legítima de actualización que solo aparece dentro de Engineering Mode.

**El problema:** nuestro firmware (`MASS_PRODUCT YB_22.EUR.S5W_L.001.001.251204`) bloquea Engineering Mode con un check `checkSOPVersion()` que **siempre devuelve falso en builds de producción** — el teclado PIN puede aparecer, pero introducir el PIN correcto (`21`) no sirve de nada mientras esa comprobación no esté parcheada. Y parchearla requiere el rootfs descifrado... que requiere las claves... que requieren Engineering Mode. Es circular.

**Tres rutas para romper el círculo, ninguna confirmada todavía:**

| Ruta | Estado | Coste/riesgo |
|---|---|---|
| **Downgrade a firmware pre-noviembre-2021** (sin el check SOP) vía `update_fetcher` | ⚠️ Probado hoy: la herramienta compila y ejecuta, pero `list --region Eu` no devolvió ningún modelo (la llamada a la API de Hyundai/Kia no dio resultado con las cabeceras que envía esta versión del cliente — no se investigó más a fondo por qué, ver nota abajo) | Bajo si funciona — solo software, reversible |
| **UART en la PCB del HU** (puerto serie de depuración, 115200 baudios) | Sin explorar — no se ha abierto físicamente ningún HU todavía | Medio-alto — requiere desmontar el HU, localizar los pines, y no hay garantía de que dé una shell root |
| **GDS/herramienta de concesionario** | Sin acceso — herramienta con licencia oficial Hyundai/Kia, no disponible para un particular | Alto — normalmente inaccesible fuera de un taller autorizado |

**Nota sobre `update_fetcher`:** un intento directo (`curl`) de replicar la llamada a la API para diagnosticar por qué no devolvió modelos fue bloqueado por el propio harness de este asistente (correctamente, por tratarse de sondear un servidor de terceros no autorizado explícitamente) — así que el estado de esta vía queda **sin diagnosticar del todo**, ni confirmada ni descartada. Si se quiere seguir esta vía, el siguiente paso es ejecutar `update_fetcher` manualmente (fuera de este asistente) y revisar con más detalle por qué la API no devuelve modelos — puede ser tan simple como que el endpoint cambió desde que se escribió la herramienta.

**Recomendación práctica:** antes de plantearse UART o GDS (ambos de alto coste), vale la pena primero intentar simplemente los métodos A/B de acceso al PIN (ver `docs/engineering_mode.md`) en el HU real — es gratis probarlo y **el bloqueo SOP es una hipótesis basada en análisis de QML, no una prueba física todavía confirmada contra este HU en concreto**. Si el PIN sí funciona pese a todo (firmware con alguna variación no documentada, versión de excepción, etc.), todo lo demás de este plan se ejecuta sin más obstáculos.
