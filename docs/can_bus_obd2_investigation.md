# CAN bus / OBD2 — Nueva vía de investigación

Fecha de análisis: 2026-07-11 (actualizado el mismo día con precedente académico directo — CVE-2020-8539/KOFFEE).
Estado: **investigación abierta, sin RE de código propio sobre nuestro rootfs todavía**, pero con un precedente académico **directo, con CVE y PoC público**, sobre un head unit hermano de la misma familia Hyundai/Kia/Genesis. Este documento fija el terreno (arquitectura real del vehículo, qué da cada camino de acceso, qué es realista) y da un objetivo de grep concreto para cuando el rootfs esté descifrado.

---

## Pregunta original

¿Se puede, con el exploit `navi_extended` (o uno similar), acceder al bus de diagnóstico OBD2 del Kia Rio MY22 EU desde el head unit? Y si se accede: ¿se pueden leer/borrar códigos de fallo (DTC), cambiar configuraciones, calibrar, o ejecutar funciones especiales?

## Resumen ejecutivo

- El HU **no es** el punto de entrada al bus de diagnóstico. En la arquitectura real de Hyundai/Kia (confirmada con fuente primaria, ver §3) el HU cuelga del **M-CAN** (Multimedia CAN), un segmento separado del **P-CAN** (powertrain), **B-CAN** (body), **C-CAN** (chassis) e **I-CAN**, todos enrutados por el **Central Gateway (CGW)**.
- Desde 2018+ los Hyundai/Kia con CGW incorporan un **Security Gateway (SGW)**: cualquier tester que pida servicios UDS privilegiados (pruebas de actuador, funciones especiales, *coding*) en una ECU debe presentar un **certificado digital emitido por Hyundai/Kia** al CGW; sin él, el CGW responde `NRC 0x33 securityAccessDenied` (ISO 14229). No hay bypass público documentado para esto.
- Los **DTC genéricos (Modo 03 leer / Modo 04 borrar)** son estándar OBD2 (regulación de emisiones) y **no dependen del SGW ni del HU** — se obtienen con cualquier adaptador OBD2 estándar (ELM327/ISO 15765) enchufado directamente al conector DLC del coche. Esta es la vía más simple y ya disponible, sin exploit.
- **Precedente directo y con CVE real** (§3): en 2020, investigadores del CNR italiano lograron inyectar tramas CAN en el **M-CAN** de un Kia Ceed desde el head unit comprometido, ejecutando el propio binario del sistema `micomd` con el flag `-c inject` (`CVE-2020-8539`, exploit público **KOFFEE**). Esto demuestra que el mecanismo interno "app del HU → daemon `micomd` → tramas CAN reales en el bus" **existe de verdad** en el ecosistema Hyundai/Kia, no es solo teoría de arquitectura.
- Ganar acceso root en el HU (`navi_extended` + `wideopen_service`, ya documentado en [gen5w_exploit_ecosystem.md](gen5w_exploit_ecosystem.md)) da como mínimo el mismo nivel de acceso que la app maliciosa de KOFFEE (ejecución de comandos arbitrarios) — con la ventaja de ser root, no una app sandboxed. Objetivo de grep concreto una vez el rootfs esté descifrado: buscar `micomd`, `-c inject`, `sendMicomMsg`, o equivalentes.
- Ese acceso **no** da automáticamente autorización SGW para escribir en ECUs de otros segmentos (P-CAN motor, C-CAN chasis) — el propio KOFFEE demuestra control real solo sobre HU/amplificador/cuadro de instrumentos/E-CALL, todos residentes en el M-CAN, nunca sobre motor, ABS o airbag.
- No existe (públicamente) un exploit conocido contra el SGW/CGW en sí — sería un proyecto de investigación distinto (mucho más difícil) al de descifrado de firmware del HU o al de KOFFEE.

---

## 1. Arquitectura real del vehículo (contexto necesario)

Los Kia/Hyundai con **Central Gateway (CGW)** dividen la red del vehículo en varios segmentos CAN que el CGW enruta y filtra. Fuente primaria (diagrama real de un **Kia Ceed**, presentación KOFFEE del CNR italiano — ver §3): la topología documentada es

```
                    ┌─────┐
                    │ CGW │
                    └──┬──┘
   P-CAN ── B-CAN ── C-CAN ── I-CAN ── M-CAN
                                        ├── AMP (amplificador)
                                        ├── HU  (head unit)
                                        ├── IC  (cuadro de instrumentos)
                                        └── E-CALL
```

- **P-CAN** = Powertrain (motor/transmisión), **B-CAN** = Body (carrocería/confort), **C-CAN** = Chassis (ABS/dirección/suspensión), **I-CAN** = probablemente Interior/Instrument, **M-CAN** = Multimedia — el segmento donde vive el head unit junto al amplificador, el cuadro de instrumentos y el módulo E-CALL.
- El HU **no está en el mismo segmento** que motor, ABS o airbag — están en P-CAN/C-CAN, detrás del CGW. Esto no es una suposición genérica de este documento: es la topología real medida por los investigadores en un vehículo físico de la misma casa (Kia).

Desde ~2018 (Ceed CD, Stinger, K5/Optima >2020, y prácticamente todo lo posterior) el CGW o el ICCU (Integrated Central Control Unit, que combina Smart Junction Block + CGW) actúan como único punto de paso entre el conector de diagnóstico (DLC, bajo el volante) y las ECUs individuales.

Sobre ese CGW se añade el **Security Gateway (SGW)**: una capa de autorización para servicios UDS "peligrosos" (`0x27` SecurityAccess de nivel alto, `0x2E` WriteDataByIdentifier/coding, `0x31` RoutineControl/actuator test, `0x2F` InputOutputControlByIdentifier). Un tester genérico puede leer DTCs y datos en vivo (PIDs estándar), pero para *funciones especiales* el CGW exige un certificado digital emitido por Hyundai/Kia y vinculado al fabricante de la herramienta de diagnóstico. La autorización es offline (no necesita conexión a internet en el momento del diagnóstico), pero el certificado en sí solo lo emite Hyundai/Kia a fabricantes de escáner con licencia (p. ej. HiCOM, GDS, Launch X431 con módulo Hyundai/Kia).

**Implicación directa para un Kia Rio MY22 EU (build 2025):** con casi total seguridad este vehículo tiene CGW+SGW. La UE exige homologación de ciberseguridad (UN R155) para nuevos tipos desde julio de 2022 y para todo vehículo nuevo matriculado desde julio de 2024 — un MY22 europeo con build de firmware de finales de 2025 es coherente con tener esta protección activa, no es una laguna de un modelo "antiguo".

---

## 2. ¿Qué papel juega el HU en esto?

Ya sabemos por [telematics_vehicle_data.md](telematics_vehicle_data.md) que el HU **lee** datos del vehículo por CAN (velocidad, presión neumáticos, etc. — necesarios para navegación con odometría y para el cuadro). Eso confirma que el HU **está físicamente conectado a algún segmento CAN**. La evidencia directa de §3 (mismo fabricante, HU hermano) apunta a que ese segmento es el **M-CAN** (Multimedia), no el de body/confort en sentido amplio — el M-CAN es el segmento propio de HU+amplificador+cuadro+E-CALL, separado de B-CAN.

Búsqueda pública (foros XDA, GitHub `cantcs/HKG_Gen5W_ReverseEngineer`, `rgerganov/gen5fw`) confirma que:
- Algunos head units gen5w tienen **todo el circuito OBD interno**; otros usan un **conector CAN-rx/CAN-tx separado** hacia un **MCU externo** que hace la conversión de protocolo OBD del coche a protocolo serie interno del HU (fuente: hilo XDA "How do CAN Bus messages make it into the unit?" — ver Fuentes). Cuál de los dos casos aplica a nuestro Rio MY22 EU **no está confirmado** — es el primer punto a verificar.
- Ningún repositorio público de RE de gen5w (`navi_extended`, `HKG_Gen5W_ReverseEngineer`, `gen5fw`, el blog `xakcop.com/post/hyundai-hack-2`) documenta el daemon/proceso interno que lee el CAN, ni nombres de servicio, ni si usa SocketCAN (`can0`) o un chip UART-a-CAN propietario. Esto es terreno inexplorado — encaja con el patrón del proyecto: somos los primeros en mirarlo.
- El fichero manifiesto `Rio_MY22_EU.ver` **no lista ningún binario de firmware separado para un MCU CAN/gateway** (a diferencia del frontkey MKBD, que sí tiene su propio `.bin` — ver [frontkey_mkbd_analysis.md](frontkey_mkbd_analysis.md)). Esto sugiere que, si hay un MCU externo de conversión CAN, su firmware no viaja en este paquete OTA (podría no ser actualizable, o gestionarse por otro canal), o que el mango SoC principal tiene el transceptor CAN integrado y todo vive en el rootfs/kernel.

---

## 3. Precedente académico directo: KOFFEE / CVE-2020-8539 (Kia Ceed, HU Android Gen 5.0 "iAVN")

Fuente primaria: presentación técnica "KOFFEE — Kia OFFensivE Exploit" (G. Costantino, I. Matteucci, IIT-CNR Italia), CVE-2020-8539, módulo Metasploit `post/android/local/koffee` (Rapid7).

### ⚠️ Aplicabilidad: es otra generación de HU, no la nuestra

El head unit atacado es el **Gen 5.0 "iAVN"** de un Kia Ceed: **Android 4.2.2**, CPU ARM Cortex A9, pantalla 8". Nuestro Rio MY22 EU lleva **Standard Gen5W** (Linux/Qt-QML, SoC "mango", versión "S5W_L") — un sistema y generación distintos, ya diferenciados en [engineering_mode.md](engineering_mode.md). El CVE-2020-8539 en sí (versiones de software `SOP.003.30.18.0703`, `SOP.005.7.181019`, `SOP.007.1.191209`, corregido por Kia en `SOP.008.4.200619`) **no aplica literalmente** a nuestro firmware. Lo que sí aporta este precedente es la prueba de que **el patrón arquitectónico es real** en el ecosistema Hyundai/Kia/Genesis, y probablemente compartido entre generaciones porque lo suministra el mismo proveedor Tier 1.

### Qué encontraron

1. **Reconocimiento**: no sabían si el HU estaba conectado al CAN bus del coche ("HU connected to the CAN bus? — We did not know…"). Empezaron por acceso físico al HU en laboratorio y RE completo del sistema: 98 apps, 2.654.557 líneas de código (Java+XML) descompiladas desde APK+ODEX.
2. **Búsqueda dirigida**: no analizaron todo el código a ciegas — buscaron específicamente "cualquier línea de código que muestre cómo controlar el HU y/o enviar tramas del bus CAN" (búsqueda difusa/fuzzy sobre el código descompilado).
3. **Hallazgo clave** — método `sendMicomMsg(String msg)`:
   ```java
   private boolean sendMicomMsg(String msg) {
       try {
           Process process = Runtime.getRuntime().exec("micomd -c inject " + msg);
           ...
       }
   }
   ```
   Es decir: cualquier app del HU con permiso de ejecutar procesos puede invocar el binario de sistema **`micomd`** con el flag **`-c inject`** seguido de un mensaje, y ese mensaje se traduce en una trama CAN real enviada al M-CAN del vehículo.
4. **Ataque local → remoto (KOFFEE)**: primero demostraron inyección local (con acceso físico/Engineering Mode del HU); luego lo convirtieron en un ataque de dos pasos completamente remoto: (1) engañar a la víctima para instalar una app Android maliciosa en el HU (el propio HU permite sideload de APKs desde USB o servidor remoto vía el navegador del sistema, sin verificación), (2) la app instalada llama a `sendMicomMsg()` para inyectar comandos sin que el usuario haga nada más.
5. **CVE-2020-8539** (MITRE, texto oficial): *"Kia Motors Head Unit... may allow an attacker to inject unauthorized commands, by executing the micomd executable deamon, to trigger unintended functionalities. In addition, this executable may be used by an attacker to inject commands to generate CAN frames that are sent into the M-CAN bus (Multimedia CAN bus) of the vehicle."* Clasificada como vulnerabilidad de **permisos inseguros** (`micomd` no verificaba qué proceso lo invocaba).
6. **Impacto demostrado** (acciones del módulo Metasploit público): `CAMERA_REVERSE_ON/OFF` (mostrar/ocultar la cámara trasera), `CLUSTER_CHANGE_LANGUAGE` y `CLUSTER_RADIO_INFO` (escribir en el **cuadro de instrumentos**, confirma que el IC cuelga del mismo M-CAN que el HU), `SET_NAVIGATION_ADDRESS`, `SWITCH_ON_Hu`/`SWITCH_OFF_Hu`, `TOGGLE_RADIO_MUTE`. **Nunca lograron control de motor, frenos, dirección ni DTCs** — coherente con que esos sistemas están en P-CAN/C-CAN, no en M-CAN.

### Divulgación responsable (timeline real)

Hallazgo 07/2019 → prueba de concepto KOFFEE 02/2020 → Kia publica software de HU corregido 04/2020 → informe técnico 11/2020 → CVE asignado 12/2020 → paper académico completo + módulo Metasploit público 04/2021.

### Qué nos aporta esta investigación a nosotros

- **Objetivo de grep concreto** para cuando tengamos el rootfs mango/S5W descifrado (Fase 2 del pipeline gen5w): buscar el binario `micomd` (o equivalente), la cadena `-c inject`, y cualquier símbolo `sendMicomMsg`/`send_micom` en los binarios de las apps del sistema. Esto encaja además con lo que ya documentamos en [telematics_vehicle_data.md](telematics_vehicle_data.md) sobre un daemon CAN→D-Bus interno sin nombre confirmado — es muy probable que sea la misma familia de componente (`micomd`/`automotivefw`/`libHVehicle`, nombres vistos también en una teardown independiente de otro head unit Hyundai/Kia basado en Linux con socket Unix abstracto `@micom_mux` y nodo `/dev/tcc_ipc`).
- **Techo realista de lo alcanzable vía HU**, ya con datos reales y no solo teoría: control de funciones del propio HU/amplificador/cuadro/E-CALL — **no** motor/frenos/DTC. Esto confirma con evidencia dura la hipótesis de aislamiento CGW que ya planteábamos en este documento.
- **El acceso root que ya tenemos** (`navi_extended`/`wideopen_service`) es estrictamente más potente que el vector de KOFFEE (una app Android sandboxed con permiso de ejecutar procesos) — si nuestro rootfs tiene un mecanismo equivalente a `micomd -c inject`, con root deberíamos poder invocarlo directamente sin necesitar ningún exploit adicional de por medio, exactamente igual que el ataque *local* original de la fase 1 de KOFFEE (antes de que lo convirtieran en remoto).

### Fuentes de esta sección

- [KOFFEE — Kia OFFensivE Exploit (PDF, IIT-CNR)](https://automotivespin.isti.cnr.it/wp-content/uploads/2021/05/KOFFEE-Kia-OFFensivE-Exploit.pdf)
- [CVE-2020-8539 (MITRE)](https://www.cve.org/CVERecord?id=CVE-2020-8539)
- [Rapid7 — módulo Metasploit `post/android/local/koffee`](https://www.rapid7.com/db/modules/post/android/local/koffee/)
- [Reversing Kia Motors Head Unit to discover and exploit software vulnerabilities — Journal of Computer Virology and Hacking Techniques, 2022](https://link.springer.com/article/10.1007/s11416-022-00430-5)
- [Gist con detalle del advisory (SOP.008.4.200619 = versión corregida)](https://gist.github.com/gianpyc/4dc8b0d0c29774a10a97785711e325c3)
- [SOWHAT — Security Of the Way to Handle Automotive sysTems, IIT-CNR](https://sowhat.iit.cnr.it/)

---

## 4. Vías de acceso evaluadas

### Vía A — OBD2 estándar directo al conector DLC (sin exploit, sin HU)

La más simple y ya disponible hoy. Un adaptador ISO 15765 (CAN) tipo ELM327/OBDLink conectado al DLC del propio Rio da:

| Función | ¿Disponible? | Motivo |
|---|---|---|
| Leer DTCs genéricos (Modo 03) | ✅ Sí | Estándar OBD2 de emisiones, obligatorio en todo vehículo homologado, no pasa por SGW |
| Borrar DTCs genéricos (Modo 04) | ✅ Sí | Igual que arriba |
| Datos en vivo (RPM, temp, velocidad — PIDs Modo 01) | ✅ Sí | Estándar OBD2 |
| DTCs mejorados específicos de fabricante | ⚠️ Parcial | Necesita stack UDS + base de datos de DTC Kia; herramientas como HiCOM lo soportan sin SGW para *lectura* |
| Cambiar configuraciones / *coding* (WriteDataByIdentifier) | ❌ No con ELM327 genérico | Bloqueado por SGW — requiere certificado Hyundai/Kia |
| Calibración / adaptación de ECU | ❌ No con ELM327 genérico | Igual, requiere autorización SGW |
| Funciones especiales / test de actuadores (RoutineControl) | ❌ No con ELM327 genérico | Igual, requiere autorización SGW |

Herramientas de terceros con licencia oficial que sí llevan el certificado SGW: **HiCOM** (interfaz dedicada Hyundai/Kia, ISO15765/KWP2000/ISO9141, usada por talleres independientes), **GDS/Hi-Scan Pro** (herramienta oficial de concesionario), y marcas generalistas con módulo Hyundai/Kia con licencia (Launch X431, Autel, Delphi/Autocom). **OBDeleven** tiene soporte para Hyundai/Kia pero limitado (diagnóstico básico, no el catálogo completo de *coding* que ofrece para VAG/BMW).

**Esta vía no necesita nada de lo que hemos construido en este proyecto** (no depende del descifrado del firmware ni de `navi_extended`). Es el camino más rápido para "obtener fallos, borrarlos" a nivel básico.

### Vía B — Shell root en el HU vía `navi_extended`/`wideopen_service` (ya disponible en el proyecto)

Con el exploit físico ya documentado ([gen5w_exploit_ecosystem.md](gen5w_exploit_ecosystem.md)) se consigue ejecución root persistente en el HU. Esto **no da acceso al bus de diagnóstico per se**, pero permite:

1. **Buscar el equivalente de `micomd -c inject`** (§3): grep sobre `/usr/bin`, `/app`, systemd units y librerías `.so` del rootfs descifrado por `micomd`, `-c inject`, `sendMicomMsg`, `send_micom`, `automotivefw`, `libHVehicle`, socket abstracto `@micom_mux`, o nodos tipo `/dev/*_ipc`. Si existe algo equivalente, con shell root se puede invocar directamente — sin necesitar ninguna vulnerabilidad adicional, exactamente como el ataque *local* de KOFFEE (que partía de una simple app con permiso de ejecutar procesos, mucho menos privilegio que root).
2. Averiguar a qué segmento CAN está conectado realmente el HU (`ip link show`, `cat /proc/net/can/*`, `lsmod | grep -i can`, buscar nodos `/dev/can*` o chips UART-CAN en `dmesg`).
3. Si hay SocketCAN activo, hacer *sniffing* pasivo del tráfico que el HU ya recibe (con un binario `candump` estático subido por USB, dado que el rootfs probablemente no lo incluye) — esto documentaría en vivo qué IDs CAN ve el HU, sin necesidad de escribir nada.
4. Identificar el daemon/proceso propietario que traduce CAN → D-Bus (el que ya sabemos que existe, per [telematics_vehicle_data.md](telematics_vehicle_data.md)) y ver si expone también DTCs o solo señales de confort/navegación.
5. Revisar si el "modo diagnóstico OBD" mencionado en el propio menú de Engineering Mode ([engineering_mode.md](engineering_mode.md), línea "Gestión de actualizaciones, modo diagnóstico OBD") es una pantalla real de lectura de DTC accesible desde la UI del HU una vez desbloqueado el Engineering Mode — pista barata de verificar, porque no depende de tocar el bus CAN en absoluto, solo de tener el rootfs parcheado y PIN `21`.

Techo realista incluso si el paso 1 tiene éxito: por precedente directo (§3), el HU solo alcanza su propio segmento M-CAN (HU, amplificador, cuadro de instrumentos, E-CALL) — **no** vería ni podría inyectar tramas de diagnóstico de motor/ABS/airbag, que viven en P-CAN/C-CAN detrás del CGW.

### Vía C — Bypass del SGW para obtener autorización de funciones especiales sin certificado oficial

Esto es un problema de seguridad **distinto y mucho más difícil** que descifrar el firmware del HU:
- No hay exploit público conocido contra el SGW/CGW de Hyundai/Kia (búsqueda realizada sin resultados — a diferencia del ecosistema gen5w del HU, que sí es público y maduro).
- Requeriría analizar el firmware del propio CGW/ICCU (que no tenemos — no forma parte de este paquete OTA del HU) o interceptar/clonar la lógica de validación de certificados, terreno de investigación de seguridad automotriz "dura" (ej. los ataques conocidos de seed-key son por ECU individual bajo `0x27`, no rompen el SGW en sí).
- No es descartable a largo plazo, pero es un proyecto nuevo, sin relación con el trabajo ya hecho de descifrado de firmware — habría que tratarlo como una investigación aparte si se decide perseguir.

---

## 5. Plan de acción recomendado (por esfuerzo/beneficio)

1. **Una vez el rootfs esté descifrado (Fase 2/3 del pipeline gen5w ya existente)**: grep inmediato por `micomd`, `-c inject`, `sendMicomMsg`, `automotivefw`, `libHVehicle`, `@micom_mux` (§3) — coste marginal cero, es un `grep -r` más sobre un rootfs que de todas formas se va a explorar.
2. **Verificar el menú "modo diagnóstico OBD" del Engineering Mode** una vez el rootfs esté parcheado (wideopen + bypass SOP/PIN, ya documentado) — coste marginal cero si de todas formas se va a desbloquear EM para otras cosas.
3. **Comprar/usar un adaptador OBD2 ISO15765 genérico** (ELM327 o similar) y probar Modo 03/04 directamente en el conector DLC del Rio — no requiere nada de este repo, es el ground truth más barato de "qué fallos hay ahora mismo" y sirve además para descartar/confirmar arquitectura del vehículo (si aparecen DTCs de red tipo "CAN gateway timeout" da pistas de la topología real).
4. **Con el HU rooteado (Vía B)**: si el paso 1 encuentra un mecanismo tipo `micomd`, probarlo directamente desde el shell root; si no, inspeccionar interfaces de red/CAN visibles, identificar el daemon CAN→D-Bus, documentar qué IDs ve.
5. **Solo si 1–4 dejan margen de interés real**: evaluar herramientas con licencia SGW oficial (HiCOM u otras) para *coding*/funciones especiales — vía legítima y sin exploit, simplemente de pago.
6. Vía C (bypass SGW) queda **aparcada** — no hay indicios de que sea viable con el conocimiento público actual, y es un proyecto distinto al de este repositorio.

---

## 6. Nota de seguridad/legal

Los pasos 2 y 4 actúan sobre el vehículo real (no solo sobre el firmware del HU en el banco). Antes de ejecutar *RoutineControl*/*actuator tests* o *coding* real conviene:
- Hacerlo con el motor parado y, si es posible, en un entorno controlado.
- Tener claro qué hace cada rutina antes de lanzarla (algunas actúan sobre frenos, airbag, dirección asistida).
- Tener en cuenta que ciertos cambios de configuración pueden afectar a la homologación/ITV del vehículo.

---

## Fuentes

- [KOFFEE — Kia OFFensivE Exploit (PDF, IIT-CNR)](https://automotivespin.isti.cnr.it/wp-content/uploads/2021/05/KOFFEE-Kia-OFFensivE-Exploit.pdf) — fuente primaria de la arquitectura de bus real (P/B/C/I/M-CAN) y del mecanismo `micomd -c inject`
- [CVE-2020-8539 (MITRE)](https://www.cve.org/CVERecord?id=CVE-2020-8539)
- [Rapid7 — módulo Metasploit `post/android/local/koffee`](https://www.rapid7.com/db/modules/post/android/local/koffee/)
- [Reversing Kia Motors Head Unit to discover and exploit software vulnerabilities — Journal of Computer Virology and Hacking Techniques, 2022](https://link.springer.com/article/10.1007/s11416-022-00430-5)
- [Gist con detalle del advisory KOFFEE](https://gist.github.com/gianpyc/4dc8b0d0c29774a10a97785711e325c3)
- [SOWHAT — Security Of the Way to Handle Automotive sysTems, IIT-CNR](https://sowhat.iit.cnr.it/)
- [programmingwithstyle.com — How I Hacked my Car Part 4: CAN Bus/Micom Access](https://programmingwithstyle.com/posts/howihackedmycarpart4/) — teardown independiente que confirma el mismo patrón `micomd`/`automotivefw`/`libHVehicle`/`@micom_mux` en otro head unit Hyundai/Kia
- [DAP4CS — Hyundai/Kia Security Gateway (SGW)](https://dap4cs.com/sgw)
- [HiCOM — Hyundai/Kia professional diagnostic scantool](https://www.obdtester.com/hicom)
- [XDA Forums — How do CAN Bus messages make it into the unit?](https://xdaforums.com/t/how-do-can-bus-messages-make-it-into-the-unit.3352343/)
- [GitHub — cantcs/HKG_Gen5W_ReverseEngineer](https://github.com/cantcs/HKG_Gen5W_ReverseEngineer)
- [GitHub — rgerganov/gen5fw](https://github.com/rgerganov/gen5fw)
- [xakcop.com — Hyundai Head Unit Hacking (parte 2)](https://xakcop.com/post/hyundai-hack-2/)
- [GitLab — hkm-gen5/gen5w/navi_extended](https://gitlab.com/g4933/gen5w/navi_extended)
- [OBDeleven — Hyundai](https://obdeleven.com/hyundai)
- [GitHub — JejuSoul/OBD-PIDs-for-HKMC-EVs, issue #41](https://github.com/JejuSoul/OBD-PIDs-for-HKMC-EVs/issues/41)
- [Pinout OBD2/DLC de 16 pines Kia](https://pinoutguide.com/CarElectronics/kia_obd2_diagnostic_pinout.shtml) — pin 6 CAN-H, pin 14 CAN-L (J-2284), pin 7/8 K-Line

Related: [gen5w_exploit_ecosystem.md](gen5w_exploit_ecosystem.md) · [engineering_mode.md](engineering_mode.md) · [telematics_vehicle_data.md](telematics_vehicle_data.md)
