# tools-registry

MCP-Server, der kleine Scripts (`scripts/<name>/`) als MCP-Tools bereitstellt — mit
Run-Dirs, Pipeline-Runner und einer **zentralen Script-Registry**, sodass neue/entfernte
Scripts **ohne Neustart** verfügbar werden.

## Architektur

```
zentraler Host                                 Client (Mac etc.)
┌──────────────────────────────┐               ┌─────────────────────────────────┐
│ Registry-Server (Docker)     │   HTTP GET    │ tools-registry-Client (stdio)   │
│  = tools-registry-Container  │ ◀──────────── │  - zieht Katalog, cacht lokal   │
│  serve scripts/ über         │  Poll (5s)    │    ~/.cache/tools-registry/...  │
│  /registry + /file           │ ─────────────▶│  - registriert Tools live       │
│  Quelle = Bind-Mount scripts/│   Bytes       │  - führt Scripts LOKAL aus      │
└──────────────────────────────┘               └─────────────────────────────────┘
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

## Konvertier-Dienst (Teil B)

Manche Tools brauchen schwere Helfer (Chromium, LibreOffice, WeasyPrint, poppler). Die würden
sonst **auf jedem Client** liegen müssen — denn Scripts laufen Client-lokal, nicht im
Registry-Container. Stattdessen bündelt ein **zustandsloser Konvertier-Dienst** (`convert-service/`,
eigener Container auf dem zentralen Host) diese Helfer an **einem** Ort. Die Scripts sind dann
**dünne curl-Wrapper**: lokale Datei rein → fertige Datei raus.

```
Client (Mac/Linux/…)                       zentraler Host (LAN)
run.sh = curl-Wrapper   --POST Datei-->    tools-convert (Docker)
  liest lokale Datei      ?params           chromium · libreoffice · weasyprint
  schreibt output_path   <--Bytes-----      · pandoc · poppler + stdlib-HTTP-Server
                                            tools-registry (Docker, Fileserver scripts/)
```

- **Vorteil:** Clients brauchen nur `curl` — kein Tool-Zoo pro Host, kein Snap-Confinement.
  Lokaldatei-Zugriff bleibt, weil der Wrapper lokal läuft und nur die Bytes hoch-/runterlädt.
- **Trade-off (bewusst):** Konvertierung braucht Netz zum Dienst; offline = Fehler (kein
  Local-Fallback, sonst wären die Host-Deps zurück).
- **Endpunkte** (`convert-service/server.py`, Body = rohe Datei-Bytes, Antwort = Ergebnis-Bytes):
  `POST /html_to_pdf?theme=&landscape=&wait_ms=`, `POST /md_to_pdf?design=`, `POST /docx_to_pdf`
  (Metadaten in `X-Converter`/`X-Warning`), `POST /pdf_to_text?layout=`, `GET /health`.
- Diese Tools nutzen den Dienst: `html_to_pdf`, `md_to_pdf`, `docx_to_pdf`, `pdf_to_text`.

Deploy (Host via Env oder untracked `.deploy.env`):

```bash
HOST=my-host ./deploy-convert.sh    # scp convert-service/ → docker compose up -d --build
# Endpoint: http://<host>:3459  (Host-Port; 3458 = mykeyvault-mcp auf mystorage)
```

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

Das Exec-Script bekommt pro Input `INPUT_<NAME>` als Env-Var sowie `TOOLS_RUN_DIR`
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
  "args": ["/pfad/zu/tools-registry/dist/index.js"],
  "env": { "TOOLS_REGISTRY_URL": "http://<host>:3457" }
}
```

### Relevante Env-Variablen

| Variable | Wirkung |
|---|---|
| `TOOLS_REGISTRY_URL` | aktiviert den Registry-Client (Katalog-Quelle). Ungesetzt → lokales `scripts/`. |
| `TOOLS_REGISTRY_TOKEN` | Shared Bearer-Token. Server: gesetzt → alle Endpoints außer `/health` verlangen `Authorization: Bearer <token>`. Client: schickt es mit. |
| `TOOLS_SCRIPTS_DIR` | lokales Script-Verzeichnis (Dev-Fallback / Quelle des Registry-Servers). |
| `TOOLS_CACHE_DIR` | lokaler Cache (Default `~/.cache/tools-registry/scripts`). |
| `TOOLS_SCRIPT_ENV_PASSTHROUGH` | Komma-Liste zusätzlicher Env-Vars an Scripts (Default-Whitelist: `PATH, HOME, LANG, LC_*, TMPDIR, TERM, TZ, USER, SHELL`). |
| `TOOLS_POLL_MS` | Poll-Intervall des Live-Reloads (Default `5000`). |
| `TOOLS_RUNS_DIR` | Wurzel der Run-Dirs (Default `/tmp/tools-runs`). |
| `TOOLS_SCRIPT_TIMEOUT_MS` | Hard-Timeout je Script-Ausführung (Default `60000`). |
| `TOOLS_RUN_TTL_MS` | Max-Alter eines Run-Dirs; ältere werden beim Start entfernt (Default `86400000` = 24h). |
| `PORT` / `HOST` | Registry-Server (Default `3457` / `0.0.0.0`). |
| `TOOLS_CONVERT_URL` | Basis-URL des Konvertier-Dienstes für die curl-Wrapper (Default `http://192.168.2.15:3459`). Override braucht Eintrag in `TOOLS_SCRIPT_ENV_PASSTHROUGH`. |
| `TOOLS_CONVERT_TOKEN` | Bearer-Token, das die Wrapper an den Dienst schicken (muss `CONVERT_TOKEN` des Dienstes entsprechen). |
| `CONVERT_TOKEN` / `CONVERT_PORT` | Konvertier-Dienst: optionales Bearer-Token (leer = aus) / Host-Port (Default `3459`; 3458 belegt). |

> **Sicherheit:** Der Client führt Katalog-Scripts **lokal aus** — die Registry darf daher nur im
> vertrauenswürdigen LAN erreichbar sein, nie auf einem öffentlichen Interface. `HOST` auf die
> LAN-IP statt `0.0.0.0` binden und `TOOLS_REGISTRY_TOKEN` setzen. (Katalog-Integrität per
> Signatur ist bewusst nicht implementiert — Upgrade-Pfad, falls die Registry je außerhalb des
> LAN läuft.)

## Discovery-Hook (UserPromptSubmit)

`hooks/tool-discovery.sh` (Python) ist ein Claude-Code-`UserPromptSubmit`-Hook. Er
schickt den Prompt an den ai-rem-`/discover`-Endpoint und injiziert dessen Antwort als
Kontext, damit Claude passende Tools/Playbooks nutzt statt Eigenlösungen zu bauen:

- **`<routines>`** — gepinnte Meta-Regeln aus ai-rem, *immer* (unabhängig vom Keyword-Match).
- **`<available-tools>` / `<relevant-knowledge>`** — relevanz-gematchte Treffer.
- **`<active-context>` / `<context-uncertain>`** — der aufgelöste privat/work-Kontext.

Endpoint + Bearer-Token werden aus `AI_REM_ENDPOINT` bzw. `~/.claude.json`
(`mcpServers.ai-rem`) abgeleitet. Der **privat/work-Kontext** wird hybrid bestimmt:

1. Override `~/.claude/.active-context` (Inhalt `work` oder `private`) — höchste Priorität.
2. sonst `cwd` gegen `~/.claude/context-map.json` (Pfad-Präfixe → Kontext, längster Treffer gewinnt).
3. kein Treffer → `private` + `<context-uncertain>`-Marker.

`~/.claude/context-map.json` (Beispiel):

```json
{ "work": ["/pfad/zu/work-root"], "private": ["/Users/<user>", "/pfad/zu/privat-root"] }
```

Der Hook ist fail-silent (nie `exit != 0`) — bei Fehler/leerem Prompt/kein Treffer
bleibt er still und blockiert den Prompt nie.

### Ausrollen & Registrieren

`dotclaude_install` (kind `hooks` oder `all`, `mode=apply`) kopiert `tool-discovery.sh`
an den **stabilen Pfad** `~/.claude/hooks/tool-discovery.sh` — so hängt `settings.json`
nicht mehr am Repo-Checkout-Pfad (`/Volumes` vs `/home`, Repo-Umbenennungen).

Die **Registrierung** in `~/.claude/settings.json` unter `hooks.UserPromptSubmit` bleibt
ein einmaliger manueller Schritt (der Installer editiert bewusst keine fremden Hook-Arrays).
Ist der Hook deployt, aber noch nicht registriert, gibt der Lauf einen prominenten
`AKTION ERFORDERLICH`-Block mit fertigem JSON aus (`registration_pending: true`). Zu
registrierender Block:

```json
{ "matcher": "", "hooks": [ { "type": "command",
  "command": "/Users/<user>/.claude/hooks/tool-discovery.sh", "timeout": 10000 } ] }
```

Absoluter Pfad (kein `~`), da der Hook via `/bin/sh` läuft. `settings-sync` (`mode=check`)
meldet das fehlende `UserPromptSubmit`-Event fortlaufend, bis registriert.

## MCP-Katalog (Plugin-Marketplace)

Dieses Repo ist zusätzlich ein nativer **Claude-Code-Plugin-Marketplace** — ein Katalog
aller eigenen MCP-Server, aus dem sich jeder Server mit einem Kommando in den passenden
Scope installieren lässt. Struktur getrennt vom Script-Registry-Teil:

- `.claude-plugin/marketplace.json` — der Katalog (Marketplace-Name `tools-registry`).
- `plugins/<name>/.claude-plugin/plugin.json` — ein Plugin = ein MCP-Server. Hosts, Tokens
  und Pfade sind ausschließlich `userConfig`-Platzhalter → **keine Secrets im Repo**.

Der Katalog ersetzt nicht die Regel „MCP minimal pro Repo": global bleibt schlank,
projektspezifische Server werden per `--scope project` on-demand gezogen.

```bash
claude plugin marketplace add markus7h/tools-registry   # oder lokaler Pfad
claude plugin install playwright@tools-registry --scope project      # ohne Secret
```

Server mit Secret beziehen den Token zur Install-Zeit aus [mykeyvault](https://github.com/markus7h/mykeyvault)
(`vault_write_secret` schreibt ihn in eine chmod-600-Datei, gibt nur den Pfad zurück):

```bash
# im Claude-Chat: vault_write_secret("<item>") -> $P
claude plugin install ai-rem@tools-registry --scope user \
  --config url=https://<host>/mcp --config token="$(cat "$P")"
rm -f "$P"
```

`sensitive: true`-Felder landen im System-Keychain, nicht in `settings.json`. Neuen Server
ergänzen: `plugins/<name>/.claude-plugin/plugin.json` anlegen + Eintrag in `marketplace.json`,
dann `claude plugin marketplace update tools-registry`.

## Build

```bash
npm install
npm run build      # tsc → dist/  (Entrypoints: dist/index.js, dist/registry-server.js)
```

## Verwandte Projekte

- [ai-rem](https://github.com/markus7h/ai-rem) — Langzeit-Gedächtnis als Knowledge-Graph-MCP. Pro Script wird per `ai_rem_entity`-Konvention eine `Tool`-Entity gepflegt, damit der Katalog auffindbar bleibt.
- [mykeyvault](https://github.com/markus7h/mykeyvault) — self-hosted Secrets-Vault (Vaultwarden + REST/MCP). Script-Secrets werden über die mykeyvault-vault-api bezogen, statt sie in Scripts oder Configs abzulegen.
