#!/usr/bin/env node
import { createServer, IncomingMessage, ServerResponse } from "node:http";
import { readFile, readdir } from "node:fs/promises";
import { join, resolve, relative, dirname, basename, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash } from "node:crypto";
import { loadScripts } from "./script-loader.js";

/**
 * Registry-Server: liefert das Script-Verzeichnis über HTTP aus, damit lokale
 * tools-mcp-Instanzen den Katalog ziehen und lokal cachen können — ein von SMB
 * unabhängiger Pfad. Läuft zentral (Container auf einem Host). Quelle = das per
 * Bind-Mount eingehängte scripts/-Verzeichnis (kein Rebuild bei Script-Änderung).
 *
 * Endpoints:
 *   GET /health                              -> "ok"
 *   GET /registry                            -> { version, scripts:[{name,manifest,files}] }
 *   GET /registry/file?script=<n>&path=<rel> -> Rohbytes einer Script-Datei
 */

const __dirname = dirname(fileURLToPath(import.meta.url));
const PROJECT_ROOT = join(__dirname, "..");
const SCRIPTS_ROOT = resolve(process.env.TOOLS_MCP_SCRIPTS_DIR ?? join(PROJECT_ROOT, "scripts"));
const PORT = Number(process.env.PORT ?? 3457);
const HOST = process.env.HOST ?? "0.0.0.0";

const NAME_RE = /^[A-Za-z0-9._-]+$/;

async function listFiles(dir: string, base = dir): Promise<string[]> {
  const out: string[] = [];
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) out.push(...(await listFiles(p, base)));
    else out.push(relative(base, p));
  }
  return out;
}

/** Baut den Katalog frisch aus der Platte; version = sha256 über alle Dateien. */
async function buildCatalog() {
  const scripts = (await loadScripts(SCRIPTS_ROOT)).sort((a, b) =>
    a.manifest.name.localeCompare(b.manifest.name)
  );
  const hash = createHash("sha256");
  const entries = [];
  for (const s of scripts) {
    // Identifier = Verzeichnisname (für Datei-Pfade). Der MCP-Tool-Name kommt
    // aus dem manifest, das der Client lokal aus dem Cache liest.
    const dir = basename(s.dir);
    const files = (await listFiles(s.dir)).sort();
    for (const rel of files) {
      const buf = await readFile(join(s.dir, rel));
      hash.update(dir).update("/").update(rel).update("\0").update(buf);
    }
    entries.push({ name: dir, manifest: s.manifest, files });
  }
  return { version: hash.digest("hex"), scripts: entries };
}

function send(res: ServerResponse, status: number, body: string | Buffer, type = "application/json") {
  res.writeHead(status, { "Content-Type": type });
  res.end(body);
}

async function handle(req: IncomingMessage, res: ServerResponse) {
  const url = new URL(req.url ?? "/", `http://${req.headers.host ?? "localhost"}`);

  if (req.method !== "GET") return send(res, 405, JSON.stringify({ error: "method not allowed" }));

  if (url.pathname === "/health") return send(res, 200, "ok", "text/plain");

  if (url.pathname === "/registry") {
    const cat = await buildCatalog();
    return send(res, 200, JSON.stringify(cat));
  }

  if (url.pathname === "/registry/file") {
    const script = url.searchParams.get("script") ?? "";
    const path = url.searchParams.get("path") ?? "";
    if (!NAME_RE.test(script)) return send(res, 400, JSON.stringify({ error: "invalid script" }));
    const scriptDir = resolve(SCRIPTS_ROOT, script);
    if (scriptDir !== SCRIPTS_ROOT && !scriptDir.startsWith(SCRIPTS_ROOT + sep)) {
      return send(res, 400, JSON.stringify({ error: "invalid script path" }));
    }
    const target = resolve(scriptDir, path);
    if (!target.startsWith(scriptDir + sep)) {
      return send(res, 400, JSON.stringify({ error: "path traversal" }));
    }
    try {
      const buf = await readFile(target);
      return send(res, 200, buf, "application/octet-stream");
    } catch {
      return send(res, 404, JSON.stringify({ error: "not found" }));
    }
  }

  return send(res, 404, JSON.stringify({ error: "not found" }));
}

const httpServer = createServer((req, res) => {
  handle(req, res).catch((err) => {
    process.stderr.write(`[tools-registry] error: ${String(err)}\n`);
    if (!res.headersSent) send(res, 500, JSON.stringify({ error: "internal" }));
  });
});

httpServer.listen(PORT, HOST, () => {
  process.stderr.write(`[tools-registry] serving ${SCRIPTS_ROOT} on http://${HOST}:${PORT}\n`);
});
