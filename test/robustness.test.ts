/**
 * Self-checks für die Robustheits-Fixes (Issues #3, #4).
 * Lauf:  node node_modules/tsx/dist/cli.mjs test/robustness.test.ts
 */
import { strict as assert } from "node:assert";
import { mkdir, writeFile, readdir, utimes, chmod } from "node:fs/promises";
import { join } from "node:path";
import { tmpdir } from "node:os";

// #4 GC alter Run-Dirs
const root = join(tmpdir(), "gc-test-" + process.pid);
process.env.TOOLS_MCP_RUNS_DIR = root;
const { gcRuns } = await import("../src/run-context.js");
await mkdir(join(root, "old"), { recursive: true });
await mkdir(join(root, "new"), { recursive: true });
const past = new Date(Date.now() - 48 * 3600 * 1000);
await utimes(join(root, "old"), past, past);
assert.equal(await gcRuns(), 1, "ein altes run-dir entfernt");
assert.deepEqual(await readdir(root), ["new"], "nur das junge bleibt");

// #3 Script-Timeout
process.env.TOOLS_MCP_SCRIPT_TIMEOUT_MS = "300";
const d = join(tmpdir(), "to-test-" + process.pid);
await mkdir(d, { recursive: true });
const exe = join(d, "run.sh");
await writeFile(exe, "#!/usr/bin/env bash\nsleep 5\n");
await chmod(exe, 0o755);
const { executeScript } = await import("../src/script-executor.js");
const { ensureRun } = await import("../src/run-context.js");
const t0 = Date.now();
const res = await executeScript({ dir: d, execPath: exe, manifest: { name: "t" } } as any, {}, await ensureRun());
assert.equal(res.status, "error", "Timeout liefert status=error");
assert.ok(Date.now() - t0 < 2000, "vor sleep-Ende abgebrochen");

console.log("ok: robustness self-checks passed");
