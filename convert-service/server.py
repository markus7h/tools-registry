#!/usr/bin/env python3
"""Zentraler Konvertier-Dienst (Container).

Datei rein (roher Request-Body) -> Datei raus (Response-Body). Bündelt die
schweren Helfer (chromium, libreoffice, weasyprint, pandoc, poppler), damit die
tools-registry-Clients nur curl brauchen.

# ponytail: stdlib ThreadingHTTPServer reicht; echtes WSGI/uvicorn erst wenn Last es verlangt.
"""
import os
import re
import sys
import html as html_lib
import shutil
import subprocess
import tempfile
import pathlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

HERE = pathlib.Path(__file__).resolve().parent
THEME_CSS = (HERE / "theme.css").read_text(encoding="utf-8")

PORT = int(os.environ.get("PORT", "3458"))
HOST = os.environ.get("HOST", "0.0.0.0")
TOKEN = os.environ.get("CONVERT_TOKEN", "")
MAX_BODY = int(os.environ.get("CONVERT_MAX_BODY", str(100 * 1024 * 1024)))  # 100 MB
TIMEOUT = int(os.environ.get("CONVERT_TIMEOUT", "120"))
CHROME = os.environ.get("CHROME_BIN") or shutil.which("chromium") or shutil.which("chromium-browser") or "chromium"


def run(cmd, **kw):
    kw.setdefault("timeout", TIMEOUT)
    kw.setdefault("capture_output", True)
    return subprocess.run(cmd, check=True, **kw)


# ---------------------------------------------------------------- html -> pdf
def magic3_inject(html: str) -> str:
    """magic3-Look in beliebiges HTML injizieren: helle Flächen, grüner Akzent,
    Mermaid-Hintergrund hell. Greift sauber bei neutralem/hand-getyptem HTML;
    überschreibt zusätzlich gängige Theme-Variablennamen (--bg/--panel/--border/…),
    sodass auch viele dunkle Eigen-Themes hell werden."""
    inject = (
        "<style>" + THEME_CSS + "</style>\n"
        "<style>\n"
        ":root{--bg:#FFFFFF!important;--background:#FFFFFF!important;--panel:#FFFFFF!important;"
        "--surface:#FFFFFF!important;--card:#FFFFFF!important;--border:#ECECEC!important;"
        "--fg:#333333!important;--text:#333333!important;--foreground:#333333!important;"
        "--muted:#666666!important;--accent:#388E3C!important;--primary:#388E3C!important;"
        "--ok:#2E7D32!important;--good:#2E7D32!important;--warn:#DD3333!important;--bad:#DD3333!important;}\n"
        "html,body{background:#FAFAFA!important;color:#333333!important;"
        "font-family:'Source Sans 3','Source Sans Pro',Arial,sans-serif!important;}\n"
        "@media print{*{-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important;}}\n"
        "@page{size:A4;margin:14mm;}\n"
        "</style>\n"
    )
    if re.search(r"</head>", html, re.IGNORECASE):
        return re.sub(r"</head>", inject + "</head>", html, count=1, flags=re.IGNORECASE)
    return inject + html


def html_to_pdf(body: bytes, q) -> tuple[bytes, dict]:
    theme = (q.get("theme", ["none"])[0] or "none").lower()
    landscape = (q.get("landscape", ["false"])[0] or "false").lower() == "true"
    wait_ms = int(q.get("wait_ms", ["4000"])[0] or "4000")
    html = body.decode("utf-8", errors="replace")
    if theme == "magic3":
        html = magic3_inject(html)
    with tempfile.TemporaryDirectory() as d:
        page = pathlib.Path(d) / "page.html"
        out = pathlib.Path(d) / "out.pdf"
        page.write_text(html, encoding="utf-8")
        cmd = [
            CHROME, "--headless=new", "--no-sandbox", "--disable-gpu", "--hide-scrollbars",
            f"--user-data-dir={d}/profile", f"--virtual-time-budget={wait_ms}",
            "--run-all-compositor-stages-before-draw", "--no-pdf-header-footer",
            f"--print-to-pdf={out}",
        ]
        if landscape:
            cmd.append("--landscape")
        cmd.append(page.as_uri())
        run(cmd, timeout=max(TIMEOUT, wait_ms // 1000 + 30))
        if not out.exists():
            raise RuntimeError("chromium hat keine PDF erzeugt")
        return out.read_bytes(), {}


# ------------------------------------------------------------- markdown -> pdf
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
  .wide-table { margin-left: -1.8cm; margin-right: -1.8cm; }
  .wide-table table { font-size: 8.5pt; width: 100%; }
  .wide-table th, .wide-table td { padding: 4px 7px; }
  body {
    font-family: 'Latin Modern Roman', 'CMU Serif', 'TeX Gyre Termes', Georgia, 'Times New Roman', serif;
    font-size: 11pt; line-height: 1.55; color: #333333; margin: 0;
    text-align: justify;
    hyphens: auto;
  }
  .title-block.design-magicM { text-align: center; margin: 0 0 28pt 0; }
  .title-block.design-magicM .doc-title { font-size: 22pt; font-weight: bold; color: #000000; line-height: 1.2; letter-spacing: 0.02em; margin-bottom: 6pt; }
  .title-block.design-magicM .doc-subtitle { font-size: 14pt; font-style: italic; color: #2E7D32; margin-bottom: 12pt; }
  .title-block.design-magicM .doc-meta { font-size: 11pt; color: #666666; }
  h1 { font-size: 20pt; color: #000000; margin-top: 0; margin-bottom: 12pt; text-align: center; font-weight: bold; letter-spacing: 0.02em; }
  h2 { font-size: 14pt; color: #000000; margin-top: 22px; margin-bottom: 6px; font-weight: bold; padding-left: 8px; border-left: 4px solid #388E3C; text-align: left; }
  h3 { font-size: 12pt; color: #333333; margin-top: 16px; margin-bottom: 4px; font-style: italic; font-weight: normal; text-align: left; }
  p { margin: 0 0 8pt 0; text-indent: 1.2em; }
  h1 + p, h2 + p, h3 + p, blockquote + p { text-indent: 0; }
  code { font-family: 'Latin Modern Mono', 'CMU Typewriter Text', 'Courier New', monospace; font-size: 10pt; background: #f5f5f5; padding: 1px 4px; border-radius: 2px; }
  pre { font-family: 'Latin Modern Mono', 'CMU Typewriter Text', 'Courier New', monospace; font-size: 9.5pt; background: #f8f8f8; padding: 10px 12px; border: 1px solid #ECECEC; white-space: pre-wrap; }
  pre code { background: transparent; padding: 0; }
  table { border-collapse: collapse; width: auto; max-width: 100%; table-layout: auto; margin: 14px 0; font-size: 10.5pt; }
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


def _wrap_wide_tables(html, min_cols=5):
    def repl(m):
        table = m.group(0)
        first_row = re.search(r'<tr>(.*?)</tr>', table, re.DOTALL)
        ncols = len(re.findall(r'<t[hd][ >]', first_row.group(1))) if first_row else 0
        return f'<div class="wide-table">{table}</div>' if ncols >= min_cols else table
    return re.sub(r'<table\b[^>]*>.*?</table>', repl, html, flags=re.DOTALL)


def _render_title_block(fm, design):
    def pick(*keys):
        for k in keys:
            if fm.get(k):
                return fm[k]
        return ""
    title_raw = pick("title", "titel")
    if not title_raw:
        return ""
    esc = lambda s: html_lib.escape(s, quote=False)
    title = esc(title_raw)
    subtitle = esc(pick("subtitle", "untertitel"))
    author = esc(pick("author", "autor", "patient"))
    date = esc(pick("date", "datum", "stand"))
    meta = "  ·  ".join(p for p in (author, date) if p)
    parts = [f'<div class="title-block design-{design}">', f'<div class="doc-title">{title}</div>']
    if subtitle:
        parts.append(f'<div class="doc-subtitle">{subtitle}</div>')
    if meta:
        parts.append(f'<div class="doc-meta">{meta}</div>')
    parts.append('</div>')
    return "\n".join(parts)


def md_to_pdf(body: bytes, q) -> tuple[bytes, dict]:
    import markdown
    design = (q.get("design", ["collana"])[0] or "collana")
    if design not in DESIGNS:
        design = "collana"
    md_text = body.decode("utf-8", errors="replace")

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

    html_body = markdown.markdown(md_text, extensions=["tables", "fenced_code"])
    html_body = _wrap_wide_tables(html_body)
    title_block = _render_title_block(frontmatter, design)

    full = (
        '<!DOCTYPE html><html lang="de"><head><meta charset="UTF-8">'
        f'<style>{DESIGNS[design]}</style></head><body>'
        f'{title_block}\n{html_body}</body></html>'
    )
    from weasyprint import HTML
    pdf = HTML(string=full).write_pdf()
    return pdf, {}


# ----------------------------------------------------------------- docx -> pdf
def docx_to_pdf(body: bytes, q) -> tuple[bytes, dict]:
    with tempfile.TemporaryDirectory() as d:
        src = pathlib.Path(d) / "in.docx"
        src.write_bytes(body)
        outdir = pathlib.Path(d) / "out"
        outdir.mkdir()
        soffice = shutil.which("soffice") or shutil.which("libreoffice")
        if soffice:
            run([soffice, "--headless", "--norestore",
                 f"-env:UserInstallation=file://{d}/profile",
                 "--convert-to", "pdf", "--outdir", str(outdir), str(src)])
            produced = outdir / "in.pdf"
            if not produced.exists():
                raise RuntimeError("LibreOffice erzeugte keine PDF")
            return produced.read_bytes(), {"X-Converter": "libreoffice", "X-Warning": ""}
        pandoc = shutil.which("pandoc")
        if pandoc:
            engine = next((e for e in ("weasyprint", "wkhtmltopdf", "pdflatex", "xelatex", "tectonic")
                           if shutil.which(e)), None)
            if not engine:
                raise RuntimeError("pandoc ohne PDF-Engine")
            out = pathlib.Path(d) / "out.pdf"
            run([pandoc, str(src), "-o", str(out), f"--pdf-engine={engine}"])
            warn = (f"LibreOffice nicht gefunden — Fallback {engine} via pandoc; "
                    "exaktes Word-Layout geht verloren.")
            return out.read_bytes(), {"X-Converter": f"pandoc+{engine}", "X-Warning": warn}
        raise RuntimeError("Kein Konverter verfügbar (LibreOffice/pandoc)")


# ------------------------------------------------------------------ pdf -> txt
def pdf_to_text(body: bytes, q) -> tuple[bytes, dict]:
    layout = (q.get("layout", ["false"])[0] or "false").lower() == "true"
    with tempfile.TemporaryDirectory() as d:
        src = pathlib.Path(d) / "in.pdf"
        out = pathlib.Path(d) / "out.txt"
        src.write_bytes(body)
        cmd = ["pdftotext"]
        if layout:
            cmd.append("-layout")
        cmd += [str(src), str(out)]
        run(cmd)
        return out.read_bytes(), {"Content-Type": "text/plain; charset=utf-8"}


ROUTES = {
    "/html_to_pdf": (html_to_pdf, "application/pdf"),
    "/md_to_pdf": (md_to_pdf, "application/pdf"),
    "/docx_to_pdf": (docx_to_pdf, "application/pdf"),
    "/pdf_to_text": (pdf_to_text, "text/plain; charset=utf-8"),
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send(self, code, body=b"", headers=None, ctype="text/plain; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            if v:
                self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _authed(self):
        if not TOKEN:
            return True
        return self.headers.get("Authorization", "") == f"Bearer {TOKEN}"

    def do_GET(self):
        if urlparse(self.path).path == "/health":
            return self._send(200, "ok")
        self._send(404, "not found")

    def do_POST(self):
        if not self._authed():
            return self._send(401, "unauthorized")
        u = urlparse(self.path)
        route = ROUTES.get(u.path)
        if not route:
            return self._send(404, "unknown endpoint")
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0:
            return self._send(400, "empty body")
        if length > MAX_BODY:
            return self._send(413, "body too large")
        body = self.rfile.read(length)
        fn, ctype = route
        try:
            out, extra = fn(body, parse_qs(u.query))
        except subprocess.CalledProcessError as e:
            err = (e.stderr or b"").decode("utf-8", "replace")[-800:]
            return self._send(500, f"{u.path} fehlgeschlagen: {err}")
        except subprocess.TimeoutExpired:
            return self._send(504, f"{u.path}: Timeout nach {TIMEOUT}s")
        except Exception as e:  # noqa: BLE001
            return self._send(500, f"{u.path}: {e}")
        ct = (extra or {}).pop("Content-Type", ctype)
        self._send(200, out, headers=extra, ctype=ct)

    def log_message(self, fmt, *args):
        sys.stderr.write("[convert] " + (fmt % args) + "\n")


if __name__ == "__main__":
    sys.stderr.write(f"[convert] chromium={CHROME} port={PORT} token={'on' if TOKEN else 'off'}\n")
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
