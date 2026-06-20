#!/usr/bin/env node
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { z } from "zod";
import { loadScripts, inputsToZodShape, LoadedScript } from "./script-loader.js";
import { ensureRun, gcRuns } from "./run-context.js";
import { executeScript } from "./script-executor.js";
import { runPipeline, PipelineSpec } from "./pipeline-runner.js";
import { fetchCatalog, syncToCache, registryCacheDir, NOT_MODIFIED } from "./registry.js";

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..");

// Script-Quelle: zentrale Registry (HTTP) ODER lokales Verzeichnis (Dev/Fallback).
// Bei gesetzter REGISTRY_URL wird der Katalog in den lokalen Cache gespiegelt und
// von dort geladen — Ausführung bleibt lokal, unabhängig vom SMB-Mount.
const REGISTRY_URL = process.env.TOOLS_MCP_REGISTRY_URL;
const LOCAL_SCRIPTS_DIR = process.env.TOOLS_MCP_SCRIPTS_DIR ?? join(PROJECT_ROOT, "scripts");
const CACHE_DIR = registryCacheDir();
const SOURCE_DIR = REGISTRY_URL ? CACHE_DIR : LOCAL_SCRIPTS_DIR;
const POLL_MS = Number(process.env.TOOLS_MCP_POLL_MS ?? 5000);

const server = new McpServer({
  name: "tools-mcp",
  version: "0.1.0",
});

// Laufzeit-Registry: Name -> Script + zugehöriges SDK-Tool-Handle (für remove/update).
const scriptsByName = new Map<string, LoadedScript>();
type ToolHandle = ReturnType<typeof server.tool>;
const handlesByName = new Map<string, ToolHandle>();

const RESERVED = new Set(["list_scripts", "pipeline_run"]);

function manifestSig(s: LoadedScript): string {
  return JSON.stringify(s.manifest);
}

function registerScript(script: LoadedScript): void {
  const { manifest } = script;
  if (RESERVED.has(manifest.name)) {
    process.stderr.write(`[tools-mcp] skip reserved name: ${manifest.name}\n`);
    return;
  }
  const shape = inputsToZodShape(manifest.inputs ?? {});
  shape.run_id = z.string().optional().describe("Existing run_id to chain steps; new one is created if omitted.");

  const handle = server.tool(
    manifest.name,
    manifest.description,
    shape,
    async (args: Record<string, unknown>) => {
      const { run_id: runIdArg, ...inputs } = args;
      const run = await ensureRun(typeof runIdArg === "string" ? runIdArg : undefined);
      // Immer das aktuell registrierte Script verwenden (kann nach Reload getauscht sein).
      const current = scriptsByName.get(manifest.name) ?? script;
      const result = await executeScript(current, inputs, run);
      return {
        content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
        isError: result.status === "error",
      };
    }
  );
  scriptsByName.set(manifest.name, script);
  handlesByName.set(manifest.name, handle);
}

/**
 * Gleicht die laufende Tool-Registrierung an den frischen Script-Stand an:
 * fügt neue hinzu, entfernt verschwundene, re-registriert bei geändertem Manifest.
 * Jede Mutation triggert via SDK automatisch notifications/tools/list_changed.
 */
function applyScripts(fresh: LoadedScript[]): void {
  const freshByName = new Map(fresh.map((s) => [s.manifest.name, s]));

  for (const name of [...scriptsByName.keys()]) {
    if (!freshByName.has(name)) {
      handlesByName.get(name)?.remove();
      handlesByName.delete(name);
      scriptsByName.delete(name);
      process.stderr.write(`[tools-mcp] -${name}\n`);
    }
  }

  for (const s of fresh) {
    const name = s.manifest.name;
    const prev = scriptsByName.get(name);
    if (!prev) {
      registerScript(s);
      process.stderr.write(`[tools-mcp] +${name}\n`);
    } else if (manifestSig(prev) !== manifestSig(s)) {
      handlesByName.get(name)?.remove();
      handlesByName.delete(name);
      scriptsByName.delete(name);
      registerScript(s);
      process.stderr.write(`[tools-mcp] ~${name}\n`);
    } else {
      // Manifest unverändert: nur die Script-Referenz (Pfade) aktualisieren.
      scriptsByName.set(name, s);
    }
  }
}

let lastVersion: string | null = null;

/** Holt frischen Script-Stand aus Registry (mit Cache-Sync) oder lokalem Dir. */
async function loadFresh(): Promise<LoadedScript[] | null> {
  if (REGISTRY_URL) {
    const cat = await fetchCatalog(REGISTRY_URL, lastVersion);
    if (cat === NOT_MODIFIED || cat.version === lastVersion) return null; // unverändert (304 oder gleicher Hash)
    await syncToCache(REGISTRY_URL, cat, CACHE_DIR);
    lastVersion = cat.version;
    return await loadScripts(CACHE_DIR);
  }
  return await loadScripts(SOURCE_DIR);
}

// Alte Run-Dirs aufräumen (best effort, blockiert den Start nicht bei Fehlern).
gcRuns()
  .then((n) => n > 0 && process.stderr.write(`[tools-mcp] gc: ${n} alte run-dir(s) entfernt\n`))
  .catch(() => {});

// ── Initiales Laden ──────────────────────────────────────────────────────────
try {
  const initial = await loadFresh();
  if (initial) applyScripts(initial);
} catch (err) {
  // Registry beim Start nicht erreichbar → vorhandenen Cache verwenden.
  process.stderr.write(`[tools-mcp] initial load failed (${String(err)}); falling back to cache ${CACHE_DIR}\n`);
  try {
    applyScripts(await loadScripts(SOURCE_DIR));
  } catch {
    process.stderr.write(`[tools-mcp] no scripts available yet\n`);
  }
}

// ── Meta-Tools ───────────────────────────────────────────────────────────────
server.tool(
  "list_scripts",
  "Listet alle aktuell registrierten Scripts mit Manifest-Eckdaten.",
  {},
  async () => {
    const summary = [...scriptsByName.values()].map((s) => ({
      name: s.manifest.name,
      description: s.manifest.description,
      inputs: Object.keys(s.manifest.inputs ?? {}),
      requires: s.manifest.requires ?? [],
      secrets: s.manifest.secrets ?? [],
      ai_rem_entity: s.manifest.ai_rem_entity,
    }));
    return { content: [{ type: "text", text: JSON.stringify(summary, null, 2) }] };
  }
);

server.tool(
  "pipeline_run",
  "Führt eine Sequenz von Script-Aufrufen aus. Variable ${name} im inputs eines Schritts wird aus outputs_as eines vorigen Schritts gefüllt. Zwischen-Artefakte bleiben als Dateien im run_dir und kommen nicht zurück.",
  {
    run_id: z.string().optional().describe("Optional: existierende run_id wiederverwenden."),
    steps: z
      .array(
        z.object({
          tool: z.string().describe("Script-Name aus list_scripts."),
          inputs: z.record(z.string(), z.unknown()).optional().describe("Inputs für das Tool; ${var} Tokens werden interpoliert."),
          outputs_as: z
            .record(z.string(), z.string())
            .optional()
            .describe("Map von Output-Key → Variablen-Name für nachfolgende Schritte."),
        })
      )
      .min(1)
      .describe("Pipeline-Schritte in Ausführungsreihenfolge."),
  },
  async (args) => {
    const spec: PipelineSpec = args as PipelineSpec;
    const result = await runPipeline(spec, scriptsByName);
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      isError: result.status === "error",
    };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);

// ── Live-Reload: Poll-Loop (SMB-tauglich, ersetzt fs.watch) ───────────────────
// Holt periodisch frischen Stand und gleicht die Tool-Liste live ab.
setInterval(async () => {
  try {
    const fresh = await loadFresh();
    if (fresh) applyScripts(fresh);
  } catch (err) {
    process.stderr.write(`[tools-mcp] reload poll error: ${String(err)}\n`);
  }
}, POLL_MS).unref();
