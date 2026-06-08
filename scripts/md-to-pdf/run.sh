#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_MD_PATH:?INPUT_MD_PATH not set}"

if [[ ! -f "$INPUT_MD_PATH" ]]; then
  printf 'ERROR: Markdown file not found: %s\n' "$INPUT_MD_PATH" >&2
  exit 2
fi

# Ausgabepfad: explizit oder neben der MD-Datei
if [[ -n "${INPUT_OUTPUT_PATH:-}" ]]; then
  pdf_out="$INPUT_OUTPUT_PATH"
else
  pdf_out="${INPUT_MD_PATH%.md}.pdf"
fi

html_tmp="${TOOLS_MCP_RUN_DIR}/converted.html"

# Python-Auswahl plattformrobust:
#   1. macOS arm64 mit /opt/homebrew Python + Pango/Cairo  → nativ arm64 (bevorzugt)
#   2. macOS mit nur Intel-Brew unter /usr/local         → arch -x86_64 python3
#      (SIP strippt DYLD_* bei /usr/bin/python3 — siehe (1) als saubere Lösung)
#   3. Linux                                              → python3
PY=(python3)
if [[ "$(uname -s)" == "Darwin" ]]; then
  if [[ -x "/opt/homebrew/bin/python3.12" && -e "/opt/homebrew/lib/libgobject-2.0.dylib" ]]; then
    PY=(/opt/homebrew/bin/python3.12)
  elif [[ -d "/usr/local/lib" ]] && command -v arch >/dev/null 2>&1; then
    PY=(arch -x86_64 python3)
  fi
fi

DESIGN="${INPUT_DESIGN:-collana}"

"${PY[@]}" - "$INPUT_MD_PATH" "$html_tmp" "$DESIGN" << 'PYEOF'
import sys, re, html as html_lib, pathlib, markdown

md_path = pathlib.Path(sys.argv[1])
html_out = pathlib.Path(sys.argv[2])
design = sys.argv[3]

md_text = md_path.read_text(encoding="utf-8")

# YAML-Frontmatter parsen (minimal, ohne PyYAML-Dependency).
# Erkennt einen `---`-Block am Anfang der Datei, Zeilen `key: value`.
# Werte in '...' oder "..." werden entquoted. Komplexe Strukturen (Listen,
# Maps) werden nicht unterstützt — für die paar Header-Felder reicht das.
frontmatter = {}
fm_match = re.match(r'^---\s*\n(.*?)\n(?:---|\.\.\.)\s*\n', md_text, re.DOTALL)
if fm_match:
    md_text = md_text[fm_match.end():]
    for line in fm_match.group(1).splitlines():
        line = line.rstrip()
        if not line or line.lstrip().startswith('#'):
            continue
        kv = re.match(r'\s*([A-Za-z_][A-Za-z0-9_-]*)\s*:\s*(.*)$', line)
        if not kv:
            continue
        key, val = kv.group(1), kv.group(2).strip()
        if len(val) >= 2 and ((val[0] == val[-1] == '"') or (val[0] == val[-1] == "'")):
            val = val[1:-1]
        frontmatter[key] = val

# Kein nl2br: weiche Zeilenumbrueche (Soft-Wraps) im Markdown duerfen NICHT zu harten
# <br> werden — sonst bricht der Fliesstext mitten im Absatz/Blockquote um. Gewollte
# Umbrueche bleiben ueber literale <br/>-Tags im Markdown erhalten.
html_body = markdown.markdown(md_text, extensions=["tables", "fenced_code"])

# Breite Tabellen (viele Spalten) in einen .wide-table-Container packen — das
# Design kann sie dann auf eine Querformat-Seite legen, damit die Spalten genug
# Platz bekommen (sonst extreme Silbentrennung in schmalen Hochformat-Spalten).
def wrap_wide_tables(html, min_cols=5):
    # Breite Tabellen (viele Spalten) markieren, damit das Design ihnen mehr Breite
    # geben kann (volle Seitenbreite + kleinere Schrift), ohne Seiten ins Querformat
    # zu kippen.
    def repl(m):
        table = m.group(0)
        first_row = re.search(r'<tr>(.*?)</tr>', table, re.DOTALL)
        ncols = len(re.findall(r'<t[hd][ >]', first_row.group(1))) if first_row else 0
        return f'<div class="wide-table">{table}</div>' if ncols >= min_cols else table
    return re.sub(r'<table\b[^>]*>.*?</table>', repl, html, flags=re.DOTALL)

html_body = wrap_wide_tables(html_body)

def render_title_block(fm, design):
    # Deutsche und englische Keys akzeptieren (erster Treffer gewinnt).
    def pick(*keys):
        for k in keys:
            v = fm.get(k)
            if v:
                return v
        return ""
    title_raw = pick("title", "titel")
    if not title_raw:
        return ""
    esc = lambda s: html_lib.escape(s, quote=False)
    title = esc(title_raw)
    subtitle = esc(pick("subtitle", "untertitel"))
    author = esc(pick("author", "autor", "patient"))
    date = esc(pick("date", "datum", "stand"))
    # Author und Date in einer Zeile, mit Bullet getrennt wenn beide da.
    meta_parts = [p for p in (author, date) if p]
    meta = "  ·  ".join(meta_parts)
    parts = [f'<div class="title-block design-{design}">']
    parts.append(f'<div class="doc-title">{title}</div>')
    if subtitle:
        parts.append(f'<div class="doc-subtitle">{subtitle}</div>')
    if meta:
        parts.append(f'<div class="doc-meta">{meta}</div>')
    parts.append('</div>')
    return "\n".join(parts)

title_block_html = render_title_block(frontmatter, design)

DESIGNS = {
    "collana": """
  @page { margin: 2cm 2.5cm; }
  body {
    font-family: 'Segoe UI', Arial, sans-serif;
    font-size: 11pt; line-height: 1.6; color: #1a1a1a; margin: 0;
  }
  .title-block.design-collana { margin: 0 0 24pt 0; padding-bottom: 14pt; border-bottom: 2px solid #fa4a05; }
  .title-block.design-collana .doc-title { font-size: 24pt; font-weight: bold; color: #0f172a; line-height: 1.2; margin-bottom: 4pt; }
  .title-block.design-collana .doc-subtitle { font-size: 13pt; color: #bc3704; font-style: italic; margin-bottom: 8pt; }
  .title-block.design-collana .doc-meta { font-size: 10pt; color: #4b5563; }
  h1 { font-size: 18pt; color: #0f172a; border-bottom: 2px solid #fa4a05; padding-bottom: 6px; margin-top: 0; }
  h2 { font-size: 14pt; color: #0f172a; border-bottom: 1px solid #d1d5db; padding-bottom: 4px; margin-top: 24px; }
  h3 { font-size: 11pt; color: #bc3704; margin-top: 16px; }
  code { background: #f3f4f6; padding: 2px 5px; border-radius: 3px; font-size: 9pt; font-family: 'Courier New', monospace; }
  pre { background: #f3f4f6; padding: 12px; border-radius: 4px; border-left: 3px solid #fa4a05; font-size: 9pt; white-space: pre-wrap; }
  table { border-collapse: collapse; width: 100%; margin: 12px 0; font-size: 10pt; }
  th { background: #bc3704; color: #fff; padding: 7px 10px; text-align: left; }
  td { padding: 6px 10px; border-bottom: 1px solid #e5e7eb; }
  tr:nth-child(even) td { background: #f9fafb; }
  blockquote { border-left: 3px solid #fa4a05; margin: 10px 0; padding: 6px 14px; color: #4b5563; font-style: italic; background: #fef1ea; }
  hr { border: none; border-top: 1px solid #e5e7eb; margin: 20px 0; }
  ul, ol { margin: 6px 0; padding-left: 22px; }
  li { margin: 3px 0; }
  strong { color: #0f172a; }
  a { color: #bc3704; }
""",
    # magicM: TeX/LaTeX-inspirierte Computer-Modern-Serife (Typografie wie gehabt),
    # Akzentfarben an das magic3-Theme angeglichen (grüner Akzent #388E3C, Tinte #333/#000/#666).
    # Seitennummerierung mittig im Footer ("3 / 12").
    "magicM": """
  @page {
    size: A4 portrait;
    margin: 2.5cm 2.8cm 2.2cm 2.8cm;
    @bottom-center {
      content: counter(page) " / " counter(pages);
      font-family: 'Latin Modern Roman', 'CMU Serif', 'TeX Gyre Termes', Georgia, 'Times New Roman', serif;
      font-size: 9pt;
      color: #666666;
    }
  }
  /* Breite Tabellen (>=5 Spalten) nutzen die volle Seitenbreite (in die Ränder
     hineingezogen) plus kleinere Schrift/engeres Padding — so haben die Spalten im
     Hochformat genug Platz, ohne Seiten ins Querformat zu kippen. */
  .wide-table { margin-left: -1.8cm; margin-right: -1.8cm; }
  .wide-table table { font-size: 8.5pt; width: 100%; }
  .wide-table th, .wide-table td { padding: 4px 7px; }
  body {
    font-family: 'Latin Modern Roman', 'CMU Serif', 'TeX Gyre Termes', Georgia, 'Times New Roman', serif;
    font-size: 11pt; line-height: 1.55; color: #333333; margin: 0;
    text-align: justify;
    hyphens: auto;
  }
  /* LaTeX-\\maketitle-Look: zentriert; Akzent über Farbe statt Linien. */
  .title-block.design-magicM { text-align: center; margin: 0 0 28pt 0; }
  .title-block.design-magicM .doc-title { font-size: 22pt; font-weight: bold; color: #000000; line-height: 1.2; letter-spacing: 0.02em; margin-bottom: 6pt; }
  .title-block.design-magicM .doc-subtitle { font-size: 14pt; font-style: italic; color: #2E7D32; margin-bottom: 12pt; }
  .title-block.design-magicM .doc-meta { font-size: 11pt; color: #666666; }
  h1 { font-size: 20pt; color: #000000; margin-top: 0; margin-bottom: 12pt; text-align: center; font-weight: bold; letter-spacing: 0.02em; }
  h2 { font-size: 14pt; color: #000000; margin-top: 22px; margin-bottom: 6px; font-weight: bold; padding-left: 8px; border-left: 4px solid #388E3C; text-align: left; }
  h3 { font-size: 12pt; color: #333333; margin-top: 16px; margin-bottom: 4px; font-style: italic; font-weight: normal; text-align: left; }
  p { margin: 0 0 8pt 0; text-indent: 1.2em; }
  /* Erster Absatz nach Überschriften ohne Einzug (LaTeX-Konvention). */
  h1 + p, h2 + p, h3 + p, blockquote + p { text-indent: 0; }
  code { font-family: 'Latin Modern Mono', 'CMU Typewriter Text', 'Courier New', monospace; font-size: 10pt; background: #f5f5f5; padding: 1px 4px; border-radius: 2px; }
  pre { font-family: 'Latin Modern Mono', 'CMU Typewriter Text', 'Courier New', monospace; font-size: 9.5pt; background: #f8f8f8; padding: 10px 12px; border: 1px solid #ECECEC; white-space: pre-wrap; }
  pre code { background: transparent; padding: 0; }
  /* Spaltenbreite richtet sich nach dem Inhalt: auto-Layout, Tabelle nur so breit
     wie nötig (max. Seitenbreite) — keine gleichmäßige Aufblähung kurzer Spalten. */
  table { border-collapse: collapse; width: auto; max-width: 100%; table-layout: auto; margin: 14px 0; font-size: 10.5pt; }
  /* Booktabs-Stil: nur waagerechte Linien, keine Vertikalen. */
  /* Zellen linksbündig (kein geerbter Blocksatz), oben ausgerichtet; lange Inhalte
     umbrechen statt die Spalte zu verbreitern. */
  th, td { text-align: left; vertical-align: top; overflow-wrap: break-word; word-break: normal; hyphens: auto; }
  th { border-top: 1.2pt solid #000; border-bottom: 0.6pt solid #000; padding: 6px 10px; font-weight: bold; background: transparent; }
  td { padding: 5px 10px; border-bottom: 0; }
  table tr:last-child td { border-bottom: 1.2pt solid #000; }
  tr:nth-child(even) td { background: transparent; }
  blockquote { border-left: 4px solid #388E3C; margin: 10px 0 10px 16px; padding: 2px 12px; color: #333333; font-style: italic; background: transparent; }
  hr { border: none; border-top: 0.5pt solid #D0D0D0; margin: 16px 0; }
  ul, ol { margin: 6px 0; padding-left: 24px; }
  li { margin: 2px 0; }
  strong { color: #000000; font-weight: bold; }
  em { font-style: italic; }
  a { color: #2E7D32; text-decoration: none; }
""",
}
if design not in DESIGNS:
    print(f"WARN: unbekanntes design '{design}', fallback auf 'collana'", file=sys.stderr)
    design = "collana"

css = DESIGNS[design]

html = f"""<!DOCTYPE html>
<html lang="de">
<head>
<meta charset="UTF-8">
<style>{css}</style>
</head>
<body>
{title_block_html}
{html_body}
</body>
</html>"""

html_out.write_text(html, encoding="utf-8")
print(f"HTML written ({design}): {html_out}")
PYEOF

"${PY[@]}" -c "
import sys, site
# Fallback: per-user site-packages in den sys.path, falls WeasyPrint dort
# (pip install --user) liegt und noch nicht sichtbar ist.
try:
    usp = site.getusersitepackages()
    if usp and usp not in sys.path:
        sys.path.insert(0, usp)
except Exception:
    pass
from weasyprint import HTML
HTML(filename='$html_tmp').write_pdf('$pdf_out')
print('PDF written: $pdf_out')
"

# Plattformrobustes Filesize (GNU stat vs. BSD stat)
if size=$(stat -c%s "$pdf_out" 2>/dev/null); then :
else size=$(stat -f%z "$pdf_out"); fi

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" << EOF
{
  "pdf_path": "${pdf_out}",
  "size_bytes": ${size}
}
EOF

printf 'PDF erstellt: %s (%d Bytes)\n' "$pdf_out" "$size"
