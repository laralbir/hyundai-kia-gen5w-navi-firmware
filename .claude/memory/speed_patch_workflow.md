---
name: speed-patch-workflow
description: Workflow completo para modificar SPEED_PATCH.db y reempaquetar el ZIP con checksums actualizados — el único camino confirmado y operativo
metadata: 
  node_type: memory
  type: project
  originSessionId: 4fdd3d22-4481-42d4-b6d4-82d1d973bc3c
---

## Workflow: Modificar SPEED_PATCH.db e instalar

Este es el camino confirmado y completamente operativo. No requiere reverse engineering adicional.

### 1. Extraer SPEED_PATCH.db del ZIP

```bash
unzip -p S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip \
  "Data/Nation/EUR/MAP/SPEED_PATCH.db" > SPEED_PATCH.db
```

### 2. Esquema SQLite

```sql
CREATE TABLE VERSION_INFO (
    FORMAT_VERSION TEXT,   -- "1.0.1.0"
    DATA_VERSION   TEXT    -- "2025072316" (23 jul 2025)
);

CREATE TABLE SPEED_PATCH (
    LINK_ID      INT64,    -- HERE Road Link ID (clave externa a .hafp tiles)
    DIR          INT,      -- 0=dirección A→B, 1=B→A, 2=ambas
    SP_LIMIT     INT,      -- Límite de velocidad en km/h
    VEHICLE_TYPE INT,      -- Bitmask de tipo de vehículo (ver tabla)
    PRIMARY KEY (LINK_ID, DIR, VEHICLE_TYPE)
) WITHOUT ROWID;
```

**VEHICLE_TYPE bitmask:**
| Valor | Tipos cubiertos |
|-------|----------------|
| 0 | Todos los vehículos |
| 7 | Coche + moto + ciclomotor |
| 15 | + vehículos ligeros |
| 23 | + camiones |
| 31 | + autobuses |
| 55, 56, 63, 64, 72, 88, 96, 103, 111, 119, 120, 127 | Otras combinaciones |

**Estadísticas (España + resto EU):**
- Total: 10,353,101 filas
- SP_LIMIT 50: 3.77M filas (predominante — vías urbanas)
- SP_LIMIT 30: 1.48M filas
- SP_LIMIT 90: 1.36M filas

### 3. Operaciones SQLite útiles

```bash
# Abrir la base de datos
sqlite3 SPEED_PATCH.db

# Ver límites en un link específico
SELECT * FROM SPEED_PATCH WHERE LINK_ID = 12345678;

# Cambiar límite en un segmento (p.ej. de 120 a 100 km/h)
UPDATE SPEED_PATCH 
SET SP_LIMIT = 100 
WHERE LINK_ID = 12345678 AND DIR = 0 AND VEHICLE_TYPE = 0;

# Añadir entrada nueva (nuevo segmento con límite)
INSERT INTO SPEED_PATCH (LINK_ID, DIR, SP_LIMIT, VEHICLE_TYPE)
VALUES (99999999, 0, 80, 0);

# Eliminar entrada
DELETE FROM SPEED_PATCH WHERE LINK_ID = 12345678;

# Ver distribución de límites
SELECT SP_LIMIT, COUNT(*) as cnt 
FROM SPEED_PATCH 
GROUP BY SP_LIMIT 
ORDER BY cnt DESC;
```

### 4. Reempaquetar el ZIP

⚠️ El ZIP original tiene 17.9 GB. Reempaquetarlo completo tarda horas.

**Opción A — Actualización in-place (más rápido, si el sistema soporta ZIP actualizado):**
```bash
# Actualizar solo SPEED_PATCH.db dentro del ZIP existente
# PRECAUCIÓN: esto cambia el tamaño si el archivo modificado es diferente
zip -u S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip \
  "Data/Nation/EUR/MAP/SPEED_PATCH.db"
```

**Opción B — Reempaquetar completo (garantizado):**
```bash
# Extraer todo, modificar, recomprimir
unzip S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip -d map_contents/
# [hacer modificaciones]
cd map_contents/
zip -r ../S5W_MAP_ALL_EUR_18_49_56_023_631_5_modified.zip .
```

### 5. Actualizar checksums

**Calcular nuevo MD5 del ZIP:**
```bash
md5 S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip
# Salida: MD5 (S5W_MAP_ALL_EUR...) = <nuevo_hash>

# Actualizar EUR.18.49.56.023.631.5_md5.txt
# Formato exacto: "<hash> *<nombre_archivo>\n"
echo "<nuevo_hash> *S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip" > EUR.18.49.56.023.631.5_md5.txt
```

**Calcular nuevo CRC32 para Rio_MY22_EU.ver:**
```python
import struct, zlib

def crc32_signed(filepath):
    with open(filepath, 'rb') as f:
        data = f.read()
    crc = zlib.crc32(data)
    # Convertir a signed int32 (como lo usa el .ver)
    return struct.unpack('<i', struct.pack('<I', crc & 0xFFFFFFFF))[0]

zip_crc  = crc32_signed('S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip')
zip_size = os.path.getsize('S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip')

md5_crc  = crc32_signed('EUR.18.49.56.023.631.5_md5.txt')
md5_size = os.path.getsize('EUR.18.49.56.023.631.5_md5.txt')
```

**Formato del .ver:** (pipe-delimited)
```
Rio_MY22_EU\HU\images\navi_eu|S5W_MAP_ALL_EUR_18_49_56_023_631_5.zip|308440|<crc_signed>|<size>|1
Rio_MY22_EU\HU\images\navi_eu|EUR.18.49.56.023.631.5_md5.txt|308439|<crc_signed>|<size>|1
```

### 6. Incógnitas antes de instalar

1. **¿Verifica el dispositivo el .ver?** El OTA updater probablemente sí — es el mecanismo de integridad principal
2. **¿Verifica appnavi checksums internos de SPEED_PATCH.db?** Posible — si tiene hash interno, la modificación se detectaría sin cambiar el resultado visible
3. **¿El cambio en SP_LIMIT activa alertas de radar?** Depende de si la app diferencia "límite de mapa HERE" vs "posición de cámara"

Related: [[haftlt-format]] · [[project-radar-db]] · [[haf-format]]
