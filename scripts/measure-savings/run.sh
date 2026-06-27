#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

args=(--run-dir "$TOOLS_RUN_DIR")
[[ -n "${INPUT_PROJECTS_DIR:-}" ]] && args+=(--projects-dir "$INPUT_PROJECTS_DIR")

exec python3 "$(dirname "$0")/measure.py" "${args[@]}"
