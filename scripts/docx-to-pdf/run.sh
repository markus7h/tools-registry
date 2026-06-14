#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_DOCX_PATH:?INPUT_DOCX_PATH not set}"

if [[ ! -f "$INPUT_DOCX_PATH" ]]; then
  printf 'ERROR: docx file not found: %s\n' "$INPUT_DOCX_PATH" >&2
  exit 2
fi

# Ausgabepfad: explizit oder neben der docx-Datei (Endung case-insensitive ersetzen).
if [[ -n "${INPUT_OUTPUT_PATH:-}" ]]; then
  pdf_out="$INPUT_OUTPUT_PATH"
else
  pdf_out="${INPUT_DOCX_PATH%.*}.pdf"
fi
out_dir="$(dirname "$pdf_out")"
mkdir -p "$out_dir"

# --- LibreOffice finden (beste Layout-Treue) ---
LO_BIN=""
for cand in soffice libreoffice; do
  if command -v "$cand" >/dev/null 2>&1; then LO_BIN="$cand"; break; fi
done
LO_FLATPAK=""
if [[ -z "$LO_BIN" ]] && command -v flatpak >/dev/null 2>&1; then
  if flatpak info org.libreoffice.LibreOffice >/dev/null 2>&1; then
    LO_FLATPAK="org.libreoffice.LibreOffice"
  fi
fi

# Konvertiert via LibreOffice headless mit eigenem User-Profil (verhindert Kollision
# mit einer laufenden LibreOffice-Instanz). $@ ist der LO-Runner (binary oder flatpak run ...).
convert_with_lo() {
  local profile="${TOOLS_MCP_RUN_DIR}/lo_profile"
  local tmp_out="${TOOLS_MCP_RUN_DIR}/lo_out"
  mkdir -p "$tmp_out"
  "$@" --headless --norestore \
    -env:UserInstallation="file://${profile}" \
    --convert-to pdf --outdir "$tmp_out" "$INPUT_DOCX_PATH" >&2
  local produced="${tmp_out}/$(basename "${INPUT_DOCX_PATH%.*}").pdf"
  if [[ ! -f "$produced" ]]; then
    printf 'ERROR: LibreOffice erzeugte keine PDF (%s)\n' "$produced" >&2
    return 1
  fi
  mv -f "$produced" "$pdf_out"
}

converter=""
warning=""
if [[ -n "$LO_BIN" ]]; then
  convert_with_lo "$LO_BIN"
  converter="libreoffice"
elif [[ -n "$LO_FLATPAK" ]]; then
  convert_with_lo flatpak run "$LO_FLATPAK"
  converter="libreoffice-flatpak"
elif command -v pandoc >/dev/null 2>&1; then
  # Fallback: pandoc liest den docx-Inhalt und rendert via PDF-Engine.
  # Hinweis: Word-Layout/Briefkopf der Vorlage geht dabei weitgehend verloren.
  engine=""
  for e in weasyprint wkhtmltopdf pdflatex xelatex tectonic; do
    if command -v "$e" >/dev/null 2>&1; then engine="$e"; break; fi
  done
  if [[ -z "$engine" ]]; then
    printf 'ERROR: pandoc gefunden, aber keine PDF-Engine (weasyprint/wkhtmltopdf/pdflatex/xelatex/tectonic).\n' >&2
    exit 3
  fi
  warning="LibreOffice nicht gefunden — Fallback ${engine} via pandoc genutzt; das exakte Word-Layout (Briefkopf/Kopf-Fußzeilen) geht dabei verloren. Für volle Treue 'libreoffice-writer' installieren."
  printf 'WARNUNG: %s\n' "$warning" >&2
  pandoc "$INPUT_DOCX_PATH" -o "$pdf_out" --pdf-engine="$engine" >&2
  converter="pandoc+${engine}"
else
  printf 'ERROR: Kein Konverter verfügbar (weder LibreOffice noch pandoc).\n' >&2
  exit 4
fi

if [[ ! -f "$pdf_out" ]]; then
  printf 'ERROR: PDF wurde nicht erstellt: %s\n' "$pdf_out" >&2
  exit 5
fi

# Plattformrobustes Filesize (GNU stat vs. BSD stat).
if size=$(stat -c%s "$pdf_out" 2>/dev/null); then :
else size=$(stat -f%z "$pdf_out"); fi

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" <<EOF
{
  "pdf_path": "${pdf_out}",
  "size_bytes": ${size},
  "converter": "${converter}",
  "warning": "${warning}"
}
EOF

printf 'PDF erstellt via %s: %s (%d Bytes)\n' "$converter" "$pdf_out" "$size"
