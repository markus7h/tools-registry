import { readdir, readFile, stat } from "node:fs/promises";
import { join, resolve } from "node:path";
import { parse as parseYaml } from "yaml";
import { z, ZodTypeAny } from "zod";

export interface ScriptInput {
  type: "string" | "number" | "boolean" | "integer";
  description?: string;
  required?: boolean;
  default?: unknown;
}

export interface ScriptOutput {
  type: "string" | "number" | "boolean";
  description?: string;
}

export interface ScriptManifest {
  name: string;
  description: string;
  inputs: Record<string, ScriptInput>;
  outputs?: Record<string, ScriptOutput>;
  exec: string;
  requires?: string[];
  secrets?: string[];
  ai_rem_entity?: string;
}

export interface LoadedScript {
  manifest: ScriptManifest;
  dir: string;
  execPath: string;
}

export async function loadScripts(scriptsRoot: string): Promise<LoadedScript[]> {
  const entries = await readdir(scriptsRoot, { withFileTypes: true });
  const loaded: LoadedScript[] = [];

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const dir = join(scriptsRoot, entry.name);
    const manifestPath = join(dir, "manifest.yaml");

    try {
      await stat(manifestPath);
    } catch {
      continue;
    }

    const raw = await readFile(manifestPath, "utf8");
    const manifest = parseYaml(raw) as ScriptManifest;

    if (!manifest?.name || !manifest?.exec) {
      console.error(`[tools-mcp] skipping ${dir}: manifest missing name/exec`);
      continue;
    }

    const execPath = resolve(dir, manifest.exec);
    loaded.push({ manifest, dir, execPath });
  }

  return loaded;
}

export function inputsToZodShape(inputs: Record<string, ScriptInput>): Record<string, ZodTypeAny> {
  const shape: Record<string, ZodTypeAny> = {};
  for (const [key, spec] of Object.entries(inputs ?? {})) {
    let schema: ZodTypeAny;
    switch (spec.type) {
      case "number":
      case "integer":
        schema = z.number();
        break;
      case "boolean":
        schema = z.boolean();
        break;
      default:
        schema = z.string();
    }
    if (spec.description) schema = schema.describe(spec.description);
    if (!spec.required) schema = schema.optional();
    shape[key] = schema;
  }
  return shape;
}
