export type SubscriptionTier = "free" | "pro" | "unknown";

export type TelegramUserRecord = {
  telegramUserId: number;
  subscriptionTier: SubscriptionTier;
  registeredAt: string;
  /** JobStack skill slug currently selected for this chat session */
  activeSkillSlug?: string;
};
