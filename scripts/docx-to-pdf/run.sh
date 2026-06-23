#!/usr/bin/env bash
# Dünner Wrapper: lädt die lokale .docx zum zentralen Konvertier-Dienst
# (LibreOffice headless, Fallback pandoc) hoch und speichert die PDF.
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_DOCX_PATH:?INPUT_DOCX_PATH not set}"

if [[ ! -f "$INPUT_DOCX_PATH" ]]; then
  printf 'ERROR: docx-Datei nicht gefunden: %s\n' "$INPUT_DOCX_PATH" >&2
  exit 2
fi

SVC="${TOOLS_MCP_CONVERT_URL:-http://192.168.2.15:3458}"

if [[ -n "${INPUT_OUTPUT_PATH:-}" ]]; then
  pdf_out="$INPUT_OUTPUT_PATH"
else
  pdf_out="${INPUT_DOCX_PATH%.*}.pdf"
fi
mkdir -p "$(dirname "$pdf_out")"

AUTH=()
[[ -n "${TOOLS_MCP_CONVERT_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${TOOLS_MCP_CONVERT_TOKEN}")

hdr="${TOOLS_MCP_RUN_DIR}/hdr"
code=$(curl -sS "${AUTH[@]}" --data-binary @"$INPUT_DOCX_PATH" \
  -D "$hdr" -w '%{http_code}' -o "$pdf_out" \
  "$SVC/docx_to_pdf")
if [[ "$code" != "200" ]]; then
  printf 'ERROR: Konvertier-Dienst (%s) HTTP %s: %s\n' "$SVC" "$code" "$(cat "$pdf_out" 2>/dev/null)" >&2
  rm -f "$pdf_out"
  exit 6
fi

# Metadaten aus den Response-Headern (X-Converter / X-Warning); Quotes für JSON entschärfen.
converter=$(grep -i '^x-converter:' "$hdr" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r"' || true)
warning=$(grep -i '^x-warning:' "$hdr" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r"' || true)
[[ -z "$converter" ]] && converter="unknown"

if size=$(stat -c%s "$pdf_out" 2>/dev/null); then :; else size=$(stat -f%z "$pdf_out"); fi

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" <<EOF
{
  "pdf_path": "${pdf_out}",
  "size_bytes": ${size},
  "converter": "${converter}",
  "warning": "${warning}"
}
EOF

printf 'PDF erstellt via %s: %s (%d Bytes)\n' "$converter" "$pdf_out" "$size"
