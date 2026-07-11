# haftlt_explorer — adyacencia y límites de velocidad reales, sin pretender ser un mapa

Tabla interactiva (buscable, filtrable, ordenable) de los registros de
`linked_records` de un `.haftlt`, más un panel de "conexiones directas" al
hacer click en una fila. **No dibuja ninguna forma global ni pretende
parecerse a un mapa o red de carreteras.**

## Por qué esta versión, y no un grafo dibujado

La primera versión de esta herramienta dibujaba la adyacencia (`f2`/`f3`)
con un layout de fuerzas (spring layout, vía `networkx`) — y visualmente
parecía la forma de una red de carreteras real (curvas, bucles,
bifurcaciones). **Era una ilusión.** Un control decisivo lo desmontó: se
generaron cadenas puramente sintéticas y aleatorias (`0-1-2-...-N` con
~15% de aristas extra al azar, **sin ningún dato real**) y, dibujadas con
el mismo layout, producen **el mismo tipo de garabatos con bucles
suaves**. Es un artefacto estético del algoritmo de layout de fuerzas
aplicado a cualquier grafo disperso tipo cadena — no es evidencia de nada
sobre carreteras reales, sea el grafo real o inventado. Detalle completo
y las imágenes de control: [`docs/road_network_topology.md`](../../docs/road_network_topology.md).

**Lo que sí es real y verificado**, y es lo único que expone esta
herramienta:

| Dato | Cómo se verificó |
|---|---|
| Adyacencia (`f2`/`f3` = índice ±1 del propio registro) | 84,6% exacto sobre 23.528 registros de España (ver `docs/hafr_spatial_index.md`) |
| `LINK_ID` (`f6\|f7<<16`) | Confirmado con prueba de permutación (p=0.0) contra `SPEED_PATCH.db` |
| Límite de velocidad real | Coincidencia directa del `LINK_ID` contra `SPEED_PATCH.db` |

El panel de "conexiones directas" de un nodo (al hacer click) es un hecho
verificable — "este registro tiene estos vecinos según `f2`/`f3`" — no una
posición ni una forma. No se dibuja ningún layout global.

## Uso

```bash
# 1. Generar linked_records.csv con el parser existente:
python3 ../haftlt_parser/parse_haftlt.py VIT_EUR_SPN.haftlt -o out/

# 2. Extraer SPEED_PATCH.db del ZIP de mapas (opcional pero recomendado):
unzip -p S5W_MAP_ALL_EUR_*.zip "Data/Nation/EUR/MAP/SPEED_PATCH.db" > SPEED_PATCH.db

# 3. Generar el explorador:
python3 generate_graph.py out/linked_records.csv \
    --speed-patch-db SPEED_PATCH.db \
    -o /tmp/haftlt_explorer.html

open /tmp/haftlt_explorer.html
```

Sin dependencias adicionales — solo Python estándar (`csv`, `json`,
`sqlite3`). No requiere `networkx` ni ninguna librería de layout (se quitó
junto con el grafo dibujado).

## Qué se puede hacer con la tabla

- **Buscar** por `LINK_ID` o `idx` exacto.
- **Filtrar** por límite de velocidad real, o por "solo cruces" (grado > 2
  en el grafo de adyacencia — candidatos a intersección real).
- **Ordenar** por cualquier columna (click en la cabecera).
- **Click en una fila** → panel lateral con sus vecinos directos
  (`f2`/`f3`) y, para cada vecino, su propio `LINK_ID` y límite si existe
  — se puede navegar de vecino en vecino.

## ⚠️ El HTML generado NO se debe commitear

Igual que el resto de visualizadores de este proyecto (`haftlt_viewer`,
`map_render_viewer`): el HTML embebe datos reales derivados del dataset
propietario de HERE (adyacencia + límites de velocidad). Genera y revisa
solo localmente.

## Verificación (sesión 2026-07-11)

Generado contra `VIT_EUR_SPN.haftlt` real (23.528 registros): tabla
completa, búsqueda por `LINK_ID`/`idx` y filtros funcionando, panel de
vecinos navegable click a click. Sin la parte de layout/dibujo de la
versión anterior — ver `docs/road_network_topology.md` para el porqué del
cambio de enfoque.
