# haftlt_graph_viewer — topología real de la red sin coordenadas GPS

Renderiza la **forma real** de la red de carreteras a partir de la adyacencia
ya confirmada en `linked_records` de un `.haftlt` (campos `f2`/`f3` — índice
±1 del propio registro, verificado estadísticamente el 2026-07-10, ver
[`docs/hafr_spatial_index.md`](../../docs/hafr_spatial_index.md)). **No usa
ni necesita coordenadas GPS** — construye un grafo (nodo = registro, arista
= adyacencia) y lo dibuja con un layout por fuerzas (spring layout, vía
`networkx`).

## Por qué esto funciona sin geometría descifrada

Toda la investigación de geometría (`.hafr`, `.hafp`, `.hafgsi` — ver
[`docs/hafp_geometry_search.md`](../../docs/hafp_geometry_search.md)) quedó
bloqueada en 2026-07-11: no hay coordenadas WGS84 ni deltas de tile
decodificables por inspección externa. Pero la **topología** (qué segmento
conecta con cuál) sí está confirmada con solidez estadística, y eso es
suficiente para dibujar la *forma* real de cada carretera — curvas,
bifurcaciones, bucles — aunque no su orientación ni posición geográfica real.
Es el mismo principio que un diagrama de metro: topológicamente fiel, no a
escala ni orientado al norte.

## Qué colorea el grafo

Cuando se pasa `--speed-patch-db`, cruza el `LINK_ID` de cada nodo
(`f6 | f7<<16`, confirmado con permutación p=0.0 contra `SPEED_PATCH.db` el
2026-07-10) contra la base de datos real de límites de velocidad — el único
dato que se puede anclar con certeza total a estos nodos hoy. **No** usa
nombres de calle: la conexión nombre↔registro sigue sin confirmarse (ver
[`tools/haftlt_parser/README.md`](../haftlt_parser/README.md)).

| Color | Significado |
|---|---|
| Verde/amarillo/naranja/rojo | Límite de velocidad real (20–130 km/h) confirmado vía `SPEED_PATCH.db` |
| Gris | Sin coincidencia en `SPEED_PATCH.db` (la mayoría — solo cubre segmentos con límite especial) |
| Nodo blanco (borde) | Cruce real — grado > 2 en el grafo de adyacencia |

## Uso

```bash
# 1. Generar linked_records.csv con el parser existente (ver tools/haftlt_parser/):
python3 ../haftlt_parser/parse_haftlt.py VIT_EUR_SPN.haftlt -o out/

# 2. Extraer SPEED_PATCH.db del ZIP de mapas (opcional pero recomendado):
unzip -p S5W_MAP_ALL_EUR_*.zip "Data/Nation/EUR/MAP/SPEED_PATCH.db" > SPEED_PATCH.db

# 3. Renderizar:
python3 generate_graph.py out/linked_records.csv \
    --speed-patch-db SPEED_PATCH.db \
    --top 16 --cols 4 \
    -o /tmp/graph_spn.html

open /tmp/graph_spn.html
```

## Requisitos

```bash
pip install networkx scipy
```

`scipy` no es estrictamente obligatorio (`networkx` tiene un fallback puro
Python) pero acelera mucho el `spring_layout` en componentes de cientos de
nodos.

## ⚠️ El HTML generado NO se debe commitear

Igual que `haftlt_viewer` y `map_render_viewer`: aunque este HTML no
embebe datos binarios brutos de HERE, sí deriva y muestra estructura real
del dataset propietario (topología + límites de velocidad reales). Genera y
revisa solo localmente.

## Verificación (sesión 2026-07-11)

Ejecutado contra `VIT_EUR_SPN.haftlt` real (23.528 registros de
`linked_records`): 4.733 componentes conexos, el mayor con 199 nodos. Los 16
componentes más grandes (~1.500 nodos totales) renderizan como curvas y
bucles topológicamente coherentes — no como ruido — con 131/1.558 `LINK_ID`
(8,4%) confirmados contra `SPEED_PATCH.db`, en línea con la tasa de
cobertura ya documentada en `docs/hafr_spatial_index.md` (~10%, dado que
`SPEED_PATCH.db` solo cubre segmentos con límite especial).

**Intento previo descartado en la misma sesión:** antes de llegar a este
enfoque se buscó geometría tipo malla/polilínea directamente en `.hafp03`
(bloques de enteros de 16 bits con estructura de triángulo compartido,
90% de tríos consecutivos con vértice en común) — pasó el filtro
estadístico pero, al renderizarlo, resultó ser dos contadores creciendo
juntos con ruido local, no una forma real. Ver
[`docs/hafp_geometry_search.md`](../../docs/hafp_geometry_search.md) para el
detalle. El enfoque de este tool (topología confirmada, no geometría nueva
sin verificar) es el que finalmente dio un resultado visualmente real.
