# Firmware MKBD (frontkey) — Análisis con Ghidra + RL78

Fecha de análisis: 2026-07-10.

---

## Corrección de arquitectura: no es ARM Cortex-M, es Renesas RL78

Los hallazgos anteriores (basados solo en los primeros bytes `d8 00 ff ff ff ff...`) asumían ARM Cortex-M little-endian. Un análisis más profundo con desensamblado real **refuta esta hipótesis** y confirma **Renesas RL78** (familia de MCU de 16 bits muy común en electrónica automotriz coreana/japonesa para paneles de switches/botones):

- La tabla de vectores RL78 usa entradas de **2 bytes** (no 4), en offsets `0x0000`–`0x007E`. Interpretando el binario como palabras de 16 bits LE:
  - `0x0000`: `0x00D8` → vector de Reset (dirección pequeña y plausible, no `0xFFFFFFFF` como exigiría un vector Cortex-M en ese offset).
  - `0x0010`, `0x0012`, `0x0028`, `0x002E`, ... hasta `0x0058`: ~14 vectores de interrupción, todos apuntando al rango `0x0800–0x0990` (bloque de manejadores de interrupción agrupados).
  - Resto de la tabla: `0xFFFF` (vector no usado, flash sin programar).
- **Option bytes** en `0x00C2–0x00C3` (`e8 84`) y **Security ID** en `0x00C4–0x00CE` (11 bytes, todos `0x00` = valor por defecto/sin proteger) — coinciden exactamente con el layout estándar RL78.
- El **Reset handler** arranca exactamente en `0x00D8` (coincide con el vector de Reset leído), confirmando la interpretación.

Este hallazgo corrige `docs/estructura_ficheros.md` (sección MKBD) y `.claude/memory/re_findings.md`, que asumían Cortex-M.

## El binario no está cifrado

Confirmado de forma definitiva: el desensamblado a partir del vector de Reset produce código RL78 limpio, coherente y semánticamente sensato (funciones cortas con prólogo/epílogo estándar `PUSH`/`POP`, llamadas `CALL !!`, sin ruido). Esto valida la hipótesis previa ("accesible sin descifrar") pero por una razón distinta: no es que el magic byte no coincidiera con un formato cifrado conocido, es que el desensamblado real tiene sentido.

## Setup de Ghidra para RL78

Ghidra no incluye RL78 de fábrica. Proceso usado:

```bash
brew install ghidra   # 12.1.2, vía Homebrew formula (no cask)

# Módulo de procesador RL78 de terceros (xyzz/ghidra-rl78, release v1)
curl -sL -o rl78.zip https://github.com/xyzz/ghidra-rl78/releases/download/v1/rl78.zip
unzip rl78.zip
cp -R rl78 "$GHIDRA_HOME/Ghidra/Processors/rl78"
"$GHIDRA_HOME/support/sleigh" -a "$GHIDRA_HOME/Ghidra/Processors/rl78/data/languages/"

# Importar como Raw Binary, procesador RL78:LE:16:default, base 0x0
"$GHIDRA_HOME/support/analyzeHeadless" <project_dir> <project_name> \
  -import MKBD_2_1f_00_NX4.bin \
  -processor RL78:LE:16:default -loader BinaryLoader -loader-baseAddr 0x0
```

Notas prácticas:
- La extensión de terceros solo trae `.slaspec`/`.pspec`/`.cspec`/`.ldefs` (sin `.sla` precompilado) — hay que compilarla con `support/sleigh -a`.
- Ghidra 12.x no trae Jython embebido por defecto; los scripts `-postScript` deben ser **Java** (`GhidraScript` compilado on-the-fly por el headless analyzer), no `.py` clásicos.
- La API antigua `AddressFactory.getAddress(long)` no existe en esta versión; usar `af.getDefaultAddressSpace().getAddress(long)`.

## Layout del binario: dos regiones de 192 KB con banco de flash separado

El fichero (196.608 bytes = 192 KiB) no es un único blob de código. Un escaneo de entropía por bloques de 1 KB muestra:
- Código real (entropía ~5.3–6.6 bits/byte) desde `0x0000` hasta `~0xD66D`.
- Relleno `0xFF` (flash sin programar) desde `~0xD800` hasta `0x18000`.
- Una **segunda tabla de punteros idéntica en estructura** en `0x2DBD0` (offset +0x22000 respecto a la primera en `0xBBD0`), con el mismo patrón de entropía.

La comparación byte a byte de las dos regiones de código muestra que **no son copias idénticas** (69.8% de bytes distintos) — no es redundancia A/B trivial; podría ser dos secciones de código relacionadas con distintos sub-sistemas o un artefacto del layout del compilador. No se ha investigado en profundidad; queda como trabajo futuro.

## Lógica identificada: validación de matriz de botones

### Tabla de despacho

En `0xBBD0` hay una tabla de **16 punteros a función** (4 bytes cada uno, direcciones de 32 bits aunque el procesador es de 16 bits — probablemente el ABI genera punteros extendidos), apuntando a `0xC096, 0xC0BF, 0xC0E9, 0xC113, 0xC13D, 0xC16B, 0xC195, 0xC1ED, 0xC217, 0xC241, 0xC26B, 0xC295, 0xC31B, 0xC3D6, 0xC443, 0xC4B1`.

### Patrón común (decompilado)

Las 16 funciones comparten estructura idéntica:

```c
undefined2 FUN_0000c096(void)
{
  FUN_00008a7f();  // enter critical section (DI + contador de anidamiento)
  if (((DAT_000ff6b8 & 0xc) != 0) && (DAT_000ff5e0 >> 4 != *_DAT_000ff680 >> 4)) {
    DAT_000ff6b9 = DAT_000ff6b9 | 1;   // marca discrepancia en el bit correspondiente
  }
  FUN_00008aa3();  // leave critical section (EI si contador llega a 0)
  return 1;
}
```

Interpretación:
- `!0xFF680` es un **buffer de 8 bytes** (offsets `+0` a `+7` usados across las 16 funciones) — muy probablemente el resultado crudo de un barrido (scan) de la matriz de botones/switches físicos, leído de un ADC o expansor de E/S.
- Cada función extrae un **sub-campo de bits** (vía `SHR`/`SHL`/`AND`) de un byte concreto del buffer — anchuras de 2, 3, 4 o 6 bits según el botón, consistente con una red resistiva compartida donde varios botones producen códigos de tensión distintos en un mismo canal ADC.
- Compara ese sub-campo contra un **valor de referencia/calibración** almacenado en una dirección RAM fija distinta por función (`!0xFF5E0`, `!0xFF5E7`, `!0xFF613`, `!0xFF614`, `!0xFF617`, `!0xFF61B`, `!0xFF61C`, `!0xFF61E`, `!0xFF61F`, `!0xFF623`, `!0xFF627`, `!0xFF629`, `!0xFF62A`, `!0xFF645`, `!0xFF647`, `!0xFF649`, `!0xFF652`, `!0xFF657`, `!0xFF663`–`!0xFF667`, `!0xFF66F`, `!0xFF672`, `!0xFF679`).
- Si no coincide, marca el bit correspondiente en un **bitmap de discrepancias** de 5 bytes (`!0xFF6B9`–`!0xFF6BD`, ≈40 bits) — algunas funciones marcan varios bits (hasta 6 sub-campos por función), así que el número real de elementos vigilados es mayor a 16.
- Todo el bloque de comparación solo se ejecuta si `!0xFF6B8 & 0xC != 0` (un flag de "modo activo"/habilitación).

Esto es consistente con una **rutina de auto-test/validación de la matriz de botones**: en cada ciclo de escaneo compara la lectura eléctrica real contra los valores esperados calibrados para el panel físico instalado, marcando fallos (botón atascado, cortocircuito, cableado incorrecto, panel no reconocido).

### Funciones auxiliares (sección crítica)

```c
void FUN_00008a7f(void) {  // "enter critical section"
  if (_DAT_000ff70c == 0) { DAT_000ff70a = FUN_00008ac1(); }  // guarda PSW (flag IE)
  _DAT_000ff70c = _DAT_000ff70c + 1;                          // contador de anidamiento
}
void FUN_00008aa3(void) {  // "leave critical section"
  _DAT_000ff70c = _DAT_000ff70c + -1;
  if (_DAT_000ff70c == 0) { FUN_00008ac6(DAT_000ff70a); }     // restaura PSW
}
```

Patrón clásico de wrapper `DI()`/`EI()` con contador de anidamiento reentrante — típico de BSP/HAL generado (Renesas Applilet o similar), aunque compilado sin símbolos de depuración.

## NX4 vs US4: no es solo una tabla de calibración distinta

Comparación directa de los dos binarios (mismo tamaño, 196.608 bytes):
- **39.8%** de todos los bytes del fichero difieren.
- **~92%** de los bytes difieren *dentro* de la región de código analizada (`0x8A7F`–`0xC4BA`, las funciones de validación + helpers).
- El auto-análisis de Ghidra reconoce solo 4 funciones "de forma automática" en NX4 (sin seed manual) frente a **30 funciones** en US4 — el layout de código y las direcciones absolutas embebidas en las instrucciones difieren sustancialmente entre variantes.

**Conclusión:** NX4 (no-HEV) y US4 (HEV) no comparten un único binario con una tabla de datos de calibración intercambiable — son compilaciones genuinamente distintas, coherente con paneles físicos con botones/funciones diferentes entre variantes (el HEV probablemente añade controles específicos del sistema híbrido). Esto no descarta que dentro de cada variante las direcciones de calibración (`!0xFF5E0` etc.) sean patcheables, pero sí descarta la hipótesis simple de "mismo firmware + tabla de constantes distinta".

## Búsqueda del protocolo de comunicación con el SoC principal

Para llegar más allá del código alcanzable desde el reset handler y las 16 funciones de validación, se sembró la disassembly y decompilación en **todos** los vectores de interrupción de la tabla (`0x0000-0x007E`), no solo el de Reset. Esto reveló ~48 funciones en total (frente a las 20 analizadas antes), incluyendo dos con un patrón muy específico:

```c
void FUN_000011fe(undefined2 param_1,undefined2 param_2)
{
  DAT_000f0800 = 0;
  DAT_000f0803 = 0;
  _DAT_000f0806 = 0x400;        // tamaño de buffer/bloque: 1024 bytes
  cVar2 = func_0x000efff8();    // llamada a rutina fuera del rango del .bin (ROM interna del chip)
  while (...) {
    param_2 = CONCAT11(DAT_000f0891, cVar1);
    if ((DAT_000f0891 & 1) != 1) break;   // bit de "listo"/"ocupado"
    cVar2 = func_0x000f08c4();            // reintento
  }
  ...
}
```

```c
char FUN_00001252(undefined2 param_1) {
  ...
  cVar4 = func_0x000efff8();
  while (cVar1 = uVar2, cVar4 == -1) {
    uVar2 = CONCAT11(DAT_000f0891,cVar1);
    if ((DAT_000f0891 & 1) != 1) {
      if (cVar1 != 3) { DAT_000f0890 |= 0x10; return -1; }  // flag de error/timeout
      DAT_000f0890 |= 0x90; return -1;                      // flag de error distinto
    }
    cVar4 = func_0x000f08c4();
  }
  return cVar4;
}
```

**Interpretación:** las direcciones `0xF0800-0xF08C4` y `0xEFFF8` caen fuera del rango cubierto por el `.bin` (`0x0000-0x2FFFF`), por lo que apuntan a **ROM interna del propio chip, no a flash de usuario**. El patrón (bucle de reintento sobre un bit de estado, tamaño de bloque fijo de 1024 bytes, flags de error distintos por causa) es muy característico de la **Flash Self-Programming Library (FSL)** de Renesas RL78 — la librería en máscara ROM que el fabricante provee para que el propio MCU pueda borrar/escribir/verificar su flash en bloques.

**Implicación directa:** el MKBD probablemente soporta re-flasheo en campo de su propio firmware (coherente con que exista un proceso de actualización OTA que incluye estos `.bin` en el paquete). Esto es la pieza que faltaba para saber "¿se puede flashear un firmware modificado a este chip?" — la respuesta parece ser sí a nivel de mecanismo (el propio chip tiene la capacidad), pero **no se ha localizado aún el código que recibe los bytes desde el exterior** (el canal por el que llegan los datos a escribir) ni el candado de autenticación/checksum antes de aceptar una imagen nueva, si existe.

No se encontraron accesos directos a las direcciones típicas del periférico SAU (Serial Array Unit, `0xF0100-0xF014F` en la mayoría de variantes RL78) que implementaría UART/CSI por hardware, en el código alcanzado hasta ahora (48 funciones de un total estimado de varios cientos en ~54 KB de código real por región). Esto no descarta que exista — solo que el análisis por flujo de control desde vectores de interrupción no lo ha alcanzado todavía; sería necesario un barrido lineal exhaustivo del resto del binario.

## Implicaciones para "cambiar el panel de botones"

| Pregunta | Estado |
|---|---|
| ¿El firmware es legible/analizable? | ✅ Sí — RL78, sin cifrar, desensamblado limpio con Ghidra |
| ¿Se entiende la lógica de lectura de botones? | ✅ Parcialmente — comparación de un buffer de 8 bytes (scan crudo) contra tablas de calibración por botón, con detección de discrepancias |
| ¿Se conoce el protocolo de comunicación con el SoC principal? | ❌ No — no se ha localizado aún el código que envía el resultado del escaneo (UART/LIN/SPI). Próximo paso de RE. |
| ¿Se sabe dónde viven las tablas de calibración en flash (antes de copiarse a RAM)? | ❌ No — las direcciones identificadas (`!0xFF5E0`...) son RAM; falta localizar el origen en flash y el código de inicialización que las carga. |
| ¿Se puede simplemente reutilizar NX4↔US4 intercambiando datos? | ❌ No — difieren en ~92% del código analizado, no es un simple cambio de tabla. |
| ¿Existe ya precedente de paneles intercambiables por variante? | ✅ Sí — el propio fabricante ya distingue NX4/US4 con firmwares distintos, lo que confirma que el hardware SÍ soporta variantes de panel, pero mediante binarios completos distintos, no mediante un parámetro. |

**Siguiente paso recomendado:** localizar en el resto del binario (fuera del rango ya analizado, ~54 KB de código por región) el código de comunicación serie con el SoC principal — buscar patrones de acceso a SFR de UART/CSI de RL78 y strings/constantes de protocolo. Esto es indispensable para saber si un panel "no oficial" sería aceptado por el SoC principal o si hay verificación adicional a ese nivel (fuera del propio MCU MKBD).

## Related

- `.claude/memory/re_findings.md` — corregido: MCU frontkey ahora identificado como RL78, no ARM Cortex-M.
- `docs/estructura_ficheros.md` — sección MKBD actualizada con la corrección de arquitectura.
- `docs/gen5w_exploit_ecosystem.md` — vía de descifrado del rootfs, relevante para investigar el lado del SoC principal del protocolo de comunicación con el MKBD.
