#!/usr/bin/env python3
"""Genera una página HTML autocontenida para inspeccionar los assets visuales
de renderizado del mapa HERE (ver docs/rendering_visual_assets.md):

  - VIT_EUR_CE_THEME_IMAGE.bin  -> atlas de texturas RGB/RGBA sin comprimir
  - VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma -> imágenes WebP de guiado de salida
  - VIT_EUR_3D_LANDMARK_ASTC.hafmma -> texturas ASTC de fachadas de landmarks 3D

Trabaja directamente sobre el ZIP de mapas (no hace falta extraer nada a mano).
"""
import argparse
import base64
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import zipfile

from PIL import Image

THEME_IMAGE_PATH = "Data/Nation/EUR/RES/SKIN/VIT_EUR_CE_THEME_IMAGE.bin"
RENDERING_PATHS = {
    "LATTE": "Data/Nation/EUR/MAP/VIT_EUR_Rendering_LATTE.hafmma",
    "MILK": "Data/Nation/EUR/MAP/VIT_EUR_Rendering_MILK.hafmma",
    "MOCHA": "Data/Nation/EUR/MAP/VIT_EUR_Rendering_MOCHA.hafmma",
}
LANDMARK_ASTC_PATH = "Data/Nation/EUR/MAP/VIT_EUR_3D_LANDMARK_ASTC.hafmma"

GL_FORMAT_NAMES = {6407: "GL_RGB", 6408: "GL_RGBA"}
ASTC_MAGIC = bytes([0x13, 0xAB, 0xA1, 0x5C])

ASTCENC_CANDIDATES = [
    "astcenc", "astcenc-native", "astcenc-avx2", "astcenc-sse4.1",
    "astcenc-sse2", "astcenc-neon",
]


def find_astcenc(explicit):
    if explicit:
        return explicit
    for name in ASTCENC_CANDIDATES:
        path = shutil.which(name)
        if path:
            return path
    return None


def read_zip_entry(zf, path, max_bytes=None):
    with zf.open(path) as f:
        return f.read(max_bytes) if max_bytes else f.read()


# --- VIT_EUR_CE_THEME_IMAGE.bin: atlas de texturas (ver docs/rendering_visual_assets.md #2) ---

def parse_theme_atlas(data, limit=None):
    """Índice de 64 B/registro -> [seq, size, data_offset]; cada textura tiene
    cabecera de 32 B con enums reales de OpenGL (GL_RGB=6407 / GL_RGBA=6408)."""
    count = struct.unpack_from("<I", data, 0)[0]
    records = []
    for i in range(count):
        off = 0x10 + i * 64
        if off + 64 > len(data):
            break
        vals = struct.unpack_from("<16I", data, off)
        seq, size, _pad, dataoff = vals[2], vals[3], vals[4], vals[5]
        records.append((seq, size, dataoff))

    results = []
    for seq, size, dataoff in (records[:limit] if limit else records):
        if dataoff + 32 > len(data):
            continue
        magicA, magicB, w, h, ch, miplevels, fmt1, _fmt2 = struct.unpack_from(
            "<8I", data, dataoff
        )
        if magicA != 0x30 or magicB != 0x31 or ch not in (3, 4):
            continue
        n = w * h * ch
        payload_start = dataoff + 32
        pixels = data[payload_start:payload_start + n]
        if len(pixels) != n or w == 0 or h == 0:
            continue
        mode = "RGB" if ch == 3 else "RGBA"
        try:
            im = Image.frombytes(mode, (w, h), pixels)
        except Exception:
            continue
        buf = io.BytesIO()
        im.save(buf, format="PNG")
        results.append({
            "seq": seq, "w": w, "h": h, "channels": ch,
            "gl_format": GL_FORMAT_NAMES.get(fmt1, f"0x{fmt1:x}"),
            "mip_levels": miplevels, "size": size,
            "png_b64": base64.b64encode(buf.getvalue()).decode(),
        })
    return results


# --- VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma: guiado WebP (ver docs #3) ---

def extract_webp_images(data, limit=None):
    positions = [m.start() for m in re.finditer(b"RIFF", data)]
    results = []
    for idx, p in enumerate(positions[:limit] if limit else positions):
        if p + 8 > len(data):
            continue
        size = struct.unpack_from("<I", data, p + 4)[0]
        chunk = data[p:p + size + 8]
        try:
            im = Image.open(io.BytesIO(chunk))
            im.load()
        except Exception:
            continue
        has_alpha = im.mode in ("RGBA", "LA") and im.convert("RGBA").getchannel("A").getextrema() != (255, 255)
        buf = io.BytesIO()
        im.convert("RGBA").save(buf, format="PNG")
        results.append({
            "idx": idx, "w": im.size[0], "h": im.size[1],
            "has_alpha": has_alpha,
            "png_b64": base64.b64encode(buf.getvalue()).decode(),
        })
    return results


# --- VIT_EUR_3D_LANDMARK_ASTC.hafmma: texturas ASTC de landmarks (ver docs #4b) ---

def extract_astc_images(data, astcenc_bin, limit=None, min_size=128):
    positions = [m.start() for m in re.finditer(re.escape(ASTC_MAGIC), data)]
    results = []
    count = 0
    for p in positions:
        if limit and count >= limit:
            break
        hdr = data[p:p + 16]
        if len(hdr) < 16:
            continue
        bx, by, bz = hdr[4], hdr[5], hdr[6]
        xsize = hdr[7] | (hdr[8] << 8) | (hdr[9] << 16)
        ysize = hdr[10] | (hdr[11] << 8) | (hdr[12] << 16)
        zsize = hdr[13] | (hdr[14] << 8) | (hdr[15] << 16)
        if xsize < min_size or ysize < min_size or zsize != 1 or bx == 0 or by == 0:
            continue
        blocks_x = (xsize + bx - 1) // bx
        blocks_y = (ysize + by - 1) // by
        total = 16 + blocks_x * blocks_y * 16
        chunk = data[p:p + total]
        if len(chunk) != total:
            continue

        entry = {"idx": count, "w": xsize, "h": ysize, "block": f"{bx}x{by}", "png_b64": None}
        if astcenc_bin:
            with tempfile.TemporaryDirectory() as td:
                astc_path = os.path.join(td, "t.astc")
                png_path = os.path.join(td, "t.png")
                with open(astc_path, "wb") as f:
                    f.write(chunk)
                r = subprocess.run(
                    [astcenc_bin, "-dl", astc_path, png_path],
                    capture_output=True,
                )
                if r.returncode == 0 and os.path.exists(png_path):
                    with open(png_path, "rb") as f:
                        entry["png_b64"] = base64.b64encode(f.read()).decode()
        results.append(entry)
        count += 1
    return results


# --- HTML ---

def html_escape(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def build_html(theme_textures, webp_by_theme, astc_images, astcenc_available):
    parts = []
    parts.append("""<!doctype html><html><head><meta charset="utf-8">
<title>Map render viewer — Rio MY22 EU</title>
<style>
:root { color-scheme: dark; }
body { background:#111317; color:#e6e6e6; font-family: -apple-system, "Segoe UI", sans-serif; margin:0; }
header { padding:16px 24px; background:#181b20; border-bottom:1px solid #2a2e35; position:sticky; top:0; z-index:10; }
header h1 { font-size:16px; margin:0 0 4px; }
header p { margin:0; font-size:12px; color:#9aa0a8; }
nav { display:flex; gap:8px; padding:10px 24px; background:#14161a; border-bottom:1px solid #2a2e35; }
nav button { background:#22262e; color:#e6e6e6; border:1px solid #33383f; border-radius:6px; padding:6px 14px; font-size:13px; cursor:pointer; }
nav button.active { background:#3a6ff0; border-color:#3a6ff0; }
section { display:none; padding:20px 24px; }
section.active { display:block; }
.grid { display:grid; grid-template-columns: repeat(auto-fill, minmax(140px, 1fr)); gap:14px; }
.card { background:#1b1e24; border:1px solid #2a2e35; border-radius:8px; overflow:hidden; }
.card .thumb { display:flex; align-items:center; justify-content:center; background:
   repeating-conic-gradient(#26292f 0% 25%, #1b1e24 0% 50%) 50% / 16px 16px; min-height:90px; }
.card img { max-width:100%; max-height:160px; display:block; }
.card .meta { padding:6px 8px; font-size:11px; color:#9aa0a8; line-height:1.5; }
.card .meta b { color:#e6e6e6; }
.missing { padding:10px; font-size:11px; color:#6a6f78; text-align:center; }
.note { background:#22262e; border:1px solid #33383f; border-radius:8px; padding:12px 16px; font-size:13px; color:#c7ccd3; margin-bottom:16px; }
.note code { background:#14161a; padding:1px 5px; border-radius:4px; }
.theme-toggle { display:flex; gap:6px; margin-bottom:14px; }
.theme-toggle button { background:#22262e; color:#e6e6e6; border:1px solid #33383f; border-radius:6px; padding:5px 12px; font-size:12px; cursor:pointer; }
.theme-toggle button.active { background:#5a8f3c; border-color:#5a8f3c; }
.theme-pane { display:none; }
.theme-pane.active { display:block; }
</style></head><body>
<header>
  <h1>Map render viewer — Rio MY22 EU</h1>
  <p>Assets visuales de renderizado extraídos del paquete de mapas HERE. Ver docs/rendering_visual_assets.md para el detalle del formato de cada fichero.</p>
</header>
<nav>
  <button class="active" onclick="showTab('webp')">Guiado de salida (WebP)</button>
  <button onclick="showTab('atlas')">Atlas de texturas UI (RGB/RGBA)</button>
  <button onclick="showTab('astc')">Landmarks 3D (ASTC)</button>
</nav>
""")

    # --- WebP junction guidance section ---
    parts.append('<section id="webp" class="active">')
    parts.append('<div class="note">Ilustraciones esquemáticas 3D de bifurcación/salida de autopista (panel de "próxima maniobra"), embebidas como WebP en <code>VIT_EUR_Rendering_{LATTE,MILK,MOCHA}.hafmma</code>. Mismo índice de imagen = misma escena en distinta paleta de luminosidad.</div>')
    themes = [t for t in ("LATTE", "MILK", "MOCHA") if t in webp_by_theme]
    parts.append('<div class="theme-toggle">')
    for i, t in enumerate(themes):
        cls = "active" if i == 0 else ""
        parts.append(f'<button class="{cls}" onclick="showTheme(\'{t}\')">{t} ({len(webp_by_theme[t])})</button>')
    parts.append('</div>')
    for i, t in enumerate(themes):
        cls = "theme-pane active" if i == 0 else "theme-pane"
        parts.append(f'<div class="theme-pane {cls}" id="theme-{t}"><div class="grid">')
        for img in webp_by_theme[t]:
            alpha_note = " · alfa" if img["has_alpha"] else ""
            parts.append(
                f'<div class="card"><div class="thumb"><img src="data:image/png;base64,{img["png_b64"]}" loading="lazy"></div>'
                f'<div class="meta">#{img["idx"]:03d} · {img["w"]}×{img["h"]}{alpha_note}</div></div>'
            )
        parts.append('</div></div>')
    parts.append('</section>')

    # --- Theme atlas section ---
    parts.append('<section id="atlas">')
    parts.append(f'<div class="note">Atlas de texturas sin comprimir de <code>VIT_EUR_CE_THEME_IMAGE.bin</code> — cada entrada declara su formato real de OpenGL en la cabecera (<code>GL_RGB</code>/<code>GL_RGBA</code>) y una cadena de mipmaps completa hasta 1×1. Mostrando {len(theme_textures)} texturas (nivel base, sin mips).</div>')
    parts.append('<div class="grid">')
    for tex in theme_textures:
        parts.append(
            f'<div class="card"><div class="thumb"><img src="data:image/png;base64,{tex["png_b64"]}" loading="lazy"></div>'
            f'<div class="meta">#{tex["seq"]} · <b>{tex["w"]}×{tex["h"]}</b><br>{tex["gl_format"]} · {tex["mip_levels"]} mips</div></div>'
        )
    parts.append('</div></section>')

    # --- ASTC landmark section ---
    parts.append('<section id="astc">')
    if astcenc_available:
        note = f'<div class="note">Texturas ASTC reales de <code>VIT_EUR_3D_LANDMARK_ASTC.hafmma</code> (fachadas de edificios landmark), decodificadas con <code>astcenc -dl</code>. Mostrando {len(astc_images)} texturas base (256×256 o mayor, sin mips).</div>'
    else:
        note = ('<div class="note">⚠️ No se encontró un binario <code>astcenc</code> en <code>PATH</code> — se listan las texturas ASTC localizadas '
                'pero sin decodificar. Compila <a href="https://github.com/ARM-software/astc-encoder" style="color:#7fb0ff">ARM-software/astc-encoder</a> '
                '(<code>cmake -B build &amp;&amp; cmake --build build</code>) y vuelve a ejecutar con <code>--astcenc ruta/al/binario</code>.</div>')
    parts.append(note)
    parts.append('<div class="grid">')
    for tex in astc_images:
        if tex["png_b64"]:
            body = f'<div class="thumb"><img src="data:image/png;base64,{tex["png_b64"]}" loading="lazy"></div>'
        else:
            body = f'<div class="missing">ASTC {tex["block"]}<br>sin decodificar</div>'
        parts.append(
            f'<div class="card">{body}<div class="meta">#{tex["idx"]} · {tex["w"]}×{tex["h"]} · bloque {tex["block"]}</div></div>'
        )
    parts.append('</div></section>')

    parts.append("""
<script>
function showTab(id) {
  document.querySelectorAll('nav button').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('section').forEach(s => s.classList.remove('active'));
  document.getElementById(id).classList.add('active');
  event.target.classList.add('active');
}
function showTheme(t) {
  document.querySelectorAll('.theme-toggle button').forEach(b => b.classList.remove('active'));
  document.querySelectorAll('.theme-pane').forEach(p => p.classList.remove('active'));
  document.getElementById('theme-' + t).classList.add('active');
  event.target.classList.add('active');
}
</script>
</body></html>""")
    return "".join(parts)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip", required=True, help="Ruta al ZIP de mapas (S5W_MAP_ALL_EUR_*.zip)")
    ap.add_argument("--themes", default="LATTE,MILK,MOCHA", help="Temas de guiado WebP a incluir (coma-separado)")
    ap.add_argument("--textures-limit", type=int, default=80, help="Máx. texturas del atlas RGB/RGBA a decodificar (0 = todas, ~420)")
    ap.add_argument("--astc-limit", type=int, default=15, help="Máx. texturas ASTC a decodificar (subprocess por textura, es lento)")
    ap.add_argument("--astc-sample-mb", type=int, default=10, help="MB a leer de VIT_EUR_3D_LANDMARK_ASTC.hafmma (379 MB completos; no hace falta leerlo entero)")
    ap.add_argument("--astcenc", default=None, help="Ruta explícita al binario astcenc (si no, se busca en PATH)")
    ap.add_argument("--skip-astc", action="store_true", help="No procesar el fichero ASTC (es el más grande, ahorra tiempo)")
    ap.add_argument("-o", "--output", default="map_render_viewer.html")
    args = ap.parse_args()

    astcenc_bin = None if args.skip_astc else find_astcenc(args.astcenc)
    if not args.skip_astc and not astcenc_bin:
        print("aviso: no se encontró astcenc en PATH -- las texturas ASTC se listarán sin decodificar", file=sys.stderr)

    print(f"Abriendo {args.zip} ...", file=sys.stderr)
    zf = zipfile.ZipFile(args.zip)

    print("Extrayendo atlas de texturas UI (VIT_EUR_CE_THEME_IMAGE.bin) ...", file=sys.stderr)
    theme_data = read_zip_entry(zf, THEME_IMAGE_PATH)
    limit = None if args.textures_limit == 0 else args.textures_limit
    theme_textures = parse_theme_atlas(theme_data, limit=limit)
    print(f"  {len(theme_textures)} texturas decodificadas", file=sys.stderr)
    del theme_data

    webp_by_theme = {}
    for theme in [t.strip().upper() for t in args.themes.split(",") if t.strip()]:
        path = RENDERING_PATHS.get(theme)
        if not path:
            print(f"aviso: tema desconocido '{theme}', ignorado", file=sys.stderr)
            continue
        print(f"Extrayendo guiado WebP ({theme}) ...", file=sys.stderr)
        data = read_zip_entry(zf, path)
        imgs = extract_webp_images(data)
        webp_by_theme[theme] = imgs
        print(f"  {len(imgs)} imágenes WebP", file=sys.stderr)

    astc_images = []
    if not args.skip_astc:
        print(f"Muestreando {args.astc_sample_mb} MB de VIT_EUR_3D_LANDMARK_ASTC.hafmma ...", file=sys.stderr)
        with zf.open(LANDMARK_ASTC_PATH) as f:
            astc_data = f.read(args.astc_sample_mb * 1024 * 1024)
        astc_images = extract_astc_images(astc_data, astcenc_bin, limit=args.astc_limit)
        decoded = sum(1 for t in astc_images if t["png_b64"])
        print(f"  {len(astc_images)} texturas ASTC localizadas, {decoded} decodificadas", file=sys.stderr)

    zf.close()

    html = build_html(theme_textures, webp_by_theme, astc_images, astcenc_bin is not None)
    with open(args.output, "w") as f:
        f.write(html)
    print(f"\nEscrito {args.output} ({len(html)/1024:.0f} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
