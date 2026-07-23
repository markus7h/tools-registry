#!/usr/bin/env bash
# Dünner Wrapper: lädt die lokale Markdown-Datei zum zentralen Konvertier-Dienst
# (markdown + WeasyPrint) hoch und speichert die zurückkommende PDF.
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"
: "${INPUT_MD_PATH:?INPUT_MD_PATH not set}"

if [[ ! -f "$INPUT_MD_PATH" ]]; then
  printf 'ERROR: Markdown-Datei nicht gefunden: %s\n' "$INPUT_MD_PATH" >&2
  exit 2
fi

SVC="${TOOLS_CONVERT_URL:-http://192.168.2.15:3459}"
design="${INPUT_DESIGN:-collana}"

if [[ -n "${INPUT_OUTPUT_PATH:-}" ]]; then
  pdf_out="$INPUT_OUTPUT_PATH"
else
  pdf_out="${INPUT_MD_PATH%.md}.pdf"
fi
mkdir -p "$(dirname "$pdf_out")"

AUTH=()
[[ -n "${TOOLS_CONVERT_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${TOOLS_CONVERT_TOKEN}")

code=$(curl -sS ${AUTH[@]+"${AUTH[@]}"} --data-binary @"$INPUT_MD_PATH" \
  -w '%{http_code}' -o "$pdf_out" \
  "$SVC/md_to_pdf?design=${design}")
if [[ "$code" != "200" ]]; then
  printf 'ERROR: Konvertier-Dienst (%s) HTTP %s: %s\n' "$SVC" "$code" "$(cat "$pdf_out" 2>/dev/null)" >&2
  rm -f "$pdf_out"
  exit 6
fi

if size=$(stat -c%s "$pdf_out" 2>/dev/null); then :; else size=$(stat -f%z "$pdf_out"); fi

cat > "${TOOLS_RUN_DIR}/outputs.json" <<EOF
{
  "pdf_path": "${pdf_out}",
  "size_bytes": ${size}
}
EOF

printf 'PDF erstellt (%s): %s (%d Bytes)\n' "$design" "$pdf_out" "$size"
