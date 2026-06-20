import { mkdir, writeFile, readFile, rm, readdir, chmod } from "node:fs/promises";
import { join, dirname, sep } from "node:path";
import { homedir } from "node:os";

/**
 * Registry-Client: holt den Script-Katalog von einem zentralen HTTP-Endpoint
 * (zentraler Host) und spiegelt ihn in einen lokalen Cache. Ausgeführt wird
 * immer aus dem lokalen Cache — so bleibt der MCP unabhängig vom SMB-Mount und
 * neue/entfernte Scripts werden ohne Neustart übernommen (siehe Poll-Loop in index.ts).
 */

export interface RegistryCatalogEntry {
  name: string;
  /** Manifest-Objekt (informativ; der Client liest das echte manifest.yaml aus dem Cache). */
  manifest?: unknown;
  /** Dateipfade relativ zum Script-Verzeichnis. */
  files: string[];
}

export interface RegistryCatalog {
  version: string;
  scripts: RegistryCatalogEntry[];
}

const DEFAULT_CACHE = join(homedir(), ".cache", "tools-mcp", "scripts");
const VERSION_FILE = ".registry-version";
/** Erlaubte Script-Verzeichnisnamen — identisch zur Server-Validierung in registry-server.ts. */
const NAME_RE = /^[A-Za-z0-9._-]+$/;

export function registryCacheDir(): string {
  return process.env.TOOLS_MCP_CACHE_DIR ?? DEFAULT_CACHE;
}

/** Liegt `target` innerhalb von `dir` (oder ist `dir` selbst)? Schutz gegen `../`-Pfade. */
export function isInside(dir: string, target: string): boolean {
  return target === dir || target.startsWith(dir + sep);
}

/** Gültiger Script-Verzeichnisname (kein `..`, kein `/`). */
export function isValidScriptName(name: string): boolean {
  return NAME_RE.test(name);
}

function withTimeout(ms: number): AbortSignal {
  return AbortSignal.timeout(ms);
}

/** Bearer-Header, falls TOOLS_MCP_REGISTRY_TOKEN gesetzt — sonst leeres Objekt. */
function authHeaders(): Record<string, string> {
  const token = process.env.TOOLS_MCP_REGISTRY_TOKEN;
  return token ? { Authorization: `Bearer ${token}` } : {};
}

/** Sentinel: Server meldet 304 (Katalog unverändert ggü. übergebener Version). */
export const NOT_MODIFIED = Symbol("not-modified");

export async function fetchCatalog(
  baseUrl: string,
  etag?: string | null
): Promise<RegistryCatalog | typeof NOT_MODIFIED> {
  const headers = authHeaders();
  if (etag) headers["If-None-Match"] = `"${etag}"`;
  const res = await fetch(new URL("/registry", baseUrl), { signal: withTimeout(5000), headers });
  if (res.status === 304) return NOT_MODIFIED;
  if (!res.ok) throw new Error(`registry GET /registry -> ${res.status}`);
  const cat = (await res.json()) as RegistryCatalog;
  if (!cat?.version || !Array.isArray(cat.scripts)) {
    throw new Error("registry: ungültiger Katalog (version/scripts fehlt)");
  }
  return cat;
}

async function fetchFile(baseUrl: string, script: string, path: string): Promise<Buffer> {
  const url = new URL("/registry/file", baseUrl);
  url.searchParams.set("script", script);
  url.searchParams.set("path", path);
  const res = await fetch(url, { signal: withTimeout(10000), headers: authHeaders() });
  if (!res.ok) throw new Error(`registry GET ${script}/${path} -> ${res.status}`);
  return Buffer.from(await res.arrayBuffer());
}

/**
 * Spiegelt den Katalog in den lokalen Cache: lädt geänderte/neue Dateien,
 * entfernt verschwundene Script-Ordner, setzt Exec-Bits und schreibt den
 * Versionsmarker. Wirft bei Netzwerkfehlern — Caller behält dann den alten Cache.
 */
export async function syncToCache(
  baseUrl: string,
  catalog: RegistryCatalog,
  cacheDir: string
): Promise<void> {
  await mkdir(cacheDir, { recursive: true });

  const wanted = new Set(catalog.scripts.map((s) => s.name));
  let existing: string[] = [];
  try {
    existing = (await readdir(cacheDir, { withFileTypes: true }))
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
  } catch {
    /* leerer Cache */
  }
  for (const name of existing) {
    if (!wanted.has(name)) await rm(join(cacheDir, name), { recursive: true, force: true });
  }

  for (const s of catalog.scripts) {
    // Server-Katalog wird nicht blind vertraut: bösartige name/rel-Pfade dürfen nicht
    // außerhalb des Cache schreiben (sonst beliebige Dateien überschreibbar → RCE).
    if (!isValidScriptName(s.name)) {
      process.stderr.write(`[tools-mcp] skip script with invalid name: ${s.name}\n`);
      continue;
    }
    const sdir = join(cacheDir, s.name);
    await mkdir(sdir, { recursive: true });
    for (const rel of s.files) {
      const target = join(sdir, rel);
      if (!isInside(sdir, target)) {
        process.stderr.write(`[tools-mcp] skip path traversal: ${s.name}/${rel}\n`);
        continue;
      }
      const buf = await fetchFile(baseUrl, s.name, rel);
      await mkdir(dirname(target), { recursive: true });
      await writeFile(target, buf);
      if (rel.endsWith(".sh") || rel.endsWith(".py")) await chmod(target, 0o755);
    }
  }

  await writeFile(join(cacheDir, VERSION_FILE), catalog.version, "utf8");
}

export async function readCachedVersion(cacheDir: string): Promise<string | null> {
  try {
    return (await readFile(join(cacheDir, VERSION_FILE), "utf8")).trim();
  } catch {
    return null;
  }
}
