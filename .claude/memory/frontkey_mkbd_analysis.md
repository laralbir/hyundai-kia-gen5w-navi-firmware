---
name: frontkey-mkbd-analysis
description: "Desensamblado del firmware MKBD (frontkey) con Ghidra: arquitectura real RL78, lógica de validación de matriz de botones, comparación NX4 vs US4"
metadata:
  node_type: memory
  type: project
  originSessionId: 592b9447-f2a9-4afd-b492-f4fa0f41c6bb
---

## Corrección de arquitectura

El firmware MKBD (frontkey, panel de botones) **no es ARM Cortex-M** como se asumió en sesiones anteriores basándose solo en los primeros bytes. Desensamblado real con Ghidra 12.1.2 + módulo de procesador RL78 de terceros (`xyzz/ghidra-rl78`, instalado manualmente en `Ghidra/Processors/`) confirma **Renesas RL78**:
- Tabla de vectores de 16 bits en `0x0000-0x007E`, reset vector = `0x00D8`.
- Option bytes en `0xC2-C3`, Security ID en `0xC4-CE` (todo ceros, sin proteger).
- El binario **no está cifrado** — desensamblado limpio, funciones coherentes con prólogo/epílogo estándar.

## Setup de Ghidra para RL78 (reutilizable)

```bash
brew install ghidra   # formula, no cask — 12.1.2
curl -sL -o rl78.zip https://github.com/xyzz/ghidra-rl78/releases/download/v1/rl78.zip
unzip rl78.zip && cp -R rl78 "$GHIDRA_HOME/Ghidra/Processors/rl78"
"$GHIDRA_HOME/support/sleigh" -a "$GHIDRA_HOME/Ghidra/Processors/rl78/data/languages/"
# Importar: -processor RL78:LE:16:default -loader BinaryLoader -loader-baseAddr 0x0
```

Ghidra 12.x no trae Jython — los `-postScript` deben ser `.java` (GhidraScript compilado on-the-fly), no `.py`.

## Lógica decompilada

Tabla de 16 punteros a función en `0xBBD0`. Cada función: entra en sección crítica (DI/EI con contador de anidamiento, `0x8A7F`/`0x8AA3`), extrae un sub-campo de bits de un buffer de 8 bytes en RAM `!0xFF680` (lectura cruda de la matriz de botones), lo compara contra un valor de calibración en una dirección RAM fija (`!0xFF5E0`, `!0xFF613`... una por botón), y marca discrepancias en un bitmap de ~40 bits (`!0xFF6B9-0xFF6BD`). Es una rutina de auto-test/validación del panel físico contra un patrón esperado.

## NX4 vs US4 — no intercambiables por datos

39.8% de bytes distintos en todo el fichero, ~92% dentro de la región de código analizada. **No son el mismo firmware con una tabla de calibración distinta** — son compilaciones genuinamente distintas (probablemente por diferencias reales de botones/funciones entre variante no-HEV y HEV).

## Posible auto-programación de flash (Flash Self-Programming Library)

Sembrando disassembly/decompilación en todos los vectores de interrupción (no solo Reset) aparecen ~48 funciones. Dos de ellas (`FUN_000011fe`, `FUN_00001252`) llaman a direcciones `0xF08C4`/`0xEFFF8` (fuera del rango del `.bin`, es decir ROM interna del chip) con patrón de reintento sobre un bit de estado y un tamaño de bloque fijo de 1024 bytes — muy característico de la Flash Self-Programming Library de Renesas RL78. Indica que el chip probablemente soporta reflasheo en campo de su propio firmware. No se ha localizado el canal por el que llegan los bytes a escribir ni ninguna verificación de autenticidad. No se encontraron accesos al periférico SAU típico (UART/CSI hardware, `0xF0100-0xF014F`) en el código alcanzado hasta ahora.

## Pendiente

- Localizar el protocolo de comunicación serie (UART/LIN/SPI) entre el MKBD y el SoC principal — necesario para saber si el SoC valida el panel más allá del propio MCU.
- Localizar el origen en flash de las tablas de calibración (las direcciones identificadas son RAM, cargadas en el arranque desde algún punto no identificado aún).

Documentación completa con listados de desensamblado y decompilación: [`docs/frontkey_mkbd_analysis.md`](../../docs/frontkey_mkbd_analysis.md).

Related: [[re-findings]] · [[gen5w-exploit]]
