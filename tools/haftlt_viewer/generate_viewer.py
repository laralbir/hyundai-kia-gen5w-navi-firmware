#!/usr/bin/env python3
"""
Genera un visualizador HTML interactivo y autocontenido para un fichero
VIT_EUR_XXX.haftlt (base de datos de radares HERE), comparando dos builds.

No decodifica coordenadas GPS -- el registro de camara aun no esta resuelto
(ver docs/haftlt_build_diff_260128.md). Es una herramienta de inspeccion:
minimapa navegable coloreado por region conocida, hex dump en vivo, e
inspector u8/u16/u32 little-endian.

El HTML resultante embebe los dos ficheros .haftlt completos en base64, por
lo que NO debe commitearse al repositorio (contiene datos propietarios de
HERE). Generar bajo demanda y usar solo localmente, o publicarlo como
Artifact efimero para revisarlo.

Uso:
    python3 generate_viewer.py OLD.haftlt NEW.haftlt --country SPN -o out.html
"""
import argparse
import base64
import json
import sys

COLORS = {
    "header": (110, 110, 105),
    "index": (42, 120, 214),
    "sec1": (27, 175, 122),
    "mid_same": (48, 48, 46),
    "mid_new": (227, 73, 72),
    "sec234": (237, 161, 0),
    "tail_same": (48, 48, 46),
    "tail_new": (235, 104, 52),
}

HTML_TEMPLATE = r"""<title>Visualizador — VIT_EUR_{COUNTRY}.haftlt</title>
<style>
:root {
  --surface-1:      #fcfcfb;
  --surface-2:      #f2f1ee;
  --surface-3:      #e9e7e1;
  --text-primary:   #0b0b0b;
  --text-secondary: #52514e;
  --text-muted:     #7a7972;
  --border:         #dedcd5;
  --accent:         #2a78d6;
}
@media (prefers-color-scheme: dark) {
  :root {
    --surface-1:      #171715;
    --surface-2:      #201f1c;
    --surface-3:      #29281f;
    --text-primary:   #f5f4f0;
    --text-secondary: #c3c2b7;
    --text-muted:     #8f8e85;
    --border:         #3a3934;
    --accent:         #3987e5;
  }
}
:root[data-theme="dark"] {
    --surface-1:      #171715;
    --surface-2:      #201f1c;
    --surface-3:      #29281f;
    --text-primary:   #f5f4f0;
    --text-secondary: #c3c2b7;
    --text-muted:     #8f8e85;
    --border:         #3a3934;
    --accent:         #3987e5;
}
:root[data-theme="light"] {
  --surface-1:      #fcfcfb;
  --surface-2:      #f2f1ee;
  --surface-3:      #e9e7e1;
  --text-primary:   #0b0b0b;
  --text-secondary: #52514e;
  --text-muted:     #7a7972;
  --border:         #dedcd5;
  --accent:         #2a78d6;
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
  background: var(--surface-1);
  color: var(--text-primary);
  margin: 0;
  padding: 20px;
}
.wrap { max-width: 1180px; margin: 0 auto; }
h1 { font-size: 1.25rem; margin: 0 0 2px; }
p.sub { color: var(--text-secondary); margin: 0 0 16px; font-size: 0.85rem; }
.toolbar {
  display: flex; flex-wrap: wrap; gap: 8px; align-items: center;
  background: var(--surface-2); border: 1px solid var(--border); border-radius: 10px;
  padding: 10px 12px; margin-bottom: 14px;
}
.toolbar .group { display: flex; gap: 4px; align-items: center; }
.toolbar label { font-size: 0.78rem; color: var(--text-secondary); margin-right: 4px; }
button, select, input[type=text] {
  font-family: inherit; font-size: 0.8rem;
  background: var(--surface-3); color: var(--text-primary);
  border: 1px solid var(--border); border-radius: 6px;
  padding: 5px 9px; cursor: pointer;
}
button:hover { border-color: var(--accent); }
button.active { background: var(--accent); color: #fff; border-color: var(--accent); }
input[type=text] { width: 90px; cursor: text; }
.sep { width: 1px; align-self: stretch; background: var(--border); margin: 0 4px; }
.main { display: flex; gap: 16px; align-items: flex-start; }
.minimap-col { flex: none; width: 160px; }
.minimap-frame {
  border: 1px solid var(--border); border-radius: 8px; overflow: hidden;
  background: var(--surface-2); padding: 6px; position: relative;
}
#minimap { display: block; width: 100%; height: auto; cursor: crosshair; image-rendering: pixelated; }
#viewport-marker {
  position: absolute; left: 6px; right: 6px; pointer-events: none;
  border: 2px solid #fff; box-shadow: 0 0 0 1px #000, 0 0 6px rgba(0,0,0,.6);
  background: rgba(255,255,255,0.12);
}
.legend { margin-top: 10px; font-size: 0.72rem; display: flex; flex-direction: column; gap: 4px; }
.legend .item { display: flex; align-items: center; gap: 6px; }
.legend .sw { width: 11px; height: 11px; border-radius: 2px; flex: none; }
.legend .item span.lbl { color: var(--text-secondary); }
.hex-col { flex: 1 1 auto; min-width: 0; }
.hexbox {
  border: 1px solid var(--border); border-radius: 8px; background: var(--surface-2);
  padding: 10px 12px; overflow-x: auto;
}
.hexrow { display: flex; gap: 14px; font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 12.5px; line-height: 20px; white-space: pre; }
.hexrow .off { color: var(--text-muted); width: 74px; flex: none; }
.hexrow .bytes { flex: none; }
.hexrow .ascii { color: var(--text-secondary); flex: none; }
.byte { padding: 0 1px; border-radius: 2px; }
.byte.cursor { outline: 1px solid var(--text-primary); }
.inspector {
  display: flex; gap: 18px; flex-wrap: wrap; margin-top: 10px;
  background: var(--surface-2); border: 1px solid var(--border); border-radius: 8px;
  padding: 10px 12px; font-size: 0.78rem;
}
.inspector .field { display: flex; flex-direction: column; gap: 2px; }
.inspector .field .k { color: var(--text-muted); font-size: 0.68rem; text-transform: uppercase; letter-spacing: .03em; }
.inspector .field .v { font-family: "SF Mono", Menlo, Consolas, monospace; font-size: 0.85rem; }
.region-badge {
  display: inline-block; padding: 2px 8px; border-radius: 20px; font-size: 0.7rem; color: #fff;
  font-weight: 600;
}
.hint { color: var(--text-muted); font-size: 0.72rem; margin-top: 8px; }
@media (max-width: 860px) {
  .main { flex-direction: column; }
  .minimap-col { width: 100%; }
  #minimap { width: 100%; height: 320px; }
}
</style>
<div class="wrap">
  <h1>Visualizador interactivo — VIT_EUR_{COUNTRY}.haftlt</h1>
  <p class="sub">Explora byte a byte el fichero real de radares de {COUNTRY_LABEL}. El formato interno no está descifrado (no hay coordenadas GPS decodificadas) — esto es una herramienta de inspección, no un mapa de cámaras.</p>

  <div class="toolbar">
    <div class="group">
      <label>Build</label>
      <button id="btn-old" class="active">{LABEL_OLD}</button>
      <button id="btn-new">{LABEL_NEW}</button>
    </div>
    <div class="sep"></div>
    <div class="group">
      <label>Ir a</label>
      <button data-jump="header">Cabecera</button>
      <button data-jump="index">Índice</button>
      <button data-jump="sec1">Sección 1</button>
      <button data-jump="mid_new">Región media (crece)</button>
      <button data-jump="sec234">Secc. 2–4</button>
      <button data-jump="tail_new">Región cola (crece)</button>
    </div>
    <div class="sep"></div>
    <div class="group">
      <label>Offset</label>
      <input type="text" id="offset-input" placeholder="0x0" />
      <button id="btn-go">Ir</button>
    </div>
  </div>

  <div class="main">
    <div class="minimap-col">
      <div class="minimap-frame">
        <canvas id="minimap" width="140" height="900"></canvas>
        <div id="viewport-marker"></div>
      </div>
      <div class="legend" id="legend"></div>
    </div>
    <div class="hex-col">
      <div class="hexbox" id="hexbox"></div>
      <div class="toolbar" style="margin-top:10px;">
        <button id="btn-prev">&larr; Página anterior</button>
        <button id="btn-next">Página siguiente &rarr;</button>
        <span class="hint" id="page-info"></span>
      </div>
      <div class="inspector" id="inspector"></div>
      <p class="hint">Click en el minimapa para saltar a esa zona del fichero. Click en un byte del hexdump para inspeccionar u8/u16/u32 (little-endian) en esa posición. Región candidata = zona que creció entre las dos builds reales (posible ubicación de cámaras nuevas); el resto está descartado o es ruido de renumeración de IDs — ver docs/haftlt_build_diff_260128.md para el análisis completo.</p>
    </div>
  </div>
</div>

<script>
const OLD_B64_CHUNKS = __OLD_JS__;
const NEW_B64_CHUNKS = __NEW_JS__;

const COLORS = {
  header:    [110,110,105],
  index:     [42,120,214],
  sec1:      [27,175,122],
  mid_same:  [48,48,46],
  mid_new:   [227,73,72],
  sec234:    [237,161,0],
  tail_same: [48,48,46],
  tail_new:  [235,104,52],
};
const LABELS = {
  header: "Cabecera", index: "Índice (descartada)", sec1: "Sección 1 (descartada)",
  mid_same: "Sin cambios", mid_new: "Región media — CANDIDATA (crece)",
  sec234: "Secc. 2–4 (ruido de renumeración)",
  tail_same: "Sin cambios", tail_new: "Región cola — CANDIDATA (crece)",
};

function b64ToBytes(chunks) {
  const bin = chunks.map(c => atob(c)).join('');
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function u32(bytes, off) {
  return bytes[off] | (bytes[off+1]<<8) | (bytes[off+2]<<16) | (bytes[off+3]<<24) >>> 0;
}

function buildRegions(bytes) {
  const sec1_start = u32(bytes, 0x94);
  const sec1_end   = u32(bytes, 0x98);
  const sec2_start = u32(bytes, 0x9c);
  const sec2_end   = u32(bytes, 0xa0);
  const sec3_end   = u32(bytes, 0xa8);
  const sec4_size  = u32(bytes, 0xac);
  const sec4_end   = sec3_end + sec4_size;
  return { sec1_start, sec1_end, sec2_start, sec2_end, sec3_end, sec4_end, size: bytes.length };
}

function commonPrefix(a, b, offA, offB, maxLen) {
  let p = 0;
  while (p < maxLen && a[offA+p] === b[offB+p]) p++;
  return p;
}
function commonSuffix(a, b, maxLen) {
  let s = 0;
  const la = a.length, lb = b.length;
  while (s < maxLen && a[la-1-s] === b[lb-1-s]) s++;
  return s;
}

let STATE = {};

function init() {
  const oldBytes = b64ToBytes(OLD_B64_CHUNKS);
  const newBytes = b64ToBytes(NEW_B64_CHUNKS);
  const oldR = buildRegions(oldBytes);
  const newR = buildRegions(newBytes);

  const midMaxLen = Math.min(oldR.sec2_start-oldR.sec1_end, newR.sec2_start-newR.sec1_end);
  const midPrefix = commonPrefix(oldBytes, newBytes, oldR.sec1_end, newR.sec1_end, midMaxLen);

  const tailMaxLen = Math.min(oldBytes.length-oldR.sec4_end, newBytes.length-newR.sec4_end);
  const tailSuffix = commonSuffix(
    oldBytes.subarray(oldR.sec4_end), newBytes.subarray(newR.sec4_end), tailMaxLen
  );

  STATE = {
    build: 'old',
    data: { old: { bytes: oldBytes, r: oldR }, new: { bytes: newBytes, r: newR } },
    midPrefix, tailSuffix,
    pageOffset: 0,
    pageSize: 512, // bytes per hex page (32 rows x 16)
    cursor: null,
  };

  renderLegend();
  renderMinimap();
  renderHexPage();
  bindUI();
}

function classify(offset, r, filelen) {
  if (offset < 0x200) return 'header';
  if (offset < r.sec1_start) return 'index';
  if (offset < r.sec1_end) return 'sec1';
  if (offset < r.sec2_start) {
    const rel = offset - r.sec1_end;
    return rel < STATE.midPrefix ? 'mid_same' : 'mid_new';
  }
  if (offset < r.sec4_end) return 'sec234';
  const relFromEnd = filelen - offset;
  return relFromEnd <= STATE.tailSuffix ? 'tail_same' : 'tail_new';
}

function current() { return STATE.data[STATE.build]; }

function renderLegend() {
  const el = document.getElementById('legend');
  el.innerHTML = Object.keys(COLORS).filter((k,i)=>['header','index','sec1','mid_new','sec234','tail_new'].includes(k) || k==='mid_same')
    .filter((v,i,a)=>a.indexOf(v)===i)
    .map(k => {
      const [r,g,b] = COLORS[k];
      return `<div class="item"><span class="sw" style="background:rgb(${r},${g},${b})"></span><span class="lbl">${LABELS[k]}</span></div>`;
    }).join('');
}

function renderMinimap() {
  const { bytes, r } = current();
  const canvas = document.getElementById('minimap');
  const width = canvas.width;
  const targetH = canvas.height;
  const n = bytes.length;
  const bytesPerPx = Math.max(1, Math.floor(n / (width*targetH)));
  const height = Math.ceil(n / (width*bytesPerPx));
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  const img = ctx.createImageData(width, height);
  const pxSize = width*bytesPerPx;

  for (let row = 0; row < height; row++) {
    const offStart = row*pxSize;
    const offRepresentative = Math.min(offStart, n-1);
    const cat = classify(offRepresentative, r, n);
    const [cr,cg,cb] = COLORS[cat];
    let sum = 0, cnt = 0;
    const end = Math.min(offStart+pxSize, n);
    for (let o = offStart; o < end; o += Math.max(1, Math.floor((end-offStart)/32))) { sum += bytes[o]; cnt++; }
    const gray = cnt ? (sum/cnt)*0.35 : 0;
    for (let col = 0; col < width; col++) {
      const idx = (row*width+col)*4;
      img.data[idx]   = Math.min(255, gray*0.25 + cr*0.75);
      img.data[idx+1] = Math.min(255, gray*0.25 + cg*0.75);
      img.data[idx+2] = Math.min(255, gray*0.25 + cb*0.75);
      img.data[idx+3] = 255;
    }
  }
  ctx.putImageData(img, 0, 0);
  STATE.minimapBytesPerRow = pxSize;
  updateViewportMarker();
}

function updateViewportMarker() {
  const canvas = document.getElementById('minimap');
  const marker = document.getElementById('viewport-marker');
  const rowH = canvas.clientHeight / canvas.height;
  const topRow = STATE.pageOffset / STATE.minimapBytesPerRow;
  const rows = Math.max(1, STATE.pageSize / STATE.minimapBytesPerRow);
  marker.style.top = (canvas.offsetTop + topRow*rowH) + 'px';
  marker.style.height = Math.max(2, rows*rowH) + 'px';
}

function byteColor(offset) {
  const { r, bytes } = current();
  const cat = classify(offset, r, bytes.length);
  return COLORS[cat];
}

function renderHexPage() {
  const { bytes, r } = current();
  const n = bytes.length;
  let start = Math.max(0, Math.min(STATE.pageOffset, n - 1));
  start = start - (start % 16);
  STATE.pageOffset = start;
  const rowsN = Math.ceil(STATE.pageSize/16);
  let html = '';
  for (let row = 0; row < rowsN; row++) {
    const rowOff = start + row*16;
    if (rowOff >= n) break;
    let hexPart = '';
    let asciiPart = '';
    for (let i = 0; i < 16; i++) {
      const off = rowOff + i;
      if (off >= n) { hexPart += '   '; continue; }
      const b = bytes[off];
      const [cr,cg,cb] = byteColor(off);
      const cursorCls = (STATE.cursor === off) ? ' cursor' : '';
      hexPart += `<span class="byte${cursorCls}" data-off="${off}" style="background:rgba(${cr},${cg},${cb},0.28)">${b.toString(16).padStart(2,'0')}</span> `;
      asciiPart += (b >= 32 && b < 127) ? String.fromCharCode(b) : '.';
    }
    html += `<div class="hexrow"><span class="off">0x${rowOff.toString(16).padStart(6,'0')}</span><span class="bytes">${hexPart}</span><span class="ascii">${asciiPart}</span></div>`;
  }
  document.getElementById('hexbox').innerHTML = html;
  document.getElementById('page-info').textContent =
    `0x${start.toString(16)} – 0x${Math.min(start+STATE.pageSize, n).toString(16)} de 0x${n.toString(16)} (${n.toLocaleString()} bytes)`;
  document.querySelectorAll('.byte').forEach(el => {
    el.addEventListener('click', () => {
      STATE.cursor = parseInt(el.dataset.off, 10);
      renderHexPage();
      renderInspector();
    });
  });
  updateViewportMarker();
  renderInspector();
}

function renderInspector() {
  const el = document.getElementById('inspector');
  const { bytes, r } = current();
  const off = STATE.cursor !== null ? STATE.cursor : STATE.pageOffset;
  const cat = classify(off, r, bytes.length);
  const [cr,cg,cb] = COLORS[cat];
  const u8 = bytes[off] ?? 0;
  const u16 = (off+1 < bytes.length) ? (bytes[off] | (bytes[off+1]<<8)) : null;
  const u32v = (off+3 < bytes.length) ? u32(bytes, off) : null;
  el.innerHTML = `
    <div class="field"><span class="k">Offset</span><span class="v">0x${off.toString(16).padStart(6,'0')} (${off})</span></div>
    <div class="field"><span class="k">Región</span><span class="v"><span class="region-badge" style="background:rgb(${cr},${cg},${cb})">${LABELS[cat]}</span></span></div>
    <div class="field"><span class="k">u8</span><span class="v">${u8} (0x${u8.toString(16)})</span></div>
    <div class="field"><span class="k">u16 LE</span><span class="v">${u16===null?'—':u16+' (0x'+u16.toString(16)+')'}</span></div>
    <div class="field"><span class="k">u32 LE</span><span class="v">${u32v===null?'—':u32v+' (0x'+u32v.toString(16)+')'}</span></div>
  `;
}

const JUMP_TARGETS = {
  header: () => 0,
  index: () => 0x200,
  sec1: (r) => r.sec1_start,
  mid_new: (r) => r.sec1_end + STATE.midPrefix,
  sec234: (r) => r.sec2_start,
  tail_new: (r) => r.sec4_end,
};

function bindUI() {
  document.getElementById('btn-old').addEventListener('click', () => switchBuild('old'));
  document.getElementById('btn-new').addEventListener('click', () => switchBuild('new'));
  document.getElementById('btn-prev').addEventListener('click', () => { STATE.pageOffset = Math.max(0, STATE.pageOffset - STATE.pageSize); STATE.cursor=null; renderHexPage(); });
  document.getElementById('btn-next').addEventListener('click', () => { STATE.pageOffset = STATE.pageOffset + STATE.pageSize; STATE.cursor=null; renderHexPage(); });
  document.getElementById('btn-go').addEventListener('click', goToOffsetInput);
  document.getElementById('offset-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') goToOffsetInput(); });
  document.querySelectorAll('[data-jump]').forEach(btn => {
    btn.addEventListener('click', () => {
      const { r } = current();
      const target = JUMP_TARGETS[btn.dataset.jump](r);
      STATE.pageOffset = target;
      STATE.cursor = target;
      renderHexPage();
    });
  });
  document.getElementById('minimap').addEventListener('click', (e) => {
    const canvas = document.getElementById('minimap');
    const rect = canvas.getBoundingClientRect();
    const yFrac = (e.clientY - rect.top) / rect.height;
    const row = Math.floor(yFrac * canvas.height);
    const off = row * STATE.minimapBytesPerRow;
    STATE.pageOffset = off;
    STATE.cursor = null;
    renderHexPage();
  });
}

function goToOffsetInput() {
  const raw = document.getElementById('offset-input').value.trim();
  if (!raw) return;
  const off = raw.toLowerCase().startsWith('0x') ? parseInt(raw, 16) : parseInt(raw, 10);
  if (Number.isNaN(off)) return;
  STATE.pageOffset = off;
  STATE.cursor = off;
  renderHexPage();
}

function switchBuild(which) {
  STATE.build = which;
  document.getElementById('btn-old').classList.toggle('active', which==='old');
  document.getElementById('btn-new').classList.toggle('active', which==='new');
  STATE.pageOffset = 0;
  STATE.cursor = null;
  renderMinimap();
  renderHexPage();
}

init();
</script>
"""


def b64_chunks(path, chunk=120000):
    with open(path, "rb") as f:
        raw = f.read()
    b64 = base64.b64encode(raw).decode("ascii")
    return [b64[i : i + chunk] for i in range(0, len(b64), chunk)]


def js_str_array(chunks):
    return "[\n" + ",\n".join(json.dumps(c) for c in chunks) + "\n]"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("old_file", help="Ruta al .haftlt de la build más antigua")
    ap.add_argument("new_file", help="Ruta al .haftlt de la build más nueva")
    ap.add_argument("--country", default="XXX", help="Código de país (p.ej. SPN, BEL, AUT)")
    ap.add_argument("--label-old", default="build antigua", help="Etiqueta del botón para la build antigua")
    ap.add_argument("--label-new", default="build nueva", help="Etiqueta del botón para la build nueva")
    ap.add_argument("-o", "--output", default="haftlt_viewer.html", help="Fichero HTML de salida")
    args = ap.parse_args()

    old_js = js_str_array(b64_chunks(args.old_file))
    new_js = js_str_array(b64_chunks(args.new_file))

    html = (
        HTML_TEMPLATE.replace("{COUNTRY}", args.country)
        .replace("{COUNTRY_LABEL}", args.country)
        .replace("{LABEL_OLD}", args.label_old)
        .replace("{LABEL_NEW}", args.label_new)
        .replace("__OLD_JS__", old_js)
        .replace("__NEW_JS__", new_js)
    )

    with open(args.output, "w") as f:
        f.write(html)

    print(f"Escrito {args.output} ({len(html):,} bytes)", file=sys.stderr)
    print("AVISO: este HTML embebe ambos ficheros .haftlt en base64 (datos propietarios HERE).", file=sys.stderr)
    print("No lo commitees al repositorio. Uso solo local / Artifact efimero.", file=sys.stderr)


if __name__ == "__main__":
    main()
