/**
 * JobClaw 마케팅/온보딩에서 사용하는 공개 설정.
 * 미설정 시 UI에서 안내 문구만 표시합니다.
 */
export function getJobClawTelegramUrl(): string | null {
  const u = process.env.NEXT_PUBLIC_JOBCLAW_TELEGRAM_URL?.trim();
  if (!u) return null;
  return u;
}
