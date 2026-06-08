#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_MCP_RUN_DIR:?TOOLS_MCP_RUN_DIR not set}"

MODE="${INPUT_MODE:-check}"
KIND="${INPUT_KIND:-all}"
ASSETS="$(dirname "$0")/assets"
AGENTS_DST="$HOME/.claude/agents"
SKILLS_DST="$HOME/.claude/skills"
REPORT="${TOOLS_MCP_RUN_DIR}/report.txt"

: > "$REPORT"
changed=false
applied=false

# Vergleicht src->dst, schreibt im apply-Modus. Setzt 'changed' bei Abweichung.
process_file() {
  local src="$1" dst="$2" label="$3"
  if [[ ! -f "$dst" ]]; then
    echo "NEU      $label" >> "$REPORT"; changed=true
  elif ! cmp -s "$src" "$dst"; then
    echo "GEAENDERT $label" >> "$REPORT"; changed=true
  else
    echo "gleich   $label" >> "$REPORT"
  fi
  if [[ "$MODE" == "apply" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"
  fi
}

want() { [[ "$KIND" == "all" || "$KIND" == "$1" ]]; }

if want agents && [[ -d "$ASSETS/agents" ]]; then
  for src in "$ASSETS/agents"/*.md; do
    [[ -f "$src" ]] || continue
    name="$(basename "$src")"
    process_file "$src" "$AGENTS_DST/$name" "agents/$name"
  done
fi

if want skills && [[ -d "$ASSETS/skills" ]]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$ASSETS/skills/"}"
    process_file "$src" "$SKILLS_DST/$rel" "skills/$rel"
  done < <(find "$ASSETS/skills" -type f -print0)
fi

[[ "$MODE" == "apply" ]] && applied=true

cat > "${TOOLS_MCP_RUN_DIR}/outputs.json" << EOF
{
  "changed": ${changed},
  "applied": ${applied}
}
EOF

echo "dotclaude-install (mode=$MODE, kind=$KIND)"
echo "  agents -> $AGENTS_DST"
echo "  skills -> $SKILLS_DST"
cat "$REPORT"
if [[ "$MODE" != "apply" && "$changed" == "true" ]]; then
  echo "Hinweis: mode=apply ausfuehren, um die Aenderungen zu schreiben."
fi
