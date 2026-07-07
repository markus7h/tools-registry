#!/usr/bin/env bash
# Listet die MCP-Plugins des tools-registry-Marketplace (Ersatz fuer fehlendes `claude plugin marketplace info`).
set -euo pipefail
manifest="$(dirname "$0")/.claude-plugin/marketplace.json"
jq -r '.name as $m | "Marketplace: \($m)\n", (.plugins[] | "  \(.name): \(.description)")' "$manifest"
