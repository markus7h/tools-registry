#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_PDF_PATH:?INPUT_PDF_PATH not set}"

if [[ ! -f "$INPUT_PDF_PATH" ]]; then
  printf 'ERROR: PDF not found: %s\n' "$INPUT_PDF_PATH" >&2
  exit 2
fi

out="${TOOLS_MCP_RUN_DIR}/extracted.txt"
layout_flag=""
if [[ "${INPUT_LAYOUT:-}" == "true" ]]; then
  layout_flag="-layout"
fi

pdftotext $layout_flag "$INPUT_PDF_PATH" "$out"

chars=$(wc -c < "$out" | tr -d ' ')

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" <<EOF
{
  "text_file": "${out}",
  "char_count": ${chars}
}
EOF

printf 'extracted %s chars to %s\n' "$chars" "$out"
