import { getDb, subscriptions } from "@jobstack/db";
import { eq } from "drizzle-orm";

type ProvisionResult =
  | { ok: true; agentId: string }
  | { ok: false; error: string; skipped?: boolean };

/**
 * 구독 결제 확정 후 Paperclip에 JobClaw용 에이전트 1명을 만든다.
 * `PAPERCLIP_PROVISION_BEARER_TOKEN` 등이 없으면 스킵(웹훅은 성공 처리).
 */
export async function provisionPaperclipAgentForJobClawUser(params: {
  userId: string;
  planKey: "basic" | "pro";
  userEmail: string | null;
}): Promise<ProvisionResult> {
  const base = process.env.PAPERCLIP_API_URL?.replace(/\/$/, "");
  const companyId = process.env.PAPERCLIP_COMPANY_ID?.trim();
  const token = process.env.PAPERCLIP_PROVISION_BEARER_TOKEN?.trim();
  if (!base || !companyId || !token) {
    return { ok: false, skipped: true, error: "missing_paperclip_env" };
  }

  const db = getDb();
  const [row] = await db
    .select({ metadata: subscriptions.metadata })
    .from(subscriptions)
    .where(eq(subscriptions.userId, params.userId))
    .limit(1);

  const meta = (row?.metadata ?? {}) as Record<string, unknown>;
  if (typeof meta.paperclipAgentId === "string" && meta.paperclipAgentId.length > 0) {
    return { ok: true, agentId: meta.paperclipAgentId };
  }

  const adapterType = process.env.PAPERCLIP_PROVISION_ADAPTER_TYPE?.trim() ?? "cursor";
  let adapterConfig: Record<string, unknown> = {};
  const rawCfg = process.env.PAPERCLIP_PROVISION_ADAPTER_CONFIG_JSON?.trim();
  if (rawCfg) {
    try {
      adapterConfig = JSON.parse(rawCfg) as Record<string, unknown>;
    } catch {
      return { ok: false, error: "invalid_PAPERCLIP_PROVISION_ADAPTER_CONFIG_JSON" };
    }
  }

  const reportsTo = process.env.PAPERCLIP_PROVISION_REPORTS_TO_AGENT_ID?.trim();
  const slugSuffix = params.userId.replace(/-/g, "").slice(0, 12);
  const name = `JobClaw-${params.planKey}-${slugSuffix}`;

  const body: Record<string, unknown> = {
    name,
    title: `JobClaw ${params.planKey}`,
    role: "general",
    adapterType,
    adapterConfig,
    metadata: {
      jobstackUserId: params.userId,
      jobstackPlan: params.planKey,
      source: "jobstack_webhook",
    },
  };
  if (reportsTo) {
    body.reportsTo = reportsTo;
  }

  let res: Response;
  try {
    res = await fetch(`${base}/api/companies/${companyId}/agents`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return { ok: false, error: `fetch_failed:${msg}` };
  }

  const text = await res.text();
  let json: { agent?: { id?: string }; error?: string } = {};
  try {
    json = JSON.parse(text) as typeof json;
  } catch {
    /* ignore */
  }

  if (!res.ok) {
    return {
      ok: false,
      error: `paperclip_http_${res.status}:${text.slice(0, 500)}`,
    };
  }

  const agentId = json.agent?.id;
  if (!agentId) {
    return { ok: false, error: "paperclip_response_missing_agent_id" };
  }

  const nextMeta: Record<string, unknown> = {
    ...meta,
    paperclipAgentId: agentId,
    paperclipProvisionedAt: new Date().toISOString(),
  };
  delete nextMeta.paperclipProvisionError;

  await db
    .update(subscriptions)
    .set({
      metadata: nextMeta,
      updatedAt: new Date(),
    })
    .where(eq(subscriptions.userId, params.userId));

  return { ok: true, agentId };
}

export async function recordPaperclipProvisionFailure(
  userId: string,
  error: string,
): Promise<void> {
  const db = getDb();
  const [row] = await db
    .select({ metadata: subscriptions.metadata })
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId))
    .limit(1);
  const meta = { ...((row?.metadata ?? {}) as Record<string, unknown>) };
  meta.paperclipProvisionError = error;
  meta.paperclipProvisionAttemptAt = new Date().toISOString();

  await db
    .update(subscriptions)
    .set({
      metadata: meta,
      updatedAt: new Date(),
    })
    .where(eq(subscriptions.userId, userId));
}
