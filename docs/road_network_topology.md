# Adyacencia real vs. "forma de mapa" — por qué el layout por fuerzas engañaba

**Fecha:** 2026-07-11
**Contexto:** tras varias sesiones intentando decodificar coordenadas GPS/geometría absoluta en `.hafr`, `.hafp` y `.hafgsi` sin éxito (ver [`hafr_spatial_index.md`](hafr_spatial_index.md) y [`hafp_geometry_search.md`](hafp_geometry_search.md)), el usuario planteó una pregunta clave: **¿hace falta la coordenada absoluta, o basta con los valores relativos de nodos/grafo ya confirmados para renderizar algo real?** Este documento describe dos intentos con resultado negativo (uno estadístico, otro visual) y la herramienta honesta que quedó al final.

## Intento 1, descartado: geometría tipo malla en `.hafp03`

Se buscaron sistemáticamente en `.hafp03` (partición de España, 621 MB) bloques de enteros de 16 bits con la firma estadística de una malla triangulada (arrays de tríos consecutivos que comparten un vértice con el trío siguiente). Se encontraron regiones candidatas que pasaron un filtro estadístico estricto (90% de tríos consecutivos comparten un valor con el trío siguiente — imposible por azar). **Al renderizar estos valores como triángulos conectados, el resultado no era una forma real** — un garabato caótico con fuerte tendencia diagonal, consistente con dos contadores/índices acoplados con ruido, no geometría 2D. Descartado por verificación visual, no solo estadística.

## Intento 2, descartado tras un control decisivo: layout por fuerzas sobre la adyacencia confirmada

En vez de buscar geometría nueva, se usó lo que **ya estaba confirmado con solidez estadística** desde la sesión 2026-07-10: los campos `f2`/`f3` de `linked_records` (dentro de `.haftlt`) apuntan al índice ±1 del propio registro — adyacencia real y verificada, sin necesidad de coordenadas. Con esa adyacencia se construyó un grafo (`networkx`) y se dibujó con un layout por fuerzas (spring layout). El resultado (curvas, bucles, bifurcaciones suaves) **parecía a primera vista la forma de una red de carreteras real**.

**El usuario cuestionó esa conclusión — con razón.** Para comprobarlo de forma rigurosa (no solo defenderlo de palabra) se generó un control: cadenas **puramente sintéticas y aleatorias** (`nx.path_graph`, literalmente `0-1-2-3-...-N`, **sin ningún dato real del proyecto**), con un ~15% de aristas extra añadidas al azar para imitar la tasa de "saltos" observada en los datos reales. Dibujadas con el mismo layout:

**Producen exactamente el mismo tipo de garabatos con bucles suaves que los datos reales.**

Conclusión: el layout por fuerzas impone su propia estética (curvas suaves, bucles, ausencia de ángulos rectos) a **cualquier** grafo disperso de tipo cadena, sea la fuente datos reales de carreteras o números consecutivos inventados. La similitud visual con una "red de carreteras" no es evidencia de nada — es un artefacto del algoritmo, no una propiedad de los datos. Se retira por completo la afirmación de la sesión anterior.

## Hallazgo adicional al construir la versión honesta: no hay cruces en `f2`/`f3`

Al reconstruir la herramienta como tabla de datos (sin layout), se calculó el grado de cada nodo con conjuntos (sin aproximaciones): **el grado máximo de cualquiera de los 23.528 registros de España es exactamente 2.** Es decir, `f2`/`f3` describe **listas enlazadas simples (cadenas)** — cada registro tiene como mucho un "anterior" y un "siguiente", nunca una tercera conexión. No hay ningún cruce/intersección codificado en este par de campos.

Esto es coherente con una interpretación más modesta y más probable de lo que representa `f2`/`f3`: punteros de lista enlazada para agrupar registros consecutivos de un mismo tramo/hazard (por ejemplo, varios segmentos cortos con el mismo tipo de aviso a lo largo de una carretera), no la topología completa de la red con sus intersecciones. Las intersecciones reales, si están codificadas en algún sitio, no están en este campo.

## Lo que queda: una herramienta honesta, sin dibujo de forma alguna

[`tools/haftlt_explorer/`](../tools/haftlt_explorer/) — tabla buscable/filtrable/ordenable de los hechos verificados:

| Dato | Verificación |
|---|---|
| Adyacencia (`f2`/`f3`) | 84,6% de los valores no-centinela son exactamente `idx∓1`; grado máximo confirmado = 2 (listas enlazadas simples, sin cruces) |
| `LINK_ID` (`f6\|f7<<16`) | Confirmado con permutación (p=0.0) contra `SPEED_PATCH.db` |
| Límite de velocidad real | Coincidencia directa del `LINK_ID` contra `SPEED_PATCH.db` |

Al hacer click en una fila se muestra el panel de "conexiones directas" (sus 0, 1 o 2 vecinos según `f2`/`f3`) — un hecho verificable de conectividad local, sin ningún dibujo de conjunto ni pretensión de forma geográfica.

## Lección metodológica

Es la segunda vez en esta misma sesión (tras el intento de malla en `.hafp03`) que una verificación puramente visual/estética sin control resulta engañosa. La primera vez se corrigió comparando contra ruido evidente (garabato caótico). Esta segunda vez el error fue más sutil — el resultado parecía "razonable" (curvas suaves como una carretera real) precisamente porque el algoritmo de layout está diseñado para producir dibujos estéticamente agradables independientemente del contenido. **La lección aplicable en adelante:** cualquier verificación visual de una hipótesis de datos debe compararse contra un control con datos sintéticos/aleatorios del mismo tipo estructural — el mismo estándar que ya se aplicaba a las pruebas estadísticas (permutación) debe aplicarse también a "esto se ve bien".

Related: [`hafr_spatial_index.md`](hafr_spatial_index.md), [`hafp_geometry_search.md`](hafp_geometry_search.md), [`tools/haftlt_explorer/README.md`](../tools/haftlt_explorer/README.md), [`.claude/memory/haf_format.md`](../.claude/memory/haf_format.md)
