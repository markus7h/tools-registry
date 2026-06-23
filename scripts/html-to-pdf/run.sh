#!/usr/bin/env bash
# Dünner Wrapper: lädt die lokale HTML hoch zum zentralen Konvertier-Dienst und
# speichert die zurückkommende PDF. Schwere Tools (Chromium) leben im Dienst.
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_HTML_PATH:?INPUT_HTML_PATH not set}"

if [[ ! -f "$INPUT_HTML_PATH" ]]; then
  printf 'ERROR: HTML-Datei nicht gefunden: %s\n' "$INPUT_HTML_PATH" >&2
  exit 2
fi

SVC="${TOOLS_MCP_CONVERT_URL:-http://192.168.2.15:3459}"
theme="${INPUT_THEME:-none}"
landscape="${INPUT_LANDSCAPE:-false}"
wait_ms="${INPUT_WAIT_MS:-4000}"

if [[ -n "${INPUT_OUTPUT_PATH:-}" ]]; then
  pdf_out="$INPUT_OUTPUT_PATH"
else
  pdf_out="${INPUT_HTML_PATH%.*}.pdf"
fi
mkdir -p "$(dirname "$pdf_out")"

AUTH=()
[[ -n "${TOOLS_MCP_CONVERT_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${TOOLS_MCP_CONVERT_TOKEN}")

code=$(curl -sS "${AUTH[@]}" --data-binary @"$INPUT_HTML_PATH" \
  -w '%{http_code}' -o "$pdf_out" \
  "$SVC/html_to_pdf?theme=${theme}&landscape=${landscape}&wait_ms=${wait_ms}")
if [[ "$code" != "200" ]]; then
  printf 'ERROR: Konvertier-Dienst (%s) HTTP %s: %s\n' "$SVC" "$code" "$(cat "$pdf_out" 2>/dev/null)" >&2
  rm -f "$pdf_out"
  exit 6
fi

if size=$(stat -c%s "$pdf_out" 2>/dev/null); then :; else size=$(stat -f%z "$pdf_out"); fi

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" <<EOF
{
  "pdf_path": "${pdf_out}",
  "size_bytes": ${size}
}
EOF

printf 'PDF erstellt: %s (%d Bytes)\n' "$pdf_out" "$size"
