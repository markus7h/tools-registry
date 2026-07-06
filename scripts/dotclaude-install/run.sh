#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

MODE="${INPUT_MODE:-check}"
KIND="${INPUT_KIND:-all}"
ASSETS="$(dirname "$0")/assets"
HOOKS_SRC="$(cd "$(dirname "$0")/../.." && pwd)/hooks"
AGENTS_DST="$HOME/.claude/agents"
SKILLS_DST="$HOME/.claude/skills"
HOOKS_DST="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"
REPORT="${TOOLS_RUN_DIR}/report.txt"

: > "$REPORT"
changed=false
applied=false
registration_pending=false

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

# Hooks: Quelle ist der Repo-Root (kanonisch), nicht assets/ — kein Duplikat/Drift.
if want hooks && [[ -f "$HOOKS_SRC/tool-discovery.sh" ]]; then
  process_file "$HOOKS_SRC/tool-discovery.sh" "$HOOKS_DST/tool-discovery.sh" "hooks/tool-discovery.sh"
  [[ "$MODE" == "apply" ]] && chmod +x "$HOOKS_DST/tool-discovery.sh"
  # Datei allein reicht nicht — der Hook muss in settings.json registriert sein.
  if ! grep -q "tool-discovery.sh" "$SETTINGS" 2>/dev/null; then
    registration_pending=true
  fi
fi

[[ "$MODE" == "apply" ]] && applied=true

cat > "${TOOLS_RUN_DIR}/outputs.json" << EOF
{
  "changed": ${changed},
  "applied": ${applied},
  "registration_pending": ${registration_pending}
}
EOF

echo "dotclaude-install (mode=$MODE, kind=$KIND)"
echo "  agents -> $AGENTS_DST"
echo "  skills -> $SKILLS_DST"
echo "  hooks  -> $HOOKS_DST"
cat "$REPORT"
if [[ "$MODE" != "apply" && "$changed" == "true" ]]; then
  echo "Hinweis: mode=apply ausfuehren, um die Aenderungen zu schreiben."
fi
if [[ "$registration_pending" == "true" ]]; then
  cat <<EOF
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
AKTION ERFORDERLICH: tool-discovery-Hook ist deployt, aber noch NICHT in
settings.json registriert. Diesen Block unter hooks.UserPromptSubmit einfuegen:

  { "matcher": "", "hooks": [ { "type": "command",
    "command": "${HOOKS_DST}/tool-discovery.sh", "timeout": 10000 } ] }

Pruefen mit:  settings-sync (mode=check)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF
fi
