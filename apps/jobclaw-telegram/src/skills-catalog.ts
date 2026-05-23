/** Mirrors `apps/web/lib/skills.ts` slugs — Telegram 메뉴는 slug 중심으로만 다룹니다. */
export type SkillMenuItem = {
  slug: string;
  title: string;
  tier: number;
};

export const SKILL_MENU: SkillMenuItem[] = [
  { slug: "auto", title: "Auto", tier: 1 },
  { slug: "strategy", title: "Strategy", tier: 1 },
  { slug: "tracker", title: "Tracker", tier: 1 },
  { slug: "company-research", title: "Company research", tier: 2 },
  { slug: "job-search", title: "Job search", tier: 2 },
  { slug: "portfolio", title: "Portfolio", tier: 2 },
  { slug: "ncs", title: "NCS", tier: 2 },
  { slug: "salary", title: "Salary", tier: 2 },
  { slug: "retro", title: "Retro", tier: 2 },
  { slug: "resume", title: "Resume", tier: 3 },
  { slug: "cover-letter", title: "Cover letter", tier: 3 },
  { slug: "mock-interview", title: "Mock interview", tier: 4 },
  { slug: "review", title: "Review", tier: 4 },
];
