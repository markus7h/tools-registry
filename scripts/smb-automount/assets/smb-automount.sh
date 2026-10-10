#!/usr/bin/env bash
# Haelt eine SMB-Freigabe eingehaengt (macOS: osascript/Schluesselbund, Linux: gio/gvfs).
# Aufruf: smb-automount smb://[user@]host/share
# Wird von LaunchAgent (macOS) bzw. systemd-user-Timer (Linux) periodisch gestartet;
# bash-3.2-kompatibel (macOS /bin/bash).
set -u

URL="${1:?Aufruf: smb-automount smb://[user@]host/share}"
rest="${URL#smb://}"
user=""
case "$rest" in *@*) user="${rest%%@*}"; rest="${rest#*@}" ;; esac
host="${rest%%/*}"
share="${rest#*/}"; share="${share%/}"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') [$host/$share] $*"; }

# Mountpunkt der Freigabe oder leer.
mountpoint_of() {
  if [ "$(uname)" = "Darwin" ]; then
    mount | awk -v h="$host" -v s="$share" '
      $0 ~ /\(smbfs/ { src=$1; sub(/^\/\/([^@]*@)?/, "", src)
        if (tolower(src) == tolower(h "/" s)) { sub(/^[^ ]+ on /, ""); sub(/ \(smbfs.*/, ""); print; exit } }'
  else
    for d in "/run/user/$(id -u)/gvfs/smb-share:server=${host},share=${share}"*; do
      [ -d "$d" ] && { echo "$d"; return; }
    done
  fi
}

responsive() { perl -e 'alarm shift; exec @ARGV' 10 stat "$1" >/dev/null 2>&1; }

force_unmount() {
  if [ "$(uname)" = "Darwin" ]; then diskutil unmount force "$1" >/dev/null 2>&1
  else gio mount -u "$URL" >/dev/null 2>&1; fi
}

do_mount() {
  if [ "$(uname)" = "Darwin" ]; then
    osascript -e "mount volume \"$URL\"" >/dev/null 2>&1
  else
    gio mount "$URL" </dev/null >/dev/null 2>&1
  fi
}

mp="$(mountpoint_of)"
if [ -n "$mp" ]; then
  responsive "$mp" && exit 0
  log "haengt ($mp reagiert nicht) - haenge aus"
  force_unmount "$mp"
fi

if ! nc -z -w 3 "$host" 445 >/dev/null 2>&1; then
  [ -n "$mp" ] && log "uebersprungen: $host:445 nicht erreichbar"
  exit 0
fi

if do_mount && mp="$(mountpoint_of)" && [ -n "$mp" ]; then
  log "eingehaengt: $mp"
else
  log "FEHLER: Einhaengen von $URL fehlgeschlagen (Zugangsdaten im Schluesselbund?)"
  exit 1
fi
