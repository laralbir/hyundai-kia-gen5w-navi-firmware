#!/usr/bin/env python3
"""Renderiza la topología real de la red de carreteras a partir de la
adyacencia CONFIRMADA en `linked_records` de un `.haftlt` (campos f2/f3,
verificados estadísticamente el 2026-07-10 como índice ±1 del propio
registro — ver docs/hafr_spatial_index.md).

No usa ni necesita coordenadas GPS: construye un grafo (nodo = registro,
arista = f2/f3) y lo dibuja con un layout por fuerzas (spring layout). El
resultado NO está geográficamente orientado ni a escala — es la FORMA
topológica real de cada carretera/cluster de carreteras (secuencia de
segmentos + puntos de bifurcación reales), no un mapa con norte arriba.

Cuando se pasa --speed-patch-db, cruza el LINK_ID (f6|f7<<16, confirmado
con permutación p=0.0) contra SPEED_PATCH.db y colorea/etiqueta los nodos
con el límite de velocidad real donde exista — el único dato 100% verificado
que se puede anclar a estos nodos hoy (no nombres de calle: la conexión
nombre↔registro sigue sin confirmarse, ver tools/haftlt_parser/README.md).

Uso:
    # 1. Generar linked_records.csv con el parser existente:
    python3 ../haftlt_parser/parse_haftlt.py VIT_EUR_SPN.haftlt -o out/

    # 2. Renderizar el grafo:
    python3 generate_graph.py out/linked_records.csv \
        --speed-patch-db SPEED_PATCH.db \
        --top 12 -o /tmp/graph_spn.html
"""
import argparse
import csv
import io
import sqlite3
import struct
import sys

import networkx as nx

SPEED_COLORS = {
    20: "#7fd97f", 30: "#7fd97f", 40: "#a3d977",
    50: "#e0d060", 60: "#e0a860", 70: "#e0a860",
    80: "#e08060", 90: "#e08060", 100: "#e06060",
    110: "#e06060", 120: "#e06060", 130: "#e06060",
}
DEFAULT_COLOR = "#6699cc"
NO_MATCH_COLOR = "#555b66"


def build_graph(rows):
    G = nx.Graph()
    n = len(rows)
    for r in rows:
        idx = int(r["idx"])
        link_id = int(r["f6"]) | (int(r["f7"]) << 16)
        G.add_node(idx, link_id=link_id)
    for r in rows:
        idx = int(r["idx"])
        f2, f3 = int(r["f2"]), int(r["f3"])
        if f2 != 65535 and f2 < n:
            G.add_edge(idx, f2)
        if f3 != 65535 and f3 < n:
            G.add_edge(idx, f3)
    return G


def load_speed_limits(db_path, link_ids):
    if not db_path:
        return {}
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    result = {}
    ids = list(link_ids)
    for i in range(0, len(ids), 500):
        chunk = ids[i:i + 500]
        placeholders = ",".join("?" * len(chunk))
        cur.execute(
            f"SELECT LINK_ID, SP_LIMIT FROM SPEED_PATCH WHERE LINK_ID IN ({placeholders})",
            chunk,
        )
        for link_id, sp_limit in cur.fetchall():
            result.setdefault(link_id, []).append(sp_limit)
    conn.close()
    return result


def speed_color(limits):
    if not limits:
        return NO_MATCH_COLOR
    v = round(sum(limits) / len(limits) / 10) * 10
    return SPEED_COLORS.get(v, DEFAULT_COLOR)


def render_svg(G, comp, speed_limits, cell, ox, oy):
    sub = G.subgraph(comp)
    pos = nx.spring_layout(sub, seed=42, iterations=200)
    xs = [p[0] for p in pos.values()]
    ys = [p[1] for p in pos.values()]
    minx, maxx = min(xs), max(xs)
    miny, maxy = min(ys), max(ys)
    pad = 16

    def sx(x):
        return ox + pad + (x - minx) / (maxx - minx + 1e-9) * (cell - 2 * pad)

    def sy(y):
        return oy + pad + (y - miny) / (maxy - miny + 1e-9) * (cell - 2 * pad)

    parts = []
    for a, b in sub.edges():
        parts.append(
            f'<line x1="{sx(pos[a][0]):.1f}" y1="{sy(pos[a][1]):.1f}" '
            f'x2="{sx(pos[b][0]):.1f}" y2="{sy(pos[b][1]):.1f}" '
            f'stroke="#8892a0" stroke-width="1" opacity="0.6"/>'
        )
    for n_ in sub.nodes():
        x, y = sx(pos[n_][0]), sy(pos[n_][1])
        deg = sub.degree(n_)
        link_id = G.nodes[n_]["link_id"]
        limits = speed_limits.get(link_id, [])
        color = speed_color(limits)
        r = 4.5 if deg > 2 else (2.6 if limits else 2.2)
        title = f"idx={n_} LINK_ID={link_id}"
        if limits:
            title += f" SP_LIMIT={'/'.join(str(l) for l in sorted(set(limits)))} km/h"
        if deg > 2:
            title += f" (cruce, grado {deg})"
        parts.append(
            f'<circle cx="{x:.1f}" cy="{y:.1f}" r="{r}" fill="{color}" '
            f'stroke="{"#fff" if deg > 2 else "none"}" stroke-width="1"><title>{title}</title></circle>'
        )
    return "".join(parts)


def build_html(G, comps, speed_limits, cols, cell):
    rows_n = (len(comps) + cols - 1) // cols
    W = cols * cell
    H = rows_n * cell
    svg_parts = [
        f'<svg viewBox="0 0 {W} {H}" xmlns="http://www.w3.org/2000/svg" style="width:100%;height:auto;background:#0f1014">'
    ]
    for i, comp in enumerate(comps):
        row, col = divmod(i, cols)
        svg_parts.append(render_svg(G, comp, speed_limits, cell, col * cell, row * cell))
    svg_parts.append("</svg>")
    svg = "".join(svg_parts)

    legend_items = "".join(
        f'<span style="display:inline-flex;align-items:center;gap:4px;margin-right:14px">'
        f'<span style="width:10px;height:10px;border-radius:50%;background:{c};display:inline-block"></span>{v} km/h</span>'
        for v, c in sorted(SPEED_COLORS.items())
    )

    return f"""<!doctype html><html><head><meta charset="utf-8">
<title>Topología de red de carreteras (grafo, sin coordenadas)</title>
<style>
:root {{ color-scheme: dark; }}
body {{ background:#111317; color:#e6e6e6; font-family: -apple-system, "Segoe UI", sans-serif; margin:0; padding:20px 24px; }}
h1 {{ font-size:16px; margin:0 0 6px; }}
p {{ font-size:12px; color:#9aa0a8; max-width:900px; line-height:1.5; }}
.legend {{ font-size:11px; color:#c7ccd3; margin:10px 0 16px; }}
</style></head><body>
<h1>Topología real de la red de carreteras — reconstruida por adyacencia, sin coordenadas GPS</h1>
<p>Cada forma es un componente conexo real de <code>linked_records</code> (adyacencia vía campos <code>f2</code>/<code>f3</code>,
verificados estadísticamente como índice ±1 del propio registro). El layout es por fuerzas (spring layout) —
<b>no está orientado al norte ni a escala real</b>, pero la forma (curvas, bifurcaciones, bucles) refleja
la topología real de cada carretera/cluster. Los nodos blancos son cruces reales (grado &gt; 2). El color indica
el límite de velocidad real cuando el <code>LINK_ID</code> del nodo coincide con una fila de <code>SPEED_PATCH.db</code>
(vínculo confirmado con permutación, p=0.0) — gris = sin coincidencia en SPEED_PATCH.db.</p>
<div class="legend">{legend_items}<span style="display:inline-flex;align-items:center;gap:4px">
<span style="width:10px;height:10px;border-radius:50%;background:{NO_MATCH_COLOR};display:inline-block"></span>sin match en SPEED_PATCH.db</span></div>
{svg}
</body></html>"""


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("linked_records_csv", help="Salida de haftlt_parser/parse_haftlt.py")
    ap.add_argument("--speed-patch-db", default=None, help="Ruta a SPEED_PATCH.db (opcional, para colorear por límite real)")
    ap.add_argument("--top", type=int, default=12, help="Cuántos componentes conexos (más grandes) dibujar")
    ap.add_argument("--cols", type=int, default=4)
    ap.add_argument("--cell", type=int, default=280, help="Tamaño en px de cada celda de la rejilla")
    ap.add_argument("-o", "--output", default="haftlt_graph.html")
    args = ap.parse_args()

    with open(args.linked_records_csv) as f:
        rows = list(csv.DictReader(f))
    print(f"Cargados {len(rows)} registros de {args.linked_records_csv}", file=sys.stderr)

    G = build_graph(rows)
    comps = sorted(nx.connected_components(G), key=len, reverse=True)
    print(f"{len(comps)} componentes conexos — dibujando los {args.top} más grandes "
          f"(tamaños: {[len(c) for c in comps[:args.top]]})", file=sys.stderr)

    speed_limits = {}
    if args.speed_patch_db:
        all_link_ids = {G.nodes[n]["link_id"] for c in comps[:args.top] for n in c}
        speed_limits = load_speed_limits(args.speed_patch_db, all_link_ids)
        matched = sum(1 for lid in all_link_ids if lid in speed_limits)
        print(f"{matched}/{len(all_link_ids)} LINK_ID de los nodos dibujados tienen match en SPEED_PATCH.db", file=sys.stderr)

    html = build_html(G, comps[:args.top], speed_limits, args.cols, args.cell)
    with open(args.output, "w") as f:
        f.write(html)
    print(f"\nEscrito {args.output}", file=sys.stderr)


if __name__ == "__main__":
    main()
