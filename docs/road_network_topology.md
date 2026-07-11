# Topología real de la red de carreteras — renderizado sin coordenadas GPS

**Fecha:** 2026-07-11
**Contexto:** tras varias sesiones intentando decodificar coordenadas GPS/geometría absoluta en `.hafr`, `.hafp` y `.hafgsi` sin éxito (ver [`hafr_spatial_index.md`](hafr_spatial_index.md) y [`hafp_geometry_search.md`](hafp_geometry_search.md)), el usuario planteó una pregunta clave: **¿hace falta la coordenada absoluta, o basta con los valores relativos de nodos/grafo ya confirmados para renderizar algo real?** La respuesta es sí — este documento describe el intento fallido de encontrar geometría nueva en `.hafp`, y el enfoque que sí funcionó: renderizar la **topología** confirmada, no perseguir coordenadas nuevas.

## Intento descartado: geometría tipo malla en `.hafp03`

Se buscaron sistemáticamente en `.hafp03` (partición de España, 621 MB) bloques de enteros de 16 bits con la firma estadística de una malla triangulada (arrays de tríos consecutivos que comparten un vértice con el trío siguiente) — patrón típico de un índice de malla 3D o de una polilínea triangulada. Se encontraron dos regiones candidatas que pasaron un filtro estadístico estricto:

- **90% de los tríos consecutivos comparten un valor con el trío siguiente** — señal estadísticamente muy fuerte, imposible por azar con un rango de ~1.500 valores posibles.
- Rango de valores acotado y positivo (390–1.952 en la región 1), consistente con coordenadas locales pequeñas o índices.

**Al renderizar estos valores como triángulos conectados, el resultado no es una forma real** — es un garabato caótico con una fuerte tendencia diagonal (x≈y creciendo juntos), consistente con dos contadores/índices que avanzan de forma acoplada con ruido local, no con geometría 2D real. Es la enésima vez en esta investigación que un patrón estadísticamente "limpio" resulta ser una primitiva de serialización genérica (ver catálogo en `.claude/memory/haf_format.md`) en vez de datos geográficos — pero esta vez se verificó **visualmente**, no solo estadísticamente, antes de descartarlo.

## Lo que sí funcionó: topología confirmada, no geometría nueva

En vez de seguir buscando geometría sin verificar, se usó lo que **ya está confirmado con solidez estadística** desde la sesión 2026-07-10: los campos `f2`/`f3` de `linked_records` (dentro de `.haftlt`) apuntan al índice ±1 del propio registro — es decir, codifican de forma directa y verificada la **adyacencia real** entre segmentos de carretera (qué segmento conecta con cuál), sin necesidad de coordenadas.

**Verificación de la hipótesis "índice ±1" a escala completa** (España, 23.528 registros): de los `f2`/`f3` no-centinela, el 84,6% coincide exactamente con `idx-1`/`idx+1`. El 15,4% restante son saltos más grandes — con alta probabilidad, **cruces/bifurcaciones reales** donde la topología se desvía del simple orden secuencial de almacenamiento.

Con esta adyacencia se construyó un grafo (`networkx`) y se dibujó con un layout por fuerzas (spring layout) — sin ninguna coordenada de entrada. Resultado:

- **4.733 componentes conexos** en España (23.528 registros), el mayor con 199 nodos.
- Los componentes grandes se dibujan como **curvas, bucles y bifurcaciones topológicamente coherentes** — no como ruido. Los nodos de grado > 2 (cruces reales) aparecen naturalmente en los puntos donde una cadena se ramifica.
- Cruzando el `LINK_ID` de cada nodo (`f6|f7<<16`, confirmado con permutación p=0.0) contra `SPEED_PATCH.db`, el 8,4% de los nodos de los componentes grandes tienen un límite de velocidad real confirmado — coherente con la cobertura ya documentada (~10%, dado que `SPEED_PATCH.db` solo cubre segmentos con límite especial).

## Qué significa esto y qué no

**Sí es real:** la forma (curvas, bifurcaciones, bucles) de cada componente refleja la topología verdadera de un tramo de carretera o cluster de carreteras conectadas — es información genuina extraída del formato HERE, no inventada ni interpolada.

**No es un mapa geográfico:** el layout por fuerzas no tiene norte, escala ni posición real — dos carreteras que en la vida real están a 500 km de distancia pueden aparecer una al lado de la otra en el render. Es un diagrama topológico (como un mapa de metro), no cartográfico.

**Herramienta:** [`tools/haftlt_graph_viewer/`](../tools/haftlt_graph_viewer/) — genera el HTML con el grafo, coloreado por límite de velocidad real donde hay coincidencia confirmada en `SPEED_PATCH.db`.

## Próximos pasos

1. **Aislar más precisamente los saltos grandes de `f2`/`f3`** (el 15,4% que no es ±1) — son los candidatos más fuertes a cruces reales; cruzarlos contra los nodos de grado > 2 del grafo para confirmar que coinciden.
2. **Probar con otros países** (el patrón 84,6%/15,4% se verificó solo en España) para confirmar que la proporción de "saltos reales" es consistente.
3. Si se encuentra alguna forma de anclar aunque sea un componente a una posición real conocida (p. ej. cruzando el patrón de nombres de calle con un cruce de alto grado en una localidad pequeña y conocida), se podría orientar/escalar el resto del grafo por continuidad — no intentado todavía.

Related: [`hafr_spatial_index.md`](hafr_spatial_index.md), [`hafp_geometry_search.md`](hafp_geometry_search.md), [`tools/haftlt_graph_viewer/README.md`](../tools/haftlt_graph_viewer/README.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
