/**
 * JobClaw 플랜 금액(KRW) — 운영 시 PortOne 콘솔 상품·실결제 금액과 반드시 일치시킵니다.
 */
export type JobClawPlanKey = "basic" | "pro";

export function jobClawAmountKrw(
  plan: JobClawPlanKey,
  billing: "monthly" | "annual",
): number {
  const monthly: Record<JobClawPlanKey, number> = {
    basic: 9_900,
    pro: 24_900,
  };
  const annual: Record<JobClawPlanKey, number> = {
    basic: 99_000,
    pro: 249_000,
  };
  return billing === "annual" ? annual[plan] : monthly[plan];
}

export function parseJobClawPlanKey(raw: string | undefined): JobClawPlanKey {
  const k = (raw ?? "basic").toLowerCase();
  return k === "pro" ? "pro" : "basic";
}
