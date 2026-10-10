#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

exec python3 "$(dirname "$0")/sync.py" \
  --mode "${INPUT_MODE:-check}" \
  --plugins "${INPUT_PLUGINS:-}" \
  --target "${INPUT_TARGET:-$HOME/.config/opencode/opencode.json}" \
  --values "${INPUT_VALUES_PATH:-$HOME/.config/opencode/tools-registry.json}" \
  --source "${INPUT_SOURCE:-https://raw.githubusercontent.com/markus7h/tools-registry/main}" \
  --run-dir "$TOOLS_RUN_DIR"
