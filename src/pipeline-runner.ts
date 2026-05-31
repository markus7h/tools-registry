import { writeFile } from "node:fs/promises";
import { join } from "node:path";
import { LoadedScript } from "./script-loader.js";
import { ensureRun } from "./run-context.js";
import { executeScript, ExecResult } from "./script-executor.js";

export interface PipelineStep {
  tool: string;
  inputs?: Record<string, unknown>;
  outputs_as?: Record<string, string>;
}

export interface PipelineSpec {
  run_id?: string;
  steps: PipelineStep[];
}

export interface StepResult {
  step: number;
  tool: string;
  status: "ok" | "error";
  outputs?: Record<string, unknown>;
  bound?: Record<string, unknown>;
  error?: string;
  stdout?: string;
  stderr?: string;
}

export interface PipelineResult {
  run_id: string;
  run_dir: string;
  status: "ok" | "error";
  steps: StepResult[];
  final_outputs: Record<string, unknown>;
}

/**
 * Ersetzt ${var} Tokens in einem String durch Variablenwerte.
 * Wenn der gesamte String genau "${var}" ist, wird der typisierte Wert
 * zurückgegeben (Number/Boolean/Object), sonst String-Interpolation.
 */
function interpolate(value: unknown, vars: Record<string, unknown>): unknown {
  if (typeof value !== "string") return value;
  const exactMatch = value.match(/^\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}$/);
  if (exactMatch) {
    const name = exactMatch[1];
    if (!(name in vars)) throw new Error(`Pipeline-Variable nicht definiert: ${name}`);
    return vars[name];
  }
  return value.replace(/\$\{([a-zA-Z_][a-zA-Z0-9_]*)\}/g, (_, name: string) => {
    if (!(name in vars)) throw new Error(`Pipeline-Variable nicht definiert: ${name}`);
    return String(vars[name]);
  });
}

function interpolateInputs(inputs: Record<string, unknown>, vars: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(inputs)) {
    out[k] = interpolate(v, vars);
  }
  return out;
}

export async function runPipeline(
  spec: PipelineSpec,
  scriptsByName: Map<string, LoadedScript>
): Promise<PipelineResult> {
  const run = await ensureRun(spec.run_id);
  const vars: Record<string, unknown> = {};
  const stepResults: StepResult[] = [];

  for (let i = 0; i < spec.steps.length; i++) {
    const step = spec.steps[i];
    const script = scriptsByName.get(step.tool);
    if (!script) {
      const result: StepResult = {
        step: i,
        tool: step.tool,
        status: "error",
        error: `Unbekanntes Tool: ${step.tool}`,
      };
      stepResults.push(result);
      await persistManifest(run.dir, spec, stepResults, vars);
      return {
        run_id: run.runId,
        run_dir: run.dir,
        status: "error",
        steps: stepResults,
        final_outputs: vars,
      };
    }

    let resolvedInputs: Record<string, unknown>;
    try {
      resolvedInputs = interpolateInputs(step.inputs ?? {}, vars);
    } catch (err: any) {
      stepResults.push({
        step: i,
        tool: step.tool,
        status: "error",
        error: err?.message ?? String(err),
      });
      await persistManifest(run.dir, spec, stepResults, vars);
      return {
        run_id: run.runId,
        run_dir: run.dir,
        status: "error",
        steps: stepResults,
        final_outputs: vars,
      };
    }

    const exec = await executeScript(script, resolvedInputs, run);
    const bound: Record<string, unknown> = {};
    if (exec.status === "ok" && exec.outputs && step.outputs_as) {
      for (const [outKey, varName] of Object.entries(step.outputs_as)) {
        if (outKey in exec.outputs) {
          vars[varName] = (exec.outputs as Record<string, unknown>)[outKey];
          bound[varName] = vars[varName];
        }
      }
    }

    const stepResult: StepResult = {
      step: i,
      tool: step.tool,
      status: exec.status,
      outputs: exec.outputs,
      bound: Object.keys(bound).length ? bound : undefined,
      error: exec.error,
      stdout: exec.stdout,
      stderr: exec.stderr,
    };
    stepResults.push(stepResult);

    if (exec.status === "error") {
      await persistManifest(run.dir, spec, stepResults, vars);
      return {
        run_id: run.runId,
        run_dir: run.dir,
        status: "error",
        steps: stepResults,
        final_outputs: vars,
      };
    }
  }

  await persistManifest(run.dir, spec, stepResults, vars);
  return {
    run_id: run.runId,
    run_dir: run.dir,
    status: "ok",
    steps: stepResults,
    final_outputs: vars,
  };
}

async function persistManifest(
  runDir: string,
  spec: PipelineSpec,
  stepResults: StepResult[],
  vars: Record<string, unknown>
): Promise<void> {
  const manifest = {
    spec,
    steps: stepResults,
    final_outputs: vars,
    persisted_at: new Date().toISOString(),
  };
  await writeFile(join(runDir, "pipeline.manifest.json"), JSON.stringify(manifest, null, 2), "utf8");
}
