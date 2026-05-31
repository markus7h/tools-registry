#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"

SCOPE="${INPUT_SCOPE:-all}"

args=(--scope "$SCOPE" --run-dir "$TOOLS_MCP_RUN_DIR")
[[ -n "${INPUT_PROJECTS_DIR:-}" ]] && args+=(--projects-dir "$INPUT_PROJECTS_DIR")

exec python3 "$(dirname "$0")/report.py" "${args[@]}"
