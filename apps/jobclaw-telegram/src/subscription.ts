import { config } from "./config.js";

export type SubscriptionDecision =
  | { ok: true; tier: "free" | "pro" }
  | { ok: false; reason: string };

/**
 * Phase 1: 웹앱 구독 DB와의 실시간 연동 전까지
 * - `open`: 모든 사용자 허용 (로컬 개발)
 * - `allowlist`: JOBCLAW_ALLOWED_TELEGRAM_IDS 에 포함된 uid 만
 * - `deny`: 모두 거절 (스테이징 잠금)
 */
export function evaluateSubscription(telegramUserId: number): SubscriptionDecision {
  if (config.subscriptionMode === "open") {
    return { ok: true, tier: "pro" };
  }
  if (config.subscriptionMode === "deny") {
    return {
      ok: false,
      reason: "현재 이 봇은 비공개 테스트 중입니다. 담당자에게 문의하세요.",
    };
  }
  if (config.allowedTelegramIds.has(telegramUserId)) {
    return { ok: true, tier: "pro" };
  }
  return {
    ok: false,
    reason:
      "구독(또는 허용 목록)이 확인되지 않았습니다. 웹에서 결제·로그인 후 담당자에게 Telegram user id 등록을 요청하세요.",
  };
}
