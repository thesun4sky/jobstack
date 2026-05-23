import { getDb, subscriptions } from "@jobstack/db";
import { eq } from "drizzle-orm";

export type EffectivePlan = {
  planKey: "free" | "basic" | "pro";
  subscriptionStatus: string | null;
  /** DB row exists (plan may still be free if 만료/취소). */
  hasSubscriptionRow: boolean;
  /** Paperclip 에이전트 id (구독 metadata). */
  paperclipAgentId: string | null;
  paperclipProvisionError: string | null;
};

const PAID_ACTIVE = new Set(["active", "trialing", "paid"]);
const PAID_PLANS = new Set(["basic", "pro"]);

function metaString(meta: Record<string, unknown> | undefined, key: string): string | null {
  const v = meta?.[key];
  return typeof v === "string" && v.length > 0 ? v : null;
}

/**
 * 제품 전역에서 플랜/쿼터를 조회할 때 사용 (대시보드, job API, 기능 플래그).
 * 유료 플랜(basic|pro)은 DB `subscription`이 활성 상태일 때만 반환.
 */
export async function getEffectivePlan(userId: string): Promise<EffectivePlan> {
  const db = getDb();
  const [row] = await db
    .select({
      planKey: subscriptions.planKey,
      status: subscriptions.status,
      metadata: subscriptions.metadata,
    })
    .from(subscriptions)
    .where(eq(subscriptions.userId, userId))
    .limit(1);

  if (!row) {
    return {
      planKey: "free",
      subscriptionStatus: null,
      hasSubscriptionRow: false,
      paperclipAgentId: null,
      paperclipProvisionError: null,
    };
  }

  const st = (row.status ?? "").toLowerCase();
  const pk = (row.planKey ?? "").toLowerCase();
  const meta = (row.metadata ?? undefined) as Record<string, unknown> | undefined;
  const paperclipAgentId = metaString(meta, "paperclipAgentId");
  const paperclipProvisionError = metaString(meta, "paperclipProvisionError");

  if (PAID_PLANS.has(pk) && PAID_ACTIVE.has(st)) {
    return {
      planKey: pk as "basic" | "pro",
      subscriptionStatus: row.status,
      hasSubscriptionRow: true,
      paperclipAgentId,
      paperclipProvisionError,
    };
  }

  return {
    planKey: "free",
    subscriptionStatus: row.status,
    hasSubscriptionRow: true,
    paperclipAgentId,
    paperclipProvisionError,
  };
}
