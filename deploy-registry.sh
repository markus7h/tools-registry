#!/usr/bin/env bash
# Deploy des tools-mcp Registry-Servers (Teil A) auf den zentralen Host.
#
# Baut lokal (tsc), scp't dist/ + Build-Kontext nach $HOST:$REMOTE_DIR und
# baut/recreatet den Container dort. scripts/ wird NICHT mitkopiert — der
# Container bind-mountet das Repo-scripts/-Verzeichnis direkt (siehe compose),
# sodass Script-Änderungen ohne Rebuild live ausgeliefert werden.
#
# Konfiguration via Env oder optionaler untracked .deploy.env:
#   HOST=<ssh-host> REMOTE_DIR=<pfad> ./deploy-registry.sh
set -euo pipefail

cd "$(dirname "$0")"

# Optionale lokale Defaults (untracked, z.B. HOST=..., REMOTE_DIR=...).
[ -f ./.deploy.env ] && source ./.deploy.env

HOST="${HOST:?HOST nicht gesetzt — SSH-Zielhost der Registry (Env oder .deploy.env)}"
REMOTE_DIR="${REMOTE_DIR:-tools-registry}"

echo "→ build (tsc)"
npm run build >/dev/null

echo "→ scp build-kontext nach ${HOST}:${REMOTE_DIR}"
ssh "${HOST}" "mkdir -p ${REMOTE_DIR}"
scp -q package.json package-lock.json Dockerfile.registry "${HOST}:${REMOTE_DIR}/"
scp -q docker-compose.registry.yml "${HOST}:${REMOTE_DIR}/docker-compose.yml"
ssh "${HOST}" "rm -rf ${REMOTE_DIR}/dist"
scp -qr dist "${HOST}:${REMOTE_DIR}/dist"

echo "→ docker compose up -d --build on ${HOST}"
ssh "${HOST}" "cd ${REMOTE_DIR} && docker compose up -d --build" 2>&1 \
  | grep -vE '^#[0-9]+ (CACHED|DONE|extracting|sha256|naming|exporting|transferring)' \
  | tail -20

echo "→ container status"
ssh "${HOST}" "docker ps --filter name=tools-registry --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
