#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

MODE="${INPUT_MODE:-check}"
SETTINGS="${INPUT_SETTINGS_PATH:-$HOME/.claude/settings.json}"
TEMPLATE="${INPUT_TEMPLATE_PATH:-$HOME/.claude/settings-template.json}"

exec python3 "$(dirname "$0")/sync.py" \
  --mode "$MODE" \
  --settings "$SETTINGS" \
  --template "$TEMPLATE" \
  --run-dir "$TOOLS_RUN_DIR"
