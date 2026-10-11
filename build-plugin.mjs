// Bündelt den tools-MCP-Server samt Abhängigkeiten in eine Datei im Plugin
// (plugins/tools/server/index.mjs) — das Plugin läuft so ohne Klon, Build und node_modules.
import { build } from "esbuild";

await build({
    entryPoints: ["src/index.ts"],
    outfile: "plugins/tools/server/index.mjs",
    bundle: true,
    platform: "node",
    format: "esm",
    target: "node20",
    legalComments: "none",
    // CJS-Abhängigkeiten im ESM-Bundle brauchen ein echtes require.
    banner: { js: 'import { createRequire as __cr } from "node:module"; const require = __cr(import.meta.url);' },
    logLevel: "warning",
});
