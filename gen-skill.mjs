#!/usr/bin/env node
// Generiert plugins/tools/skills/tools-registry/SKILL.md aus scripts/*/manifest.yaml.
// Aufruf: npm run gen:skill (läuft auch in deploy-registry.sh).
import { readdirSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parse } from "yaml";

const root = dirname(fileURLToPath(import.meta.url));
const scriptsDir = join(root, "scripts");
const outFile = join(root, "plugins/tools/skills/tools-registry/SKILL.md");

const manifests = readdirSync(scriptsDir, { withFileTypes: true })
  .filter((d) => d.isDirectory())
  .map((d) => parse(readFileSync(join(scriptsDir, d.name, "manifest.yaml"), "utf8")))
  .sort((a, b) => a.name.localeCompare(b.name));

if (manifests.length === 0) throw new Error(`keine Manifeste unter ${scriptsDir} gefunden`);

const toolNames = manifests.map((m) => m.name).join(", ");

const rows = manifests
  .map((m) => {
    const inputs = Object.entries(m.inputs ?? {})
      .map(([k, v]) => (v.required ? `**${k}**` : k))
      .join(", ");
    const desc = m.description.replace(/\s+/g, " ").replace(/\|/g, "\\|").trim();
    return `| \`mcp__tools__${m.name}\` | ${desc} | ${inputs} |`;
  })
  .join("\n");

const skill = `---
name: tools-registry
description: "MUSS geprüft werden, bevor du für eine Aufgabe Bash-Kommandos, Ad-hoc-Scripts oder Eigenbau-Code schreibst — die tools-registry hat fertige, geprüfte MCP-Tools dafür. Deckt ab: Dokument-Konvertierung (Markdown/Word/HTML → PDF), PDF-Text-Extraktion, Datei-Previews, mehrstufige Pipelines, Settings-Sync, Token-Messung. Tools: ${toolNames}."
---

# tools-registry: Registrierte Tools nutzen statt Eigenbau

Diese Tools laufen als MCP-Tools (\`mcp__tools__*\`) über den tools-registry-Server.
**Regel: Passt ein Tool zur Aufgabe, rufe es direkt auf — kein Bash-Äquivalent, kein Ad-hoc-Script.**
Die MCP-Tools sind deferred: vor dem ersten Aufruf per ToolSearch (\`select:mcp__tools__<name>\`) laden.

| Tool | Zweck | Inputs (fett = required) |
|---|---|---|
${rows}

## Ketten

Mehrstufige Abläufe (z. B. PDF → Text → Preview) laufen über \`mcp__tools__pipeline_run\`:
\`\${name}\` in den inputs eines Schritts referenziert \`outputs_as\` eines vorigen Schritts.

## Details

Vollständige Parameter-Schemas zur Laufzeit: \`mcp__tools__list_scripts\`.

<!-- GENERIERT aus scripts/*/manifest.yaml via gen-skill.mjs — nicht von Hand editieren. -->
`;

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, skill);
console.log(`SKILL.md generiert: ${manifests.length} Tools → ${outFile}`);
