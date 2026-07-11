# CAN bus / OBD2 — vía de investigación

## Hallazgo central

El HU no es la puerta al bus de diagnóstico. Los Hyundai/Kia con Central Gateway (CGW) llevan un Security Gateway (SGW): servicios UDS privilegiados (coding `0x2E`, actuator test/RoutineControl `0x31`, IO control `0x2F`) exigen certificado digital emitido por Hyundai/Kia; sin él, NRC `0x33 securityAccessDenied`. Sin bypass público conocido del SGW/CGW en sí.

## Precedente directo con CVE real: KOFFEE / CVE-2020-8539

IIT-CNR (Italia) reverseó un head unit Kia hermano (Kia Ceed, Android Gen 5.0 "iAVN" — generación distinta a nuestro Standard Gen5W/mango/S5W_L) y encontró que cualquier app podía ejecutar `Runtime.exec("micomd -c inject " + msg)` para inyectar tramas CAN reales en el **M-CAN** del vehículo. CVE-2020-8539 = permisos inseguros en `micomd`. Escalado a ataque remoto (sideload de APK maliciosa sin verificación) con módulo público de Metasploit (`post/android/local/koffee`). Kia lo corrigió en 04/2020.

Topología real de bus confirmada por esta fuente primaria: **P-CAN(motor) · B-CAN(carrocería) · C-CAN(chasis) · I-CAN · M-CAN(multimedia)**, todos tras el CGW. El HU vive en M-CAN junto a amplificador, cuadro de instrumentos (IC) y E-CALL. Impacto demostrado: cámara trasera, idioma/info en cuadro, on/off HU, mute — nunca motor/frenos/DTC (aislados en P-CAN/C-CAN).

## Aplicabilidad e implicación para este proyecto

El CVE exacto no aplica a nuestro firmware (otra generación, ya parcheado), pero prueba que el patrón "app del HU → daemon tipo micomd → CAN real" existe de verdad en el ecosistema Hyundai/Kia/Genesis, probablemente compartido entre generaciones (mismo Tier 1). Con el root que ya da `navi_extended`/`wideopen_service` — más privilegio que la app sandboxed de KOFFEE — si el rootfs mango/S5W tiene un mecanismo equivalente, sería invocable directamente sin exploit adicional.

**Objetivo de grep concreto para cuando el rootfs esté descifrado:** `micomd`, `-c inject`, `sendMicomMsg`, `automotivefw`, `libHVehicle`, `@micom_mux`.

## Datos específicos: consumo, batería 48V, cámara frontal

- **Consumo/autonomía**: ✅ ya disponible sin exploit. Kia Connect cloud expone `vehicleStatus.dte.value` (confirmado en `KiaUvoApiEU.py`). El firmware STD_GEN5W también tiene pantalla nativa "Fuel economy" en el menú "Hybrid", pero gateada "(HEV only)" — el Rio es MHEV no HEV en la taxonomía Kia, aplicabilidad sin confirmar.
- **Batería 48V** (MHSG, 0,44 kWh Li-ion bajo el maletero): ⚠️ el SOC se muestra en el cuadro de instrumentos (gauge batería + gauge CHARGE/ECO/POWER) — evidencia de que la señal cruza la pasarela hasta el M-CAN (mismo segmento que HU e IC). El menú "Energy flow" (11 modos) también gateado "HEV only". Kia Connect **no** expone ningún campo 48V/MHSG (solo `battery.batSoc`=12V y `evStatus.*` solo EV/PHEV reales).
- **Cámara frontal — corregido tras aviso del usuario**: su función principal es **ISLA** (Intelligent Speed Limit Assist), implementación Kia del mandato europeo ISA (Reglamento UE 2019/2144, obligatorio 6/07/2022 tipos nuevos / 7/07/2024 todos los nuevos — muy probable que el Rio MY22 EU lo lleve de serie por ser obligatorio). ISLA combina cámara + **límite de velocidad de la base de datos de navegación** — probable conexión directa con `SPEED_PATCH.db`, ya manipulable en este proyecto: si se confirma, modificar esa DB podría afectar a un sistema de asistencia activa real, no solo al mapa. Sigue sin dar vídeo al HU; la única cámara de vídeo confirmada es la trasera (M-CAN, KOFFEE). Pendiente: confirmar si `appnavi` publica el límite de velocidad hacia fuera del HU (canal HU→ADAS).
- Nota general (sin datos de vehículos concretos): en el sector, una sola MFC suele soportar LDW+LFA+FCA+TSR/ISLA como un paquete, diferenciado por variant coding — que un vehículo tenga ya activas funciones de cámara más exigentes (ej. LFA, dirección activa por carril) es indicio de que el mismo sensor podría soportar también lectura de señales. El corte regulatorio (Reglamento UE 2019/2144, 6/07/2022) también importa: antes de esa fecha no hay obligación legal de llevar ISA, así que su ausencia en un acabado puede ser diferenciación comercial, no límite técnico.

## Vía D: activar ISLA/TSR si la cámara no lo tiene de fábrica

Real y documentado en el ecosistema HK (no exploit): el módulo de cámara frontal se llama **MFC** (Multi-Function Camera) en literatura genérica y **`FR_CMR`** en nomenclatura oficial Kia — confirmado con TSB real (`ELE246`, agosto 2021): KDS lo muestra como icono `FR_CMR` en el menú de sistema, conexión por **OBD-II estándar** (sin conector oculto), y exige "Variant Coding & Calibration" tras cualquier sustitución. El nombre `F-CMR` que muestran herramientas aftermarket (Autel, etc.) es la abreviatura de esa misma nomenclatura oficial. Tiene tablas de **variant coding** con casillas por función (evidencia en foro técnico `diag.net`: *"In LKA/LDW insert LDW. In FCA/FCW insert FCW"*), mismo patrón que TPMS/AFLS/ESC. Herramientas que funcionan: KDS/GDS+Jbox, GScan, Autel MaxiADAS (con licencia ADAS HK) — un ELM327 genérico no sirve (no pasa el CGW). **Matiz importante** (`diag.net`, "Best tool For Kia and Hyundai 2019+ models"): para 2018+/2019+ con SGW, consenso técnico es que *"the only real option is the Kia/Hyundai tablets"* (KDS/GDS genuino, ~15.000 USD con suscripciones) — herramientas aftermarket, **incluido Autel**, solo funcionan **parcialmente** contra el SGW en estos modelos; un scanner genérico/de entrada (ELM327, ThinkDiag) muy probablemente no basta. Incógnita adicional no verificable a distancia: si el hardware concreto de esa cámara soporta TSR (varía por trim, ej. Xceed 3 vs 4). Recomendación: no comprar un scanner genérico para esto específicamente — buscar taller independiente que ya tenga acceso real a KDS/GDS, consultar por VIN, recalibrar cámara tras el cambio.

## Vías evaluadas

- **A — OBD2 estándar al DLC** (sin exploit): DTCs genéricos Modo 03/04 sí funcionan siempre (regulación de emisiones, no pasa por SGW). Coding/calibración/actuator tests no, salvo herramienta con licencia SGW oficial (HiCOM, GDS).
- **B — HU rooteado** (ya disponible en el proyecto): permite el grep de arriba y, si hay mecanismo equivalente a micomd, invocarlo directamente. Techo real: solo M-CAN (HU/ampli/cuadro/E-CALL), nunca motor/frenos/DTC.
- **C — Bypass del SGW/CGW en sí**: sin exploit público conocido, proyecto de investigación aparte, aparcado.

Documentado en detalle en `docs/can_bus_obd2_investigation.md` (incluye diagrama de bus, timeline de responsible disclosure de KOFFEE, y plan de acción priorizado por coste/beneficio).
