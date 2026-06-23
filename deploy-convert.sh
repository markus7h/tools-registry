#!/usr/bin/env bash
# Deploy des tools-mcp Konvertier-Dienstes (Teil B) auf den zentralen Host.
#
# scp't convert-service/ + compose nach $HOST:$REMOTE_DIR und baut/recreatet den
# Container dort. Anders als der Registry-Server bündelt dieses Image die schweren
# Helfer (chromium/libreoffice/weasyprint/pandoc/poppler) selbst — kein Bind-Mount nötig.
#
# Konfiguration via Env oder optionaler untracked .deploy.env:
#   HOST=<ssh-host> REMOTE_DIR=<pfad> [CONVERT_TOKEN=<token>] ./deploy-convert.sh
set -euo pipefail

cd "$(dirname "$0")"
[ -f ./.deploy.env ] && source ./.deploy.env

HOST="${HOST:?HOST nicht gesetzt — SSH-Zielhost (Env oder .deploy.env)}"
REMOTE_DIR="${REMOTE_DIR:-tools-convert}"

echo "→ scp convert-service nach ${HOST}:${REMOTE_DIR}"
ssh "${HOST}" "mkdir -p ${REMOTE_DIR}/convert-service"
scp -q docker-compose.convert.yml "${HOST}:${REMOTE_DIR}/docker-compose.yml"
scp -q convert-service/server.py convert-service/theme.css convert-service/Dockerfile \
       "${HOST}:${REMOTE_DIR}/convert-service/"

if [ -n "${CONVERT_TOKEN:-}" ]; then
  echo "→ .env (CONVERT_TOKEN) schreiben"
  ssh "${HOST}" "cd ${REMOTE_DIR} && printf 'CONVERT_TOKEN=%s\n' '${CONVERT_TOKEN}' > .env"
fi

echo "→ docker compose up -d --build on ${HOST}"
ssh "${HOST}" "cd ${REMOTE_DIR} && docker compose up -d --build" 2>&1 \
  | grep -vE '^#[0-9]+ (CACHED|DONE|extracting|sha256|naming|exporting|transferring)' \
  | tail -20

echo "→ container status"
ssh "${HOST}" "docker ps --filter name=tools-convert --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
echo "→ Endpoint: http://${HOST}:${CONVERT_PORT:-3459}  (/health, /html_to_pdf, /md_to_pdf, /docx_to_pdf, /pdf_to_text)"
