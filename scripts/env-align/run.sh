#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

MODE="${INPUT_MODE:-check}"
REFERENCE="${INPUT_REFERENCE:?INPUT_REFERENCE not set (SSH-Host, settings.json oder Manifest)}"
SETTINGS="${INPUT_SETTINGS_PATH:-$HOME/.claude/settings.json}"
STRICT="${INPUT_STRICT:-false}"

exec python3 "$(dirname "$0")/align.py" \
  --mode "$MODE" \
  --reference "$REFERENCE" \
  --settings "$SETTINGS" \
  --strict "$STRICT" \
  --run-dir "$TOOLS_RUN_DIR"
