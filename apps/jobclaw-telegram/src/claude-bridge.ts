import { spawn } from "node:child_process";
import { config } from "./config.js";

export type BridgeResult =
  | { ok: true; stdout: string; stderr: string }
  | { ok: false; error: string };

/**
 * Telegram 사용자 메시지를 Claude CLI stdin으로 넘기고 stdout을 수집합니다.
 * Phase 1: `CLAUDE_CLI_COMMAND` 기본값 `claude` — PATH에 CLI가 없으면 실패 메시지를 반환합니다.
 */
export async function runClaudeCliBridge(userPrompt: string): Promise<BridgeResult> {
  return new Promise((resolve) => {
    const child = spawn(config.claudeCliCommand, [], {
      cwd: config.claudeCliCwd,
      env: { ...process.env },
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stdout = "";
    let stderr = "";
    child.stdout?.on("data", (d: Buffer) => {
      stdout += d.toString("utf8");
    });
    child.stderr?.on("data", (d: Buffer) => {
      stderr += d.toString("utf8");
    });
    child.on("error", (err) => {
      resolve({ ok: false, error: String(err.message ?? err) });
    });
    child.on("close", (code) => {
      if (code === 0) resolve({ ok: true, stdout, stderr });
      else
        resolve({
          ok: false,
          error: `CLI exited with ${code}. stderr: ${stderr || "(empty)"}`,
        });
    });
    child.stdin?.write(userPrompt, "utf8");
    child.stdin?.end();
  });
}
