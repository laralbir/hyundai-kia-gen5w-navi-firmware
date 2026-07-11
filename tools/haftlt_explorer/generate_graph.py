#!/usr/bin/env python3
"""Explorador de datos de `linked_records` de un `.haftlt` — tabla buscable
y filtrable, SIN pretender ser un mapa.

Contexto (ver docs/road_network_topology.md): un intento anterior dibujaba
esta misma adyacencia con un layout de fuerzas (spring layout) y parecía
"la forma de una red de carreteras" — pero un control con cadenas
puramente sintéticas y aleatorias (sin ningún dato real) produce el mismo
tipo de garabatos con bucles suaves. Es un artefacto estético del
algoritmo de layout aplicado a cualquier grafo disperso tipo cadena, no
evidencia de nada sobre carreteras reales. Se abandonó esa vía.

Lo que SÍ es real y verificado, y es lo que esta herramienta expone:
  - La adyacencia en sí (campos f2/f3 = índice ±1 del propio registro,
    confirmado al 84,6% en España completa).
  - El LINK_ID de cada registro (f6|f7<<16, confirmado con permutación
    p=0.0 contra SPEED_PATCH.db).
  - El límite de velocidad real cuando ese LINK_ID coincide con una fila
    de SPEED_PATCH.db.

Nota importante encontrada al construir esta versión: el grado máximo de
CUALQUIER nodo en las 23.528 filas de España es exactamente 2 (verificado
con conjuntos, sin aproximaciones) — es decir, f2/f3 describe listas
enlazadas simples (cadenas), sin ningún nodo de grado > 2. No hay cruces
reales codificados en este par de campos; no confundir "grado" con
"intersección de carretera".

La herramienta es una tabla buscable/filtrable/ordenable de estos hechos,
más un panel de "conexiones directas" (el nodo seleccionado + sus vecinos
inmediatos únicamente — un hecho de conectividad verificable, no un mapa)
al hacer click en una fila.

Uso:
    python3 ../haftlt_parser/parse_haftlt.py VIT_EUR_SPN.haftlt -o out/
    unzip -p S5W_MAP_ALL_EUR_*.zip "Data/Nation/EUR/MAP/SPEED_PATCH.db" > SPEED_PATCH.db
    python3 generate_graph.py out/linked_records.csv \
        --speed-patch-db SPEED_PATCH.db \
        -o /tmp/haftlt_explorer.html
"""
import argparse
import csv
import json
import sqlite3
import sys


def load_records(path):
    with open(path) as f:
        rows = list(csv.DictReader(f))
    return rows


def compute_neighbors(rows):
    """Devuelve dict idx -> [idx_vecino, ...] a partir de f2/f3."""
    n = len(rows)
    neighbors = {int(r["idx"]): [] for r in rows}
    for r in rows:
        idx = int(r["idx"])
        f2, f3 = int(r["f2"]), int(r["f3"])
        if f2 != 65535 and f2 < n:
            neighbors[idx].append(f2)
            neighbors.setdefault(f2, [])
            if idx not in neighbors[f2]:
                neighbors[f2].append(idx)
        if f3 != 65535 and f3 < n:
            neighbors[idx].append(f3)
            neighbors.setdefault(f3, [])
            if idx not in neighbors[f3]:
                neighbors[f3].append(idx)
    return neighbors


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


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("linked_records_csv", help="Salida de haftlt_parser/parse_haftlt.py")
    ap.add_argument("--speed-patch-db", default=None, help="Ruta a SPEED_PATCH.db (opcional)")
    ap.add_argument("-o", "--output", default="haftlt_explorer.html")
    args = ap.parse_args()

    rows = load_records(args.linked_records_csv)
    print(f"Cargados {len(rows)} registros de {args.linked_records_csv}", file=sys.stderr)

    neighbors = compute_neighbors(rows)

    link_ids = {int(r["idx"]): (int(r["f6"]) | (int(r["f7"]) << 16)) for r in rows}
    all_link_ids = set(link_ids.values())
    speed_limits = load_speed_limits(args.speed_patch_db, all_link_ids) if args.speed_patch_db else {}
    matched = sum(1 for lid in all_link_ids if lid in speed_limits)
    print(f"{matched}/{len(all_link_ids)} LINK_ID distintos con match en SPEED_PATCH.db", file=sys.stderr)

    records = []
    for r in rows:
        idx = int(r["idx"])
        link_id = link_ids[idx]
        nb = sorted(set(neighbors.get(idx, [])))
        records.append({
            "idx": idx,
            "link_id": link_id,
            "f0": int(r["f0"]), "f1": int(r["f1"]),
            "f2": int(r["f2"]), "f3": int(r["f3"]),
            "f4": int(r["f4"]), "f5": int(r["f5"]),
            "deg": len(nb),
            "nb": nb,
            "sp": sorted(set(speed_limits.get(link_id, []))),
        })

    with_speed = sum(1 for r in records if r["sp"])
    ends = sum(1 for r in records if r["deg"] == 1)
    max_deg = max((r["deg"] for r in records), default=0)
    print(f"{with_speed} registros con límite de velocidad real, {ends} extremos de cadena (grado 1), grado máximo observado: {max_deg}", file=sys.stderr)

    html = build_html(records)
    with open(args.output, "w") as f:
        f.write(html)
    print(f"\nEscrito {args.output}", file=sys.stderr)


def build_html(records):
    data = json.dumps(records, separators=(",", ":"))
    return HTML_TEMPLATE.replace("__DATA__", data).replace("__TOTAL__", str(len(records)))


HTML_TEMPLATE = r"""<!doctype html><html><head><meta charset="utf-8">
<title>haftlt explorer — adyacencia y límites reales, sin mapa</title>
<style>
:root { color-scheme: dark; }
body { background:#111317; color:#e6e6e6; font-family: -apple-system, "Segoe UI", sans-serif; margin:0; }
header { padding:14px 20px; background:#181b20; border-bottom:1px solid #2a2e35; }
header h1 { font-size:15px; margin:0 0 4px; }
header p { margin:0; font-size:12px; color:#9aa0a8; max-width:900px; line-height:1.5; }
.controls { display:flex; gap:10px; align-items:center; flex-wrap:wrap; padding:12px 20px; background:#14161a; border-bottom:1px solid #2a2e35; }
.controls input[type=text] { background:#0f1115; border:1px solid #33383f; color:#e6e6e6; border-radius:6px; padding:7px 10px; font-size:12px; width:180px; }
.controls select, .controls label { background:#22262e; border:1px solid #33383f; color:#e6e6e6; border-radius:6px; padding:7px 10px; font-size:12px; }
.controls label { display:flex; align-items:center; gap:6px; cursor:pointer; }
#count { font-size:12px; color:#9aa0a8; margin-left:auto; }
main { display:flex; height:calc(100vh - 128px); }
#tableWrap { flex:1; overflow:auto; }
table { width:100%; border-collapse:collapse; font-size:12px; }
th { position:sticky; top:0; background:#1b1e24; text-align:left; padding:8px 10px; cursor:pointer; user-select:none; border-bottom:1px solid #2a2e35; color:#c7ccd3; }
th:hover { color:#fff; }
td { padding:6px 10px; border-bottom:1px solid #1d2027; }
tr:hover td { background:#181b20; cursor:pointer; }
tr.selected td { background:#22304a; }
.badge { display:inline-block; padding:1px 7px; border-radius:10px; font-size:11px; font-weight:600; }
.pager { display:flex; gap:8px; align-items:center; padding:10px 20px; border-top:1px solid #2a2e35; background:#14161a; font-size:12px; }
.pager button { background:#22262e; border:1px solid #33383f; color:#e6e6e6; border-radius:6px; padding:5px 10px; cursor:pointer; }
.pager button:disabled { opacity:0.4; cursor:default; }
#side { width:340px; border-left:1px solid #2a2e35; background:#14161a; padding:16px; overflow:auto; }
#side h2 { font-size:13px; margin:0 0 10px; color:#c7ccd3; }
#side .kv { display:flex; justify-content:space-between; margin:3px 0; font-size:12px; }
#side .kv span:first-child { color:#9aa0a8; }
#side .kv b { color:#e6e6e6; }
#localGraph { margin-top:14px; }
#emptySide { color:#6a6f78; font-size:12px; }
.nb-list { margin-top:10px; font-size:12px; }
.nb-list .nb-row { display:flex; justify-content:space-between; padding:4px 6px; border-radius:5px; cursor:pointer; }
.nb-list .nb-row:hover { background:#1e222a; }
</style></head><body>
<header>
  <h1>haftlt explorer — adyacencia y límites de velocidad reales (sin pretender ser un mapa)</h1>
  <p>Tabla de los __TOTAL__ registros de <code>linked_records</code>. Cada fila es un hecho verificado: el índice de sus vecinos directos
  (campos <code>f2</code>/<code>f3</code>, confirmado al 84,6% como adyacencia real) y, cuando coincide, el límite de velocidad real
  de <code>SPEED_PATCH.db</code> vía su <code>LINK_ID</code>. <b>No hay ningún dibujo global ni "forma de red"</b> — un intento anterior con
  layout de fuerzas parecía una red de carreteras pero resultó ser un artefacto del algoritmo (ver docs/road_network_topology.md); esta
  versión solo muestra datos confirmados y, al hacer click, las conexiones directas de ese nodo en concreto.</p>
</header>
<div class="controls">
  <input id="q" type="text" placeholder="Buscar LINK_ID o idx...">
  <select id="speedFilter"><option value="">Cualquier límite</option></select>
  <label><input type="checkbox" id="onlyEnds"> solo extremos de cadena (grado 1)</label>
  <label><input type="checkbox" id="onlySpeed"> solo con límite real</label>
  <span id="count"></span>
</div>
<main>
  <div id="tableWrap">
    <table>
      <thead><tr>
        <th data-k="idx">idx</th>
        <th data-k="link_id">LINK_ID</th>
        <th data-k="deg">grado</th>
        <th data-k="sp">límite real</th>
        <th data-k="f2">f2</th>
        <th data-k="f3">f3</th>
      </tr></thead>
      <tbody id="tbody"></tbody>
    </table>
  </div>
  <div id="side"><div id="emptySide">Selecciona una fila para ver sus conexiones directas.</div></div>
</main>
<div class="pager">
  <button id="prevPage">← anterior</button>
  <span id="pageInfo"></span>
  <button id="nextPage">siguiente →</button>
</div>

<script>
const DATA = __DATA__;
const byIdx = new Map(DATA.map(r => [r.idx, r]));
const SPEED_COLORS = {20:"#5fae5f",30:"#5fae5f",40:"#8ab35f",50:"#c2b04a",60:"#c98f4a",70:"#c98f4a",80:"#c66f4a",90:"#c66f4a",100:"#c34a4a",110:"#c34a4a",120:"#c34a4a",130:"#c34a4a"};
function speedBadge(sp) {
  if (!sp || sp.length===0) return '<span style="color:#5a606a">—</span>';
  return sp.map(v => `<span class="badge" style="background:${SPEED_COLORS[Math.round(v/10)*10]||'#6699cc'};color:#0b0c0f">${v}</span>`).join(' ');
}

// filter options
(function initSpeedFilter(){
  const distinct = new Set();
  for (const r of DATA) for (const v of r.sp) distinct.add(v);
  const sel = document.getElementById('speedFilter');
  for (const v of [...distinct].sort((a,b)=>a-b)) {
    const opt = document.createElement('option'); opt.value=v; opt.textContent = v+' km/h'; sel.appendChild(opt);
  }
})();

let filtered = DATA;
let sortKey = 'idx', sortDir = 1;
let page = 0;
const PAGE_SIZE = 60;

function applyFilters() {
  const q = document.getElementById('q').value.trim();
  const speedVal = document.getElementById('speedFilter').value;
  const onlyEnds = document.getElementById('onlyEnds').checked;
  const onlyS = document.getElementById('onlySpeed').checked;
  filtered = DATA.filter(r => {
    if (q) {
      const qn = parseInt(q,10);
      if (String(r.link_id) !== q && String(r.idx) !== q && !(Number.isFinite(qn) && (r.link_id===qn || r.idx===qn))) return false;
    }
    if (speedVal !== '' && !r.sp.includes(parseInt(speedVal,10))) return false;
    if (onlyEnds && r.deg !== 1) return false;
    if (onlyS && r.sp.length === 0) return false;
    return true;
  });
  sortRows();
  page = 0;
  render();
}

function sortRows() {
  filtered = filtered.slice().sort((a,b) => {
    let av = a[sortKey], bv = b[sortKey];
    if (sortKey === 'sp') { av = a.sp[0] ?? -1; bv = b.sp[0] ?? -1; }
    if (av < bv) return -1*sortDir;
    if (av > bv) return 1*sortDir;
    return 0;
  });
}

document.querySelectorAll('th[data-k]').forEach(th => {
  th.addEventListener('click', () => {
    const k = th.dataset.k;
    if (sortKey === k) sortDir *= -1; else { sortKey = k; sortDir = 1; }
    sortRows(); page = 0; render();
  });
});

let selectedIdx = null;

function render() {
  const tbody = document.getElementById('tbody');
  const start = page * PAGE_SIZE;
  const pageRows = filtered.slice(start, start + PAGE_SIZE);
  tbody.innerHTML = pageRows.map(r => `
    <tr data-idx="${r.idx}" class="${r.idx===selectedIdx?'selected':''}">
      <td>${r.idx}</td>
      <td>${r.link_id}</td>
      <td>${r.deg}</td>
      <td>${speedBadge(r.sp)}</td>
      <td>${r.f2===65535?'—':r.f2}</td>
      <td>${r.f3===65535?'—':r.f3}</td>
    </tr>`).join('');
  tbody.querySelectorAll('tr').forEach(tr => {
    tr.addEventListener('click', () => selectRow(parseInt(tr.dataset.idx,10)));
  });

  document.getElementById('count').textContent = `${filtered.length} / ${DATA.length} registros`;
  const totalPages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  document.getElementById('pageInfo').textContent = `página ${page+1} / ${totalPages}`;
  document.getElementById('prevPage').disabled = page === 0;
  document.getElementById('nextPage').disabled = page >= totalPages-1;
}

function selectRow(idx) {
  selectedIdx = idx;
  render();
  const r = byIdx.get(idx);
  const side = document.getElementById('side');
  const nbRows = r.nb.map(n => {
    const nr = byIdx.get(n);
    return `<div class="nb-row" data-idx="${n}"><span>idx ${n} (LINK_ID ${nr?nr.link_id:'?'})</span>${nr?speedBadge(nr.sp):''}</div>`;
  }).join('') || '<div style="color:#6a6f78">sin vecinos registrados (extremo de cadena)</div>';
  side.innerHTML = `
    <h2>Nodo idx ${r.idx}</h2>
    <div class="kv"><span>LINK_ID</span><b>${r.link_id}</b></div>
    <div class="kv"><span>Límite real</span><b>${r.sp.length ? r.sp.join('/')+' km/h' : '— sin match'}</b></div>
    <div class="kv"><span>Grado (nº conexiones)</span><b>${r.deg}${r.deg===1?' — extremo de cadena':''}</b></div>
    <div class="kv"><span>f0 / f1</span><b>${r.f0} / ${r.f1}</b></div>
    <div class="kv"><span>f4 / f5</span><b>${r.f4} / ${r.f5}</b></div>
    <div class="nb-list"><b style="color:#c7ccd3">Conexiones directas (f2/f3):</b>${nbRows}</div>
  `;
  side.querySelectorAll('.nb-row[data-idx]').forEach(el => {
    el.addEventListener('click', () => selectRow(parseInt(el.dataset.idx,10)));
  });
}

document.getElementById('q').addEventListener('input', applyFilters);
document.getElementById('speedFilter').addEventListener('change', applyFilters);
document.getElementById('onlyEnds').addEventListener('change', applyFilters);
document.getElementById('onlySpeed').addEventListener('change', applyFilters);
document.getElementById('prevPage').addEventListener('click', () => { if (page>0) { page--; render(); } });
document.getElementById('nextPage').addEventListener('click', () => { page++; render(); } );

sortRows();
render();
</script>
</body></html>"""


if __name__ == "__main__":
    main()
