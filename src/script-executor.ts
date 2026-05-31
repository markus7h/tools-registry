import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { LoadedScript } from "./script-loader.js";
import { RunContext, readOutputs } from "./run-context.js";

const execFileAsync = promisify(execFile);

export interface ExecResult {
  status: "ok" | "error";
  run_id: string;
  run_dir: string;
  outputs?: Record<string, unknown>;
  stdout?: string;
  stderr?: string;
  error?: string;
}

export async function executeScript(
  script: LoadedScript,
  inputs: Record<string, unknown>,
  run: RunContext
): Promise<ExecResult> {
  const env: NodeJS.ProcessEnv = {
    ...process.env,
    TOOLS_MCP_RUN_DIR: run.dir,
    TOOLS_MCP_RUN_ID: run.runId,
    TOOLS_MCP_INPUTS_JSON: JSON.stringify(inputs),
  };

  for (const [k, v] of Object.entries(inputs)) {
    env[`INPUT_${k.toUpperCase()}`] = v === null || v === undefined ? "" : String(v);
  }

  try {
    const { stdout, stderr } = await execFileAsync(script.execPath, [], {
      cwd: script.dir,
      env,
      maxBuffer: 10 * 1024 * 1024,
    });
    const outputs = await readOutputs(run.dir);
    return {
      status: "ok",
      run_id: run.runId,
      run_dir: run.dir,
      outputs,
      stdout: stdout.trim().slice(0, 2000),
      stderr: stderr.trim().slice(0, 500) || undefined,
    };
  } catch (err: any) {
    return {
      status: "error",
      run_id: run.runId,
      run_dir: run.dir,
      error: err?.message ?? String(err),
      stdout: typeof err?.stdout === "string" ? err.stdout.slice(0, 2000) : undefined,
      stderr: typeof err?.stderr === "string" ? err.stderr.slice(0, 2000) : undefined,
    };
  }
}
