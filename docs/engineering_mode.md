# Engineering Mode — Análisis de acceso

Fecha de análisis: 2026-06-30.  
Fuentes: `update_patcher.sh` (gen5w), análisis QML, oviradio.cz, n-cars.net, XDA forums, kia-forums.com.

---

## ¿Qué es Engineering Mode?

Engineering Mode (también llamado Service Mode o Diagnostic Mode) es un menú oculto del Head Unit que expone:
- Información del sistema (versión SW, hardware, calibración)
- Ajustes de pantalla y audio de bajo nivel
- Acceso a logs del sistema
- Gestión de actualizaciones, modo diagnóstico OBD

En la plataforma gen5w, la UI de Engineering Mode está implementada en Qt/QML:
```
/app/share/AppEngineerMode/AppEngineerMode_PinCodeKeypad.qml
```

---

## Distinción crítica: Standard Gen5W vs. Premium AVNT

El **Kia Rio MY22 EU** lleva el sistema **Standard Gen5W** (Linux/QML, plataforma mango x86-64), **no** el sistema Premium AVNT (Android-based). Esto afecta directamente al PIN y al procedimiento de acceso.

| Sistema | Plataforma | PIN | Nuestro HU |
|---|---|---|---|
| **Standard Gen5W** (STD_GEN5W) | Linux / Qt-QML | `21` / `11` (ver análisis QML) | ✅ SÍ |
| Premium Gen5W AVNT | Linux/Android | 8 dígitos (`19480717`) | ❌ NO |
| Gen5 Standard (anterior) | Linux / Qt-QML | `2801`, `1111`, `2400` | ❌ NO |

---

## Bloqueos en firmware MASS_PRODUCT

El firmware `MASS_PRODUCT` tiene **dos capas de bloqueo en el Standard Gen5W**:

### Capa 1 — SOP Version Check (bloqueo principal)

```qml
// En múltiples .qml del rootfs:
checkSOPVersion() === <valor_engineering>
: AppEngineerModeEngine.checkSOPVersion()
```

`AppEngineerModeEngine.checkSOPVersion()` devuelve `true` solo en builds de ingeniería, nunca en `MASS_PRODUCT`. Bloquea Engineering Mode **antes incluso de mostrar el PIN**, independientemente del código introducido.

El parche del rootfs (`update_patcher.sh`) invierte la lógica:
```bash
checkSOPVersion() ===  →  checkSOPVersion() !==
: AppEngineerModeEngine.checkSOPVersion()  →  : false
```

### Capa 2 — PIN QML

En `AppEngineerMode_PinCodeKeypad.qml`:
```qml
enterMenu == 21    // acceso al menú principal de Engineering Mode
enterMenu == 11    // acceso a sub-menú específico
```

`enterMenu` es una propiedad QML que recoge el valor numérico introducido en el teclado PIN. Analizado el código:
- **PIN principal: `21`**
- **PIN sub-menú: `11`**

El parche elimina el check: `enterMenu == 21` → `enterMenu` (cualquier valor pasa).

> **En firmware MASS_PRODUCT stock**: aunque se introduzca el PIN correcto (`21`), la capa 1 (SOP check) bloquea la entrada. Ambas capas deben estar bypasadas para que EM funcione.

---

## Procedimiento de acceso — Standard Gen5W (nuestro sistema)

### Cómo llegar al teclado PIN

Hay tres métodos documentados para el Standard Gen5W (Linux/QML):

#### Método A — Digital/Analogue/None (más confirmado)

1. Ir a **All menus → Settings** (o pulsar botón **Setup**)
2. Navegar a la pantalla de ajuste de sonido donde aparecen las opciones **Digital – Analogue – None**
3. Tocar **por debajo** de esas tres opciones en la siguiente secuencia (**7 toques en total**):

```
Digital  →  Analogue  →  None  →  Analogue  →  Digital  →  Analogue  →  None
  [1]          [2]         [3]       [4]           [5]          [6]         [7]
```

4. Aparece el teclado PIN → introducir `21`

#### Método B — System Info / SW Version

1. Ir a **All menus → Settings → System Information** (o similar)
2. En la pantalla de versiones SW/FW/Map:
   - Tocar **5 veces a la izquierda** del botón "Update"
   - Tocar **1 vez a la derecha** del botón "Update"
3. Aparece el teclado PIN → introducir `21`

Variante alternativa:
   - Tocar la palabra **"Map"** 7 veces rápido
   - Teclado PIN → `21`

#### Método C — Volume knob (algunos modelos con 2 mandos)

1. Ajustar el volumen a **7** → pulsar el mando derecho
2. Ajustar el volumen a **3** → pulsar el mando derecho
3. Ajustar el volumen a **1** → pulsar el mando derecho
4. Engineering Mode se abre directamente (sin PIN en algunas versiones)

> El Kia Rio MY22 tiene un solo mando de volumen. El Método A o B son los más probables para este modelo.

### PIN a introducir

| Sub-modo | PIN | Check QML |
|---|---|---|
| Engineering Mode principal | **`21`** | `enterMenu == 21` |
| Sub-menú alternativo | **`11`** | `enterMenu == 11` |

---

## PIN para sistemas Premium AVNT (referencia, no nuestro sistema)

Los sistemas Premium AVNT (con pantallas grandes, Android o Linux premium) usan PINs de 8 dígitos basados en fechas históricas coreanas, rotados por versión de firmware:

| Versión firmware EUR | PIN (8 dígitos) | Fecha histórica |
|---|---|---|
| 240726, 250226 | `19190301` | 1 de marzo de 1919 (Movimiento 1 de Marzo) |
| **250604, 251204** | **`19480717`** | 17 de julio de 1948 (Constitución Corea del Sur) |

> Nuestro firmware es `251204` (build 4 de diciembre de 2025). Si el sistema resulta ser AVNT Premium, el PIN sería **`19480717`**. Para Standard Gen5W el PIN es `21`.

El sistema selecciona el código mediante `eng_pswd_<N>` donde N es el último dígito del año actual. Si no hay GPS, usa `eng_pswd_default`.

---

## Impacto del bloqueo SOP en firmware stock

**En el Kia Rio MY22 con firmware MASS_PRODUCT `YB_22.EUR.S5W_L.001.001.251204`:**

```
Intento de acceso al Engineering Mode
    │
    ├─ Método A/B/C activa el teclado PIN (probablemente sí funciona)
    │
    └─ PIN correcto ("21") introducido
           │
           └─ checkSOPVersion() === false  → EM BLOQUEADO ❌
```

El teclado PIN probablemente aparece en pantalla (la secuencia táctil funciona), pero al confirmar el PIN, el SOP check falla y EM no se abre.

**Excepción:** versiones de firmware anteriores a noviembre de 2021 no tienen el SOP check.

---

## Resumen operativo

| Escenario | Acción |
|---|---|
| HU stock (firmware actual MASS_PRODUCT) | EM inaccesible sin parchear rootfs |
| HU con rootfs parcheado (wideopen) | Método A/B + PIN `21` → EM accesible |
| HU con firmware pre-noviembre 2021 | Método A/B + PIN `21` directamente |
| HU Premium AVNT (no nuestro caso) | Método diferente + PIN `19480717` |

---

## Cómo verificar el PIN directamente en el firmware

Una vez descifrado el rootfs (Fase 2 + 3 del flujo gen5w), el PIN se puede leer directamente:

```bash
# Buscar el QML con el check del PIN
find rootfs_extracted/ -name "AppEngineerMode_PinCodeKeypad.qml" 2>/dev/null

# Leer el check
grep -n "enterMenu\|pinCode\|pswd\|password" \
  rootfs_extracted/app/share/AppEngineerMode/AppEngineerMode_PinCodeKeypad.qml
```

Si muestra `enterMenu == 21` → PIN es `21`. Si muestra `enterMenu == 19480717` → PIN es `19480717`.

---

## Fuentes

- [Oviradio.cz — Engineering Mode passwords gen5w](https://www.oviradio.cz/hyundai-kia-radio-engineering-mode-en/)
- [n-cars.net — How to read the engineering password from update files](https://n-cars.net/forums/threads/how-to-read-the-engineering-password-from-the-software-update-files.12485/)
- [Kia Forums — Engineering Mode password found](https://www.kia-forums.com/threads/no-longer-working-uvo-gen5-nov-8-update-access-engineering-mode-password-found.354178/)
- [Hyundai Forums — Standard Gen5W 8-digit code](https://www.hyundai-forums.com/threads/anyone-know-standart-gen5w-standart-8-digit-engineering-mode-code.726495/)
- [Kia EV Forum — Engineering Mode code](https://www.kiaevforums.com/threads/does-anyone-know-the-new-engineering-mode-code.8018/)
- `update_patcher.sh` (gen5w repo) — parches QML con los checks exactos
