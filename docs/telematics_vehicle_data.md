# Comunicación externa de datos del vehículo — Telemetría / Kia Connect

Fecha de análisis: 2026-07-10.
Fuentes: manifiesto `Rio_MY22_EU.ver`, magic bytes de los paquetes de módem, proyectos públicos de RE de la API de Kia Connect (`Hyundai-Kia-Connect/kia_uvo`, `Hyundai-Kia-Connect/hyundai_kia_connect_api`, `Hacksore/bluelinky`).

---

## Pregunta de investigación

¿Cómo obtiene el HU la información del vehículo (velocidad, puertas, combustible, ubicación, etc.) y cómo la exporta hacia el exterior? El usuario apunta a un posible API REST.

## Dos canales distintos a diferenciar

Es importante separar dos sistemas que a menudo se confunden porque comparten el nombre "vehicle data":

### 1. Canal interno (CAN → HU)

El HU lee el bus CAN del vehículo (velocidad, puertas, nivel de combustible, RPM, etc.) mediante un **gateway/daemon interno** que corre en el rootfs principal (`mango-rootfs.tar.gz`). Este componente típicamente:
- Expone los datos a otras apps del HU (cluster, navegación, clima) vía **D-Bus** o sockets locales, no vía REST — un API HTTP local sería inusual pero no descartable (algunos HU exponen una mini API HTTP interna para apps tipo CarPlay/Android Auto o modo diagnóstico).
- Es el equivalente al "vehicle proxy" o "VIP" (Vehicle Information Provider) que aparece en otras plataformas Hyundai/Kia.

**Estado:** sin acceso — vive dentro de `mango-rootfs.tar.gz` (838,4 MB, cifrado AES). Bloqueado por el mismo cifrado que el resto del paquete OTA (ver [[gen5w-exploit-ecosystem]]).

### 2. Canal externo (HU/módem → nube Kia) — el que probablemente pregunta el usuario

Este es el sistema de **telemática (TCU)** que sube el estado del vehículo a los servidores de Kia para que la app móvil **Kia Connect** (antes UVO) lo muestre. Es un canal real hacia el exterior (Internet, vía LTE) y sí usa REST/HTTPS con payloads JSON.

**Evidencia pública del lado servidor (no del HU, sino de la API que consume la app):**
- Proyectos de RE ya existentes y consolidados (usados en Home Assistant, openHAB, ioBroker) documentan la API de Kia Connect:
  - [`Hyundai-Kia-Connect/hyundai_kia_connect_api`](https://github.com/Hyundai-Kia-Connect/hyundai_kia_connect_api) (Python, la librería base)
  - [`Hyundai-Kia-Connect/kia_uvo`](https://github.com/Hyundai-Kia-Connect/kia_uvo) (integración Home Assistant)
  - [`Hacksore/bluelinky`](https://github.com/Hacksore/bluelinky) (Node.js, equivalente para Hyundai Bluelink, misma infraestructura backend)
- Región EU: endpoint conocido `https://prd.eu-ccapi.kia.com:8080` — **CCAPI = Connected Car API**.
- La región EU firma cada petición con un "stamp" (algoritmo propietario, validez ~1 semana) — capa anti-abuso sobre el REST.
- Datos expuestos por esa API (y por tanto reportados por el vehículo): GPS + geocoding, odómetro, nivel de combustible/batería 12V y de tracción (EV/HEV), estado de puertas/ventanas/maletero, presión de neumáticos, climatización, estado de carga (si aplica), intervalos de servicio.

**Lo que NO es público:** el lado *vehículo* de esa comunicación — el cliente TCU que construye esos JSON a partir del CAN bus y los firma/envía. Ese código vive casi con toda seguridad en:
- `HU/firmware/modem/eu/modem_eu.tar.gz` (151,3 MB) — módem estándar EU
- `HU/firmware/modem/eu_le22/modem_eu_le22.tar.gz` (331,1 MB) — módem LTE EU chipset LE rev.22 (nuestro caso más probable, Kia Rio MY22 lleva LTE para Kia Connect)
- Posiblemente parte de la lógica de orquestación en `mango-rootfs.tar.gz` si el cliente HTTPS corre en el SoC principal y el módem solo hace de módem PPP/QMI.

Verificado con `xxd`: los tres paquetes de módem (`modem_eu`, `modem_eu_le22`, `modem_au_le22`) tienen el mismo patrón — **no son gzip, cifrados AES** igual que el resto del paquete OTA. Ya estaban catalogados como cifrados en [[file-details]]; este análisis no cambia su estado, solo confirma que son el objetivo correcto para responder la pregunta del usuario.

---

## Detalle técnico de la API CCAPI (lado servidor — de `hyundai_kia_connect_api`)

Código fuente inspeccionado: `hyundai_kia_connect_api/KiaUvoApiEU.py` y `ApiImplType1.py` (MIT, repo público `Hyundai-Kia-Connect/hyundai_kia_connect_api`). Esto documenta el API que consume la **app móvil**, no el HU — pero da el molde exacto de payloads/headers a buscar cuando se pueda leer el módem.

**Constantes hardcodeadas por marca (Kia EU):**
```python
BASE_DOMAIN = "prd.eu-ccapi.kia.com"
PORT = 8080
CCSP_SERVICE_ID = "fdc85c00-0a2f-4c64-bcb4-2cfb1500730a"   # client_id OAuth2
APP_ID       = "a2b8469b-30a3-4361-8e13-6fceea8fbe74"
CFB          = base64.b64decode("wLTVxwidmH8CfJYBWSnHD6E0huk0ozdiuygB4hLkM5XCgzAL1Dk5sE36d/bx5PFMbZs=")
BASIC_AUTHORIZATION = "Basic ZmRjODVjMDAtMGEyZi00YzY0LWJjYjQtMmNmYjE1MDA3MzBhOnNlY3JldA=="
LOGIN_FORM_HOST = "https://idpconnect-eu.kia.com"
```
Hyundai y Genesis EU tienen el mismo esquema con sus propias constantes (`prd.eu-ccapi.hyundai.com`, `prd-eu-ccapi.genesis.com`).

**Endpoints base:**
```
https://prd.eu-ccapi.kia.com:8080/api/v1/user/     (auth/OAuth2)
https://prd.eu-ccapi.kia.com:8080/api/v1/spa/      (SPA API v1)
https://prd.eu-ccapi.kia.com:8080/api/v2/spa/      (SPA API v2)
```
Estado del vehículo: `GET {SPA_API_URL}vehicles/{vehicle_id}/ccs2/carstatus` → JSON con raíz `vehicleStatus.*` (batería, motor, puertas/ventanas/maletero, presión neumáticos, luces, climatización, estado EV/carga, distancia recorrible...). "ccs2" parece ser la versión más reciente del protocolo de estado (frente a un `carstatus` v1 más antiguo).

**Header anti-abuso "Stamp"** — el mecanismo que buscaba la pregunta original ("firmado por semana"):
```python
def _get_stamp(self) -> str:
    raw_data = f"{APP_ID}:{int(datetime.now().timestamp())}".encode()
    result = bytes(b1 ^ b2 for b1, b2 in zip(CFB, raw_data))
    return base64.b64encode(result).decode()
```
Es un **XOR** de `APP_ID:timestamp_unix` contra el buffer `CFB` (constante estática, reutilizada como keystream — no es cifrado real pese al nombre). El resultado va en la cabecera HTTP `Stamp` de cada request junto a `ccsp-device-id`, `Authorization` (Bearer/control token) y `Ccuccs2protocolsupport`.

**Importante — distinción que hay que verificar con el HU real:** esto es la app-side de la nube (usa `okhttp/3.12.0` como User-Agent, o sea confirma que el cliente real es una app Android). El **vehículo** (TCU/módem) casi seguro NO usa este mismo flujo de login username/password + stamp XOR — probablemente usa autenticación por certificado/dispositivo (mTLS o similar) contra un endpoint distinto orientado a "push" de telemetría, no de "pull" de estado. Cuando se lea el módem, buscar strings `ccs2`, `carstatus`, `vehicleStatus`, `Stamp`, `ccsp-device-id`, `prd.eu-ccapi` o certificados cliente embebidos para confirmar si comparte infraestructura con la app o es un canal aparte.

---

## Bloqueo actual

Tanto el canal interno (rootfs) como el externo (módem) están **cifrados con el mismo esquema AES** que el resto del paquete OTA. No hay atajo de solo-lectura: para leer el código real (endpoints hardcodeados, certificados, formato exacto del payload, credenciales/VIN usado como identificador) hace falta:

1. Acceso físico al HU (instalado en el vehículo o en banco de pruebas).
2. Ejecutar el exploit `navi_extended` (ver [[gen5w-exploit-ecosystem]]) para extraer `DecryptToPIPE` + `decryption_key.der` del dispositivo.
3. Descifrar `mango-rootfs.tar.gz` y los `modem_*.tar.gz` con `update_decryptor`.
4. Buscar en el resultado: nombres de servicio D-Bus (`com.kia.*`, `com.lgsvl.*`, `com.hyundai.*`), binarios con strings `ccapi`, `eu-ccapi`, `telematics`, `tcu`, `vehicle_status`, certificados TLS embebidos, uso de `libcurl`/`openssl`, colas MQTT si las hubiera.

## Atajo potencial: shell en vivo sin descifrado completo

El propio exploit `navi_extended` da **ejecución de código en el sistema ya corriendo** (no en el paquete OTA cifrado — el rootfs en ejecución está, obviamente, descifrado en memoria/disco). Una vez ahí, sin necesidad de completar todo el pipeline de descifrado de los `.tar.gz`, se puede:

- `ps aux` / `systemctl list-units` — identificar el proceso/servicio de telemática en ejecución.
- `netstat -tlnp` / `ss -tlnp` — puertos locales abiertos (posible API HTTP local).
- `lsof -i` — conexiones salientes activas (confirmaría si habla con `eu-ccapi.kia.com` u otro host).
- Captura de tráfico (si el HU tiene interfaz de red accesible, o vía el propio módem en modo diagnóstico) — vería directamente las peticiones HTTPS salientes (aunque el contenido esté cifrado por TLS, el SNI/host de destino y el timing ya son informativos; con acceso a la CA del sistema podría plantearse un MITM controlado en banco de pruebas).
- `dbus-monitor` — si el gateway CAN expone datos vía D-Bus, se ven los nombres de servicio/método en vivo.

Esta vía es más rápida para responder "cómo exporta los datos" que esperar al descifrado completo de 838 MB + 331 MB de paquetes OTA, porque ataca el sistema en ejecución directamente.

---

## Estado del proyecto (Fase 1 del exploit)

A fecha de este análisis, **no se han extraído aún las claves** (`tools/phase2_decrypt/keys/` solo contiene `.gitkeep`) ni se ha ejecutado `navi_extended` sobre un HU físico. Este es el mismo bloqueo documentado para el resto del paquete — ver `tools/phase1_usb/README.md` para el procedimiento.

## Próximos pasos

1. Confirmar si hay acceso físico a un HU (vehículo o banco de pruebas) para ejecutar Fase 1.
2. Si hay acceso: priorizar extracción de shell en vivo (atajo de arriba) sobre el pipeline completo de descifrado, específicamente para esta pregunta.
3. Si no hay acceso físico por ahora: seguir documentando por OSINT el lado servidor (repos `hyundai_kia_connect_api`, `bluelinky`) para tener el "molde" del JSON esperado — facilita reconocer el código cliente en cuanto se consiga leer el módem o el rootfs.

Related: [[gen5w-exploit-ecosystem]] · [[file-details]] · [[project-context]] · [[re-findings]]
