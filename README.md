# tools-mcp

MCP-Server, der kleine Scripts (`scripts/<name>/`) als MCP-Tools bereitstellt — mit
Run-Dirs, Pipeline-Runner und einer **zentralen Script-Registry**, sodass neue/entfernte
Scripts **ohne Neustart** verfügbar werden.

## Architektur

```
zentraler Host                              Client (Mac etc.)
┌─────────────────────────┐                ┌───────────────────────────────┐
│ tools-registry (Docker) │   HTTP GET     │ tools-mcp (stdio, lokal)      │
│  serve scripts/ über     │ ◀───────────── │  - zieht Katalog, cacht lokal  │
│  /registry + /file       │  Poll (5s)     │    ~/.cache/tools-mcp/scripts  │
│  Quelle = Bind-Mount      │ ──────────────▶│  - registriert Tools live      │
│  des Repo-scripts/        │   Bytes        │  - führt Scripts LOKAL aus     │
└─────────────────────────┘                └───────────────────────────────┘
```

- **Registry-Server** (`src/registry-server.ts`): liefert `scripts/` per HTTP aus. Läuft als
  Container auf einem zentralen Host und bind-mountet das Repo-`scripts/`-Verzeichnis (kein
  Image-Rebuild bei Script-Änderungen). Ein vom Netz-Mount unabhängiger Pfad an die Dateien.
- **MCP-Client** (`src/index.ts`, `src/registry.ts`): spiegelt den Katalog in einen lokalen
  Cache und führt von dort aus. Ein Poll-Loop (kein `fs.watch` — funktioniert nicht über SMB)
  gleicht die Tool-Liste live ab: neu → registrieren, entfernt → `remove()`, geändertes
  Manifest → re-registrieren. Das SDK sendet je Mutation `notifications/tools/list_changed`.

Identifier eines Scripts ist der **Verzeichnisname** (für Datei-Pfade); der **MCP-Tool-Name**
kommt aus `manifest.name` (das der Client lokal aus dem Cache liest).

## Ein Script anlegen

`scripts/<name>/manifest.yaml` + ausführbares `exec`-Script:

```yaml
name: mein_tool            # MCP-Tool-Name (mcp__tools__mein_tool)
description: Was es tut.
exec: ./run.sh
inputs:
  scope:
    type: string           # string | number | integer | boolean
    description: "..."
    required: false
outputs:                   # optional, informativ
  report_file: { type: string, description: Pfad zum Ergebnis. }
ai_rem_entity: tool_mein_tool   # Konvention: korrespondierende ai-rem Tool-Entity
```

Das Exec-Script bekommt pro Input `INPUT_<NAME>` als Env-Var sowie `TOOLS_MCP_RUN_DIR`
(Schreib-Verzeichnis). Benannte Outputs werden über `<run_dir>/outputs.json` zurückgegeben.

Auf dem zentralen Host editiert (per Netz-Mount oder direkt) → die Registry liefert die Änderung
sofort aus, der Client übernimmt sie beim nächsten Poll (≤5 s) **ohne MCP-Neustart**.

### Beispiel: einen Claude-Code-Skill ausliefern

Ein Script kann Dateien beilegen (`assets/`, werden mitgespiegelt) und sie lokal installieren —
so lässt sich ein Claude-Code-Skill systemübergreifend verteilen, ohne manuelles Kopieren.
Siehe `scripts/magic3-design/`: legt SKILL.md + Spec + Theme als Assets bei und schreibt sie via
`mode=apply` nach `~/.claude/skills/magic3-design/` (`mode=check` zeigt nur den Diff).

## Meta-Tools

- `list_scripts` — listet alle aktuell registrierten Scripts.
- `pipeline_run` — verkettet mehrere Script-Aufrufe (`${var}`-Interpolation aus `outputs_as`).

## Deployment & Konfiguration

Registry-Server auf dem zentralen Host bauen/deployen (Host via Env oder untracked
`.deploy.env` setzen — `HOST=<ssh-host> REMOTE_DIR=<pfad>`):

```bash
HOST=my-host ./deploy-registry.sh   # tsc → scp → docker compose up -d --build
# Endpoint: http://<host>:3457  (/health, /registry, /registry/file)
```

Client (MCP-Eintrag in `~/.claude.json`) auf Registry-Modus stellen:

```json
"tools": {
  "type": "stdio",
  "command": "node",
  "args": ["/pfad/zu/tools-mcp/dist/index.js"],
  "env": { "TOOLS_MCP_REGISTRY_URL": "http://<host>:3457" }
}
```

### Relevante Env-Variablen

| Variable | Wirkung |
|---|---|
| `TOOLS_MCP_REGISTRY_URL` | aktiviert den Registry-Client (Katalog-Quelle). Ungesetzt → lokales `scripts/`. |
| `TOOLS_MCP_SCRIPTS_DIR` | lokales Script-Verzeichnis (Dev-Fallback / Quelle des Registry-Servers). |
| `TOOLS_MCP_CACHE_DIR` | lokaler Cache (Default `~/.cache/tools-mcp/scripts`). |
| `TOOLS_MCP_POLL_MS` | Poll-Intervall des Live-Reloads (Default `5000`). |
| `TOOLS_MCP_RUNS_DIR` | Wurzel der Run-Dirs (Default `/tmp/tools-runs`). |
| `PORT` / `HOST` | Registry-Server (Default `3457` / `0.0.0.0`). |

## Build

```bash
npm install
npm run build      # tsc → dist/  (Entrypoints: dist/index.js, dist/registry-server.js)
```

## Verwandte Projekte

- [ai-rem](https://github.com/markus7h/ai-rem) — Langzeit-Gedächtnis als Knowledge-Graph-MCP. Pro Script wird per `ai_rem_entity`-Konvention eine `Tool`-Entity gepflegt, damit der Katalog auffindbar bleibt.
- [mykeyvault](https://github.com/markus7h/mykeyvault) — self-hosted Secrets-Vault (Vaultwarden + REST/MCP). Script-Secrets werden über die mykeyvault-vault-api bezogen, statt sie in Scripts oder Configs abzulegen.
