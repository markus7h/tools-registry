---
name: tools-registry
description: "MUSS geprüft werden, bevor du für eine Aufgabe Bash-Kommandos, Ad-hoc-Scripts oder Eigenbau-Code schreibst — die tools-registry hat fertige, geprüfte MCP-Tools dafür. Deckt ab: Dokument-Konvertierung (Markdown/Word/HTML → PDF), PDF-Text-Extraktion, Datei-Previews, mehrstufige Pipelines, Settings-Sync, Token-Messung. Tools: docx_to_pdf, dotclaude_install, echo, env_align, head_lines, html_to_pdf, magic3_design_install, md_to_pdf, measure_savings, opencode_sync, paperless_tag_no_ocr, pdf_to_text, settings_sync, subagent_models."
---

# tools-registry: Registrierte Tools nutzen statt Eigenbau

Diese Tools laufen als MCP-Tools (`mcp__tools__*`) über den tools-registry-Server.
**Regel: Passt ein Tool zur Aufgabe, rufe es direkt auf — kein Bash-Äquivalent, kein Ad-hoc-Script.**
Die MCP-Tools sind deferred: vor dem ersten Aufruf per ToolSearch (`select:mcp__tools__<name>`) laden.

| Tool | Zweck | Inputs (fett = required) |
|---|---|---|
| `mcp__tools__docx_to_pdf` | Konvertiert eine Word-.docx-Datei in PDF (im zentralen Konvertier-Dienst). Bevorzugt LibreOffice headless (volle Layout-Treue inkl. Briefkopf/Kopf- und Fußzeilen); fällt sonst auf `pandoc` mit einer verfügbaren PDF-Engine (WeasyPrint/wkhtmltopdf/LaTeX) zurück — dann ohne exaktes Word-Layout. Gibt den PDF-Pfad und das verwendete Backend zurück. | **docx_path**, output_path |
| `mcp__tools__dotclaude_install` | Installiert/aktualisiert lokale Claude-Code-Assets (Agents, Skills und Hooks) unter ~/.claude/ aus der tools-registry-Registry. Agents -> ~/.claude/agents/<name>.md, Skills -> ~/.claude/skills/<name>/, Hooks -> ~/.claude/hooks/ (tool-discovery.sh an stabilen Pfad). mode=check zeigt nur Abweichungen, mode=apply schreibt die Dateien. kind filtert auf agents, skills oder hooks (default all). Der Hook wird nur deployt, nicht in settings.json registriert - fehlt der Eintrag, gibt der Lauf einen AKTION-ERFORDERLICH-Block aus (registration_pending). So lassen sich die hauseigenen Assets auf jedem System ohne manuelles Kopieren ausrollen. | mode, kind |
| `mcp__tools__echo` | Smoke-Test. Schreibt die übergebene Nachricht ins Run-Dir und gibt den Pfad zurück. | **msg** |
| `mcp__tools__env_align` | Gleicht Claude-Code-Plugins & Marketplaces eines Systems an eine Referenz an. Referenz = zweites System (SSH-Alias), lokale settings.json oder Manifest-JSON. Verglichen/synchronisiert werden enabledPlugins (aktivierte) und extraKnownMarketplaces. mode=check zeigt den Diff, mode=apply registriert fehlende Marketplaces und aktiviert fehlende Plugins (additiv; mit strict=true Voll-Spiegel inkl. Deaktivieren lokaler Extras). Aenderungen greifen nach Claude-Code-Neustart. | **reference**, mode, settings_path, strict |
| `mcp__tools__head_lines` | Liest die ersten N Zeilen einer Textdatei und schreibt sie ins run_dir. Nützlich als Preview-Step in Pipelines. | **text_file**, n |
| `mcp__tools__html_to_pdf` | Rendert eine HTML-Datei (inkl. JavaScript/Mermaid-Diagrammen) via Headless-Chromium im zentralen Konvertier-Dienst zu PDF. Optional theme=magic3 injiziert das magic3-Theme (hell, grüner Akzent | **html_path**, output_path, theme, landscape, wait_ms |
| `mcp__tools__magic3_design_install` | Installiert/aktualisiert den Claude-Code-Skill `magic3-design` (hauseigenes magic3-Design: IBCS/SUCCESS, heller Hintergrund, grüner Akzent #388E3C, Source Sans 3 +0,15 pt) lokal unter ~/.claude/skills/magic3-design/. mode=check zeigt nur Abweichungen, mode=apply schreibt die Dateien. So lässt sich der Skill auf jedem System mit tools-registry ohne manuelles Kopieren ausrollen. | mode, target_dir |
| `mcp__tools__md_to_pdf` | Konvertiert eine Markdown-Datei in eine formatierte PDF via Python markdown + WeasyPrint (im zentralen Konvertier-Dienst). Designs `collana` (oranges b-imtec, default), `magicM` (LaTeX-Serif, Seitennummerierung) und `magic3` (IBCS/SUCCESS, hell, grüner Akzent | **md_path**, output_path, design |
| `mcp__tools__measure_savings` | Misst die Token-Spar-Basis von ai-rem aus den lokalen Claude-Code-Transcripts (~/.claude/projects/*/*.jsonl): Transcript-Fenster, Sessions/Tag, Recall-Quote (Sessions die ai-rem nutzen), ai-rem-Tool-Calls und Retrieval-Payload (chars / ~4 ≈ Tokens) je Recall-Session, plus Monatsaufschlüsselung. Agent- Sidechains und Fast-leere Sessions werden übersprungen. Hinweis: Claude Code räumt Transcripts nach ~30 Tagen weg — das Fenster deckt nur ab, was noch auf der Platte liegt. | projects_dir |
| `mcp__tools__opencode_sync` | Installiert Plugins des tools-registry-Marketplace in opencode (das keinen Plugin-Marketplace kennt): liest marketplace.json + plugin.json und schreibt die mcpServers als "mcp"-Eintraege in eine opencode.json - global oder projekt-lokal (target=<projekt>/opencode.json, Regel "MCP minimal pro Repo"). Werte fuer ${user_config.*} kommen aus ~/.config/opencode/tools-registry.json (plugins.<name>.<feld>, plus optional _environment), sonst aus den Claude-Code- pluginConfigs, sonst aus dem Default. Secrets werden nie im Klartext geschrieben, sondern in chmod-600-Dateien unter <ziel-dir>/secrets/ abgelegt und per {file:} referenziert. ai-rem und mykeyvault verwaltet `ai-rem install`. mode=check zeigt den Diff, mode=apply schreibt (mit Backup). | mode, plugins, target, values_path, source |
| `mcp__tools__paperless_tag_no_ocr` | Taggt alle Paperless-Dokumente ohne OCR-Text (leerer content) mit einem Sammel-Tag und entfernt den Tag wieder, sobald ein Dokument doch Text bekommen hat. Macht die Luecke zwischen Paperless-Gesamtzahl und dem paperless-ai-Index sichtbar: textlose Dokumente (Fotos, Scans ohne OCR) werden bewusst nie eingebettet. Ohne apply=true nur Trockenlauf. Laeuft per ssh im paperless-ai-Container, der die Paperless-Credentials bereits als Env mitbringt. | apply, tag_name, host, container |
| `mcp__tools__pdf_to_text` | Extrahiert reinen Text aus einer PDF-Datei via pdftotext (poppler, im zentralen Konvertier-Dienst). Schreibt extracted.txt ins run_dir. | **pdf_path**, layout |
| `mcp__tools__settings_sync` | Vergleicht die lokale Claude Code settings.json mit dem settings-template.json. mode=check zeigt Abweichungen, mode=apply ergaenzt fehlende Eintraege. | mode, settings_path, template_path |
| `mcp__tools__subagent_models` | Schnelle Auskunft, welche Modelle die delegierten Subagenten genutzt haben (= greift die Modellwahl-Regel). Liest die Subagent-Transcripts unter ~/.claude/projects/<proj>/<session>/subagents/agent-*.jsonl und schluesselt pro Agent-Typ (Explore/general-purpose/Plan) x Modell-Familie nach Laeufen, Turns und Output-Tokens auf. scope=session = juengste Session, scope=all = alle Sessions. | scope, projects_dir |

## Ketten

Mehrstufige Abläufe (z. B. PDF → Text → Preview) laufen über `mcp__tools__pipeline_run`:
`${name}` in den inputs eines Schritts referenziert `outputs_as` eines vorigen Schritts.

## Details

Vollständige Parameter-Schemas zur Laufzeit: `mcp__tools__list_scripts`.

<!-- GENERIERT aus scripts/*/manifest.yaml via gen-skill.mjs — nicht von Hand editieren. -->
