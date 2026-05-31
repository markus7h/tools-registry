#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_MSG:?INPUT_MSG not set}"

out="${TOOLS_MCP_RUN_DIR}/echo.txt"
printf '%s\n' "$INPUT_MSG" > "$out"

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" <<EOF
{ "text_file": "${out}" }
EOF

printf 'wrote: %s\n' "$out"
