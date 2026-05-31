#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"
: "${INPUT_TEXT_FILE:?INPUT_TEXT_FILE not set}"

n="${INPUT_N:-20}"

if [[ ! -f "$INPUT_TEXT_FILE" ]]; then
  printf 'ERROR: text_file not found: %s\n' "$INPUT_TEXT_FILE" >&2
  exit 2
fi

preview="${TOOLS_MCP_RUN_DIR}/preview.txt"
head -n "$n" "$INPUT_TEXT_FILE" > "$preview"

# JSON-sicheres Encoding des preview_text via python
preview_json=$(python3 -c 'import json,sys; print(json.dumps(open(sys.argv[1]).read()))' "$preview")

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" <<EOF
{
  "preview_file": "${preview}",
  "preview_text": ${preview_json}
}
EOF

printf 'wrote first %s lines to %s\n' "$n" "$preview"
