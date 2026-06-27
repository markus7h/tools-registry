import { mkdir, readFile, writeFile, stat, readdir, rm } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

const RUNS_ROOT = process.env.TOOLS_RUNS_DIR ?? "/tmp/tools-runs";

export interface RunContext {
  runId: string;
  dir: string;
}

export async function ensureRun(runId?: string): Promise<RunContext> {
  const id = runId && runId !== "auto" ? runId : randomUUID();
  const dir = join(RUNS_ROOT, id);
  await mkdir(dir, { recursive: true });
  return { runId: id, dir };
}

/**
 * Entfernt Run-Dirs, die älter als `maxAgeMs` sind (mtime). Best effort —
 * Fehler einzelner Einträge werden ignoriert. Beim Start aufgerufen, damit
 * /tmp/tools-runs nicht unbegrenzt wächst. Default-TTL: 24h.
 */
export async function gcRuns(
  maxAgeMs = Number(process.env.TOOLS_RUN_TTL_MS ?? 24 * 60 * 60 * 1000)
): Promise<number> {
  const cutoff = Date.now() - maxAgeMs;
  let removed = 0;
  let entries: string[];
  try {
    entries = await readdir(RUNS_ROOT);
  } catch {
    return 0; // Root existiert noch nicht
  }
  for (const name of entries) {
    const p = join(RUNS_ROOT, name);
    try {
      if ((await stat(p)).mtimeMs < cutoff) {
        await rm(p, { recursive: true, force: true });
        removed++;
      }
    } catch {
      /* einzelnen Eintrag überspringen */
    }
  }
  return removed;
}

/**
 * Liest outputs.json aus dem run_dir. Scripts dürfen sie schreiben um
 * benannte Output-Artefakte (Pfade, IDs, Zahlen) deklarativ zurückzugeben.
 * Pfade in outputs.json sollten relativ zum run_dir oder absolut sein.
 */
export async function readOutputs(runDir: string): Promise<Record<string, unknown> | undefined> {
  const path = join(runDir, "outputs.json");
  try {
    await stat(path);
  } catch {
    return undefined;
  }
  const raw = await readFile(path, "utf8");
  try {
    return JSON.parse(raw);
  } catch (err) {
    throw new Error(`outputs.json in ${runDir} ist kein gültiges JSON: ${(err as Error).message}`);
  }
}

/**
 * Schreibt outputs.json — vom Pipeline-Runner und ggf. Helper-CLIs genutzt.
 */
export async function writeOutputs(runDir: string, outputs: Record<string, unknown>): Promise<void> {
  await writeFile(join(runDir, "outputs.json"), JSON.stringify(outputs, null, 2), "utf8");
}
