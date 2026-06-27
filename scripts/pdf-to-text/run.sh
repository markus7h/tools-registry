#!/usr/bin/env bash
# Dünner Wrapper: lädt die lokale PDF zum zentralen Konvertier-Dienst (pdftotext)
# hoch und schreibt den extrahierten Text ins run_dir.
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"
: "${INPUT_PDF_PATH:?INPUT_PDF_PATH not set}"

if [[ ! -f "$INPUT_PDF_PATH" ]]; then
  printf 'ERROR: PDF nicht gefunden: %s\n' "$INPUT_PDF_PATH" >&2
  exit 2
fi

SVC="${TOOLS_CONVERT_URL:-http://192.168.2.15:3459}"
layout="false"
[[ "${INPUT_LAYOUT:-}" == "true" ]] && layout="true"

out="${TOOLS_RUN_DIR}/extracted.txt"

AUTH=()
[[ -n "${TOOLS_CONVERT_TOKEN:-}" ]] && AUTH=(-H "Authorization: Bearer ${TOOLS_CONVERT_TOKEN}")

code=$(curl -sS "${AUTH[@]}" --data-binary @"$INPUT_PDF_PATH" \
  -w '%{http_code}' -o "$out" \
  "$SVC/pdf_to_text?layout=${layout}")
if [[ "$code" != "200" ]]; then
  printf 'ERROR: Konvertier-Dienst (%s) HTTP %s: %s\n' "$SVC" "$code" "$(cat "$out" 2>/dev/null)" >&2
  rm -f "$out"
  exit 6
fi

chars=$(wc -c < "$out" | tr -d ' ')

cat > "${TOOLS_RUN_DIR}/outputs.json" <<EOF
{
  "text_file": "${out}",
  "char_count": ${chars}
}
EOF

printf 'extracted %s chars to %s\n' "$chars" "$out"
