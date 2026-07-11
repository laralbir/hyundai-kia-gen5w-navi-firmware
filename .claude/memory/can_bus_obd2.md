# CAN bus / OBD2 — vía de investigación

## Hallazgo central

El HU no es la puerta al bus de diagnóstico. Los Hyundai/Kia con Central Gateway (CGW) llevan un Security Gateway (SGW): servicios UDS privilegiados (coding `0x2E`, actuator test/RoutineControl `0x31`, IO control `0x2F`) exigen certificado digital emitido por Hyundai/Kia; sin él, NRC `0x33 securityAccessDenied`. Sin bypass público conocido del SGW/CGW en sí.

## Precedente directo con CVE real: KOFFEE / CVE-2020-8539

IIT-CNR (Italia) reverseó un head unit Kia hermano (Kia Ceed, Android Gen 5.0 "iAVN" — generación distinta a nuestro Standard Gen5W/mango/S5W_L) y encontró que cualquier app podía ejecutar `Runtime.exec("micomd -c inject " + msg)` para inyectar tramas CAN reales en el **M-CAN** del vehículo. CVE-2020-8539 = permisos inseguros en `micomd`. Escalado a ataque remoto (sideload de APK maliciosa sin verificación) con módulo público de Metasploit (`post/android/local/koffee`). Kia lo corrigió en 04/2020.

Topología real de bus confirmada por esta fuente primaria: **P-CAN(motor) · B-CAN(carrocería) · C-CAN(chasis) · I-CAN · M-CAN(multimedia)**, todos tras el CGW. El HU vive en M-CAN junto a amplificador, cuadro de instrumentos (IC) y E-CALL. Impacto demostrado: cámara trasera, idioma/info en cuadro, on/off HU, mute — nunca motor/frenos/DTC (aislados en P-CAN/C-CAN).

## Aplicabilidad e implicación para este proyecto

El CVE exacto no aplica a nuestro firmware (otra generación, ya parcheado), pero prueba que el patrón "app del HU → daemon tipo micomd → CAN real" existe de verdad en el ecosistema Hyundai/Kia/Genesis, probablemente compartido entre generaciones (mismo Tier 1). Con el root que ya da `navi_extended`/`wideopen_service` — más privilegio que la app sandboxed de KOFFEE — si el rootfs mango/S5W tiene un mecanismo equivalente, sería invocable directamente sin exploit adicional.

**Objetivo de grep concreto para cuando el rootfs esté descifrado:** `micomd`, `-c inject`, `sendMicomMsg`, `automotivefw`, `libHVehicle`, `@micom_mux`.

## Vías evaluadas

- **A — OBD2 estándar al DLC** (sin exploit): DTCs genéricos Modo 03/04 sí funcionan siempre (regulación de emisiones, no pasa por SGW). Coding/calibración/actuator tests no, salvo herramienta con licencia SGW oficial (HiCOM, GDS).
- **B — HU rooteado** (ya disponible en el proyecto): permite el grep de arriba y, si hay mecanismo equivalente a micomd, invocarlo directamente. Techo real: solo M-CAN (HU/ampli/cuadro/E-CALL), nunca motor/frenos/DTC.
- **C — Bypass del SGW/CGW en sí**: sin exploit público conocido, proyecto de investigación aparte, aparcado.

Documentado en detalle en `docs/can_bus_obd2_investigation.md` (incluye diagrama de bus, timeline de responsible disclosure de KOFFEE, y plan de acción priorizado por coste/beneficio).
