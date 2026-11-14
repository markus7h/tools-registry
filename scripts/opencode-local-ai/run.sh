#!/usr/bin/env bash
# Key kommt aus mykeyvault (ai-rem run --secret). Auch direkt nutzbar:
#   INPUT_MODE=apply ./run.sh
set -euo pipefail

VAULT_ITEM="${INPUT_VAULT_ITEM:-litellm opencode key}"
# Eigener Env-Name statt LITELLM_API_KEY: der steht oft in der Shell (anderer Key, z.B. aus ~/.zshrc)
# und wuerde sonst den Vault-Abruf ueberspringen.

# Ohne Key einmal unter `ai-rem run` neu starten, das ihn aus dem Vault setzt.
if [[ -z "${OPENCODE_LITELLM_KEY:-}" && -z "${_OLA_VIA_AIREM:-}" ]] && command -v ai-rem >/dev/null; then
  export _OLA_VIA_AIREM=1
  if ai-rem run --secret "${VAULT_ITEM}=OPENCODE_LITELLM_KEY" -- true >/dev/null 2>&1; then
    exec ai-rem run --secret "${VAULT_ITEM}=OPENCODE_LITELLM_KEY" -- "$0" "$@"
  fi
  echo "Hinweis: Vault-Item '${VAULT_ITEM}' nicht abrufbar - weiter mit vorhandener Secret-Datei." >&2
fi

RUN_DIR="${TOOLS_RUN_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/opencode-local-ai.XXXXXX")}"

exec python3 "$(dirname "$0")/setup.py" \
  --mode "${INPUT_MODE:-check}" \
  --set-default "${INPUT_SET_DEFAULT:-false}" \
  --target "${INPUT_TARGET:-$HOME/.config/opencode/opencode.json}" \
  --base-url "${INPUT_BASE_URL:-http://mystorage.lan:11437/v1}" \
  --model "${INPUT_MODEL:-private-general}" \
  --vault-item "$VAULT_ITEM" \
  --run-dir "$RUN_DIR"
