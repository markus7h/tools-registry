#!/usr/bin/env bash
set -euo pipefail

: "${TOOLS_RUN_DIR:?TOOLS_RUN_DIR not set}"

MODE="${INPUT_MODE:-check}"
URL="${INPUT_URL:-smb://markus@mystorage.lan/markus}"
INTERVAL="${INPUT_INTERVAL:-60}"
ASSETS="$(cd "$(dirname "$0")" && pwd)/assets"
REPORT="${TOOLS_RUN_DIR}/report.txt"
OS="$(uname)"

case "$MODE" in check|apply|uninstall|reconnect) ;; *) echo "ERROR: mode muss check, apply, uninstall oder reconnect sein" >&2; exit 2 ;; esac
case "$URL" in smb://*/*) ;; *) echo "ERROR: url muss smb://[user@]host/share sein, nicht '$URL'" >&2; exit 2 ;; esac
case "$INTERVAL" in ''|*[!0-9]*) echo "ERROR: interval muss eine Zahl (Sekunden) sein" >&2; exit 2 ;; esac
[[ "$OS" == "Darwin" || "$OS" == "Linux" ]] || { echo "ERROR: nur macOS und Linux unterstuetzt ($OS)" >&2; exit 2; }

rest="${URL#smb://}"; rest="${rest#*@}"
HOST="${rest%%/*}"; SHARE="${rest#*/}"; SHARE="${SHARE%/}"
LABEL="tools.smb-automount.${HOST}-${SHARE//[^A-Za-z0-9._-]/_}"
BIN="$HOME/.local/bin/smb-automount"

if [[ "$OS" == "Darwin" ]]; then
  LOG="$HOME/Library/Logs/smb-automount.log"
  UNITS=("$HOME/Library/LaunchAgents/${LABEL}.plist")
  TEMPLATES=("$ASSETS/launchagent.plist.tmpl")
else
  LOG="journalctl --user -u ${LABEL}.service"
  UNITS=("$HOME/.config/systemd/user/${LABEL}.service" "$HOME/.config/systemd/user/${LABEL}.timer")
  TEMPLATES=("$ASSETS/systemd.service.tmpl" "$ASSETS/systemd.timer.tmpl")
fi

render() {
  sed -e "s|@LABEL@|${LABEL}|g" -e "s|@BIN@|${BIN}|g" -e "s|@URL@|${URL}|g" \
      -e "s|@INTERVAL@|${INTERVAL}|g" -e "s|@LOG@|${LOG}|g" "$1"
}

job_loaded() {
  if [[ "$OS" == "Darwin" ]]; then launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1
  else systemctl --user is-active --quiet "${LABEL}.timer"; fi
}

unload() {
  if [[ "$OS" == "Darwin" ]]; then launchctl bootout "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  else systemctl --user disable --now "${LABEL}.timer" >/dev/null 2>&1 || true; fi
}

: > "$REPORT"
say() { echo "$*" >> "$REPORT"; }
changed=false
applied=false

say "Freigabe: $URL  (Job $LABEL, alle ${INTERVAL}s)"

# Soll-Zustand vergleichen: Waechter-Script + Plist bzw. systemd-Units.
compare() {
  local src="$1" dst="$2" tmp
  tmp="$(mktemp)"; cat > "$tmp"
  if [[ ! -f "$dst" ]]; then say "NEU      $dst"; changed=true
  elif ! cmp -s "$tmp" "$dst"; then say "GEÄNDERT $dst"; changed=true
  else say "gleich   $dst"; fi
  [[ "$MODE" == "apply" ]] && { mkdir -p "$(dirname "$dst")"; cp "$tmp" "$dst"; }
  rm -f "$tmp"
}

if [[ "$MODE" == "reconnect" ]]; then
  # Waechter einmal sofort laufen lassen statt auf den naechsten Job-Lauf zu warten.
  # Installiertes Script bevorzugen, sonst das mitgelieferte; hart begrenzt, damit ein
  # haengender Mount den Tool-Aufruf nicht blockiert.
  watcher="$BIN"; [[ -x "$watcher" ]] || watcher="$ASSETS/smb-automount.sh"
  out="$(perl -e 'alarm shift; exec @ARGV' 45 /bin/bash "$watcher" "$URL" 2>&1)" \
    && say "Waechter: ok" || say "Waechter: Exit $? (Timeout oder Fehler)"
  if [[ -n "$out" ]]; then
    say "$out"
    [[ "$OS" == "Darwin" ]] && { mkdir -p "$(dirname "$LOG")"; echo "$out" >> "$LOG"; }
  fi
  job_loaded && say "Job:     geladen" || say "Job:     NICHT geladen (mode=apply installiert den Waechter dauerhaft)"
elif [[ "$MODE" == "uninstall" ]]; then
  unload
  for u in "${UNITS[@]}"; do [[ -f "$u" ]] && { rm -f "$u"; say "entfernt $u"; changed=true; }; done
  [[ "$OS" == "Linux" ]] && systemctl --user daemon-reload >/dev/null 2>&1 || true
  # Waechter-Script nur entfernen, wenn kein anderer Job es mehr nutzt.
  others=$(grep -ls "$BIN" "$HOME/Library/LaunchAgents/"tools.smb-automount.* \
           "$HOME/.config/systemd/user/"tools.smb-automount.* 2>/dev/null || true)
  if [[ -z "$others" && -f "$BIN" ]]; then rm -f "$BIN"; say "entfernt $BIN"; fi
  applied=$changed
else
  compare "$ASSETS/smb-automount.sh" "$BIN" < "$ASSETS/smb-automount.sh"
  [[ "$MODE" == "apply" ]] && chmod +x "$BIN"
  for i in "${!UNITS[@]}"; do compare "${TEMPLATES[$i]}" "${UNITS[$i]}" < <(render "${TEMPLATES[$i]}"); done

  if [[ "$MODE" == "apply" ]]; then
    if [[ "$OS" == "Darwin" ]]; then
      unload
      mkdir -p "$(dirname "$LOG")"
      launchctl bootstrap "gui/$(id -u)" "${UNITS[0]}"
    else
      systemctl --user daemon-reload
      systemctl --user enable --now "${LABEL}.timer" >/dev/null
      systemctl --user start "${LABEL}.service" || true
    fi
    applied=true
  fi

  job_loaded && say "Job:     geladen" || { say "Job:     NICHT geladen"; changed=true; }
fi

mounted=false
if mount 2>/dev/null | grep -qiE "@?${HOST}/${SHARE} on .*smbfs" \
   || ls -d "/run/user/$(id -u)/gvfs/smb-share:server=${HOST},share=${SHARE}"* >/dev/null 2>&1; then
  mounted=true
  say "Mount:   eingehängt"
else
  say "Mount:   nicht eingehängt"
fi
say "Log:     $LOG"

cat > "${TOOLS_RUN_DIR}/outputs.json" << EOF
{
  "report": "${REPORT}",
  "changed": ${changed},
  "applied": ${applied},
  "mounted": ${mounted}
}
EOF

echo "smb_automount (mode=$MODE, $OS)"
cat "$REPORT"
if [[ "$MODE" == "check" && "$changed" == "true" ]]; then
  echo "Hinweis: mode=apply ausführen, um den Waechter zu installieren/aktualisieren."
fi
