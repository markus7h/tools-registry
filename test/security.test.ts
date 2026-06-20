/**
 * Self-checks für die Security-Härtung (Issues #1, #2, #6).
 * Lauf:  node node_modules/tsx/dist/cli.mjs test/security.test.ts
 */
import { strict as assert } from "node:assert";
import { join } from "node:path";
import { isInside, isValidScriptName } from "../src/registry.js";
import { baseEnv } from "../src/script-executor.js";

// #2 Path-Traversal-Guard
const cache = "/home/u/.cache/tools-mcp/scripts/foo";
assert.ok(isInside(cache, join(cache, "run.sh")), "normale Datei ist drin");
assert.ok(isInside(cache, join(cache, "sub/a.py")), "Unterordner ist drin");
assert.ok(!isInside(cache, join(cache, "../../.bashrc")), "../-Pfad fliegt raus");
assert.ok(isValidScriptName("magic3-design"), "gültiger Name");
assert.ok(!isValidScriptName("../x"), "Name mit .. abgewiesen");
assert.ok(!isValidScriptName("a/b"), "Name mit / abgewiesen");

// #6 Env-Whitelist
process.env.FAKE_SECRET = "leak-me";
process.env.LC_FOO = "x";
process.env.MY_EXTRA = "ok";
process.env.TOOLS_MCP_SCRIPT_ENV_PASSTHROUGH = "MY_EXTRA";
const env = baseEnv();
assert.ok(env.PATH !== undefined, "PATH durchgereicht");
assert.equal(env.FAKE_SECRET, undefined, "Secret NICHT durchgereicht");
assert.equal(env.LC_FOO, "x", "LC_*-Prefix durchgereicht");
assert.equal(env.MY_EXTRA, "ok", "Passthrough-Var durchgereicht");

console.log("ok: security self-checks passed");
