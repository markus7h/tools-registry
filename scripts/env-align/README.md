# env-align — zwei Claude-Code-Systeme angleichen

Gleicht **Plugins** (`enabledPlugins`) und **Marketplaces** (`extraKnownMarketplaces`)
eines Systems an eine Referenz an. Referenz = zweites System (SSH-Alias), eine
`settings.json` oder ein Manifest-JSON.

Motivation: Die Reload-Meldung `Reloaded: … N hooks` zählt **Plugin-Hooks**.
Fehlen auf System A Plugins, die auf System B aktiv sind (z. B. `superpowers`,
`ponytail`), fehlen dort auch deren Session-Hooks. env-align macht diesen Drift
sichtbar und behebt ihn.

## Nutzung (MCP-Tool `env_align`)

```jsonc
// Diff anzeigen — was fehlt lokal gegenüber myubuntu?
{ "reference": "myubuntu", "mode": "check" }

// Angleichen (additiv): fehlende Marketplaces registrieren + Plugins aktivieren
{ "reference": "myubuntu", "mode": "apply" }

// Voll-Spiegel: zusätzlich lokal-only Plugins deaktivieren
{ "reference": "myubuntu", "mode": "apply", "strict": "true" }
```

Referenz-Auflösung: existiert `reference` als Datei → direkt lesen; sonst als
SSH-Host behandeln (`ssh <ref> cat ~/.claude/settings.json`).

**Additiv (Default):** nur Fehlendes wird ergänzt; lokale Extras (z. B. ein nur
auf dem Mac installiertes `mykeyvault`) bleiben erhalten.
**strict:** echter Spiegel — lokal aktive, in der Referenz unbekannte Plugins
werden deaktiviert.

`apply` schreibt vorher ein Backup `settings.json.bak-envalign`.

## Wichtig: Neustart

Plugin-/Marketplace-Änderungen greifen erst nach **Claude-Code-Neustart** — beim
Start installiert Claude Code aktivierte Plugins automatisch aus
`extraKnownMarketplaces` (Marketplace wird bei Bedarf selbst geklont, kein
manueller `git clone` nötig). Danach `/plugin` bzw. `/reload-plugins` zeigt die
neue Hook-Zahl.

## Was NICHT abgeglichen wird

`hooks`-Block in `settings.json`, Permissions, Env, Skills/Agents. Dafür:
- `settings_sync` — settings.json gegen `settings-template.json`
- `dotclaude_install` — Agents/Skills/Hooks aus der Registry lokal ausrollen

## Manuelles Runbook (ohne Tool)

1. Referenz lesen: `ssh <host> cat ~/.claude/settings.json` → `enabledPlugins`
   (true) und `extraKnownMarketplaces` notieren.
2. Lokal in `~/.claude/settings.json`:
   - fehlende Marketplace-Einträge in `extraKnownMarketplaces` ergänzen
     (`source: {source: github, repo: "owner/repo"}` bzw. `directory`/`path`);
   - fehlende Plugins in `enabledPlugins` auf `true` setzen
     (Schlüssel: `<plugin>@<marketplace>`).
3. JSON validieren: `python3 -c "import json;json.load(open('…/settings.json'))"`.
4. Claude Code neu starten → Auto-Install → `/plugin` prüfen.

Private GitHub-Marketplaces brauchen Zugriff: öffentliche Repos gehen per HTTPS
ohne Auth; für private einen deploybaren SSH-Key/Token hinterlegen.
