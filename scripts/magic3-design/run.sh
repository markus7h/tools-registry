#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

MODE="${INPUT_MODE:-check}"
TARGET="${INPUT_TARGET_DIR:-$HOME/.claude/skills/magic3-design}"
ASSETS="$(dirname "$0")/assets"
REPORT="${TOOLS_RUN_DIR}/report.txt"

: > "$REPORT"
changed=false
applied=false

for f in SKILL.md design-spec.md theme.css; do
  src="$ASSETS/$f"
  dst="$TARGET/$f"
  if [[ ! -f "$dst" ]]; then
    echo "NEU      $f" >> "$REPORT"; changed=true
  elif ! cmp -s "$src" "$dst"; then
    echo "GEÄNDERT $f" >> "$REPORT"; changed=true
  else
    echo "gleich   $f" >> "$REPORT"
  fi
done

if [[ "$MODE" == "apply" ]]; then
  mkdir -p "$TARGET"
  for f in SKILL.md design-spec.md theme.css; do
    cp "$ASSETS/$f" "$TARGET/$f"
  done
  applied=true
  echo "-> geschrieben nach $TARGET" >> "$REPORT"
fi

cat > "${TOOLS_RUN_DIR}/outputs.json" << EOF
{
  "target": "${TARGET}",
  "changed": ${changed},
  "applied": ${applied}
}
EOF

echo "magic3-design (mode=$MODE) -> $TARGET"
cat "$REPORT"
if [[ "$MODE" != "apply" && "$changed" == "true" ]]; then
  echo "Hinweis: mode=apply ausführen, um die Änderungen zu schreiben."
fi
