import "dotenv/config";
import path from "node:path";

function envString(name: string, fallback?: string): string {
  const v = process.env[name];
  if (v !== undefined && v !== "") return v;
  if (fallback !== undefined) return fallback;
  throw new Error(`Missing required env: ${name}`);
}

export const config = {
  telegramBotToken: envString("TELEGRAM_BOT_TOKEN"),
  /** Public web app URL for 구독/로그인 안내 */
  jobstackWebUrl: process.env.JOBSTACK_WEB_URL ?? "http://localhost:3000",
  subscriptionMode:
    (process.env.JOBCLAW_SUBSCRIPTION_MODE as "open" | "allowlist" | "deny") ??
    "allowlist",
  /** Comma-separated Telegram numeric user ids */
  allowedTelegramIds: new Set(
    (process.env.JOBCLAW_ALLOWED_TELEGRAM_IDS ?? "")
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean)
      .map((s) => Number.parseInt(s, 10))
      .filter((n) => !Number.isNaN(n)),
  ),
  /** Optional: `claude` CLI or full path */
  claudeCliCommand: process.env.CLAUDE_CLI_COMMAND ?? "claude",
  /** Working directory for Claude CLI (often repo root) */
  claudeCliCwd: process.env.CLAUDE_CLI_CWD ?? process.cwd(),
  /** 기본: 앱 cwd 하위 `data/telegram-users.json` */
  userRegistryPath:
    process.env.JOBCLAW_USER_REGISTRY_PATH ??
    path.join(process.cwd(), "data", "telegram-users.json"),
};
