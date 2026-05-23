import type { SubscriptionTier } from "./types.js";

/** 런타임 세션 — Telegram `from.id` 당 하나 (봇 프로세스 메모리). */
export type ChatSession = {
  subscriptionTier: SubscriptionTier;
  activeSkillSlug?: string;
};

const sessions = new Map<number, ChatSession>();

export function getSession(telegramUserId: number): ChatSession | undefined {
  return sessions.get(telegramUserId);
}

export function ensureSession(
  telegramUserId: number,
  tier: SubscriptionTier,
): ChatSession {
  let s = sessions.get(telegramUserId);
  if (!s) {
    s = { subscriptionTier: tier };
    sessions.set(telegramUserId, s);
    return s;
  }
  s.subscriptionTier = tier;
  return s;
}

export function setActiveSkill(
  telegramUserId: number,
  slug: string | undefined,
): void {
  const s = sessions.get(telegramUserId);
  if (!s) return;
  s.activeSkillSlug = slug;
}
