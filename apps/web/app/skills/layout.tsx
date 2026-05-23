import Link from "next/link";
import { SKILLS, type SkillTier } from "@/lib/skills";
import type { ReactNode } from "react";

const tierLabel: Record<SkillTier, string> = {
  1: "Tier 1 · 오케스트레이션",
  2: "Tier 2 · 시장·직무 정렬",
  3: "Tier 3 · 서류·자산",
  4: "Tier 4 · 자소서·면접·통합",
};

function groupByTier() {
  const m = new Map<SkillTier, typeof SKILLS>();
  for (const s of SKILLS) {
    const list = m.get(s.tier) ?? [];
    list.push(s);
    m.set(s.tier, list);
  }
  return m;
}

export default function SkillsLayout({ children }: { children: ReactNode }) {
  const grouped = groupByTier();

  return (
    <div className="min-h-screen bg-[var(--background)]">
      <div className="mx-auto flex max-w-7xl flex-col gap-8 px-4 py-8 lg:flex-row lg:px-6">
        <aside className="lg:w-72 lg:shrink-0">
          <div className="sticky top-6 space-y-6 rounded-2xl border border-[var(--js-border)] bg-[var(--js-surface)] p-4 shadow-sm">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-[var(--js-faint)]">
                스킬 체인
              </p>
              <p className="mt-1 text-sm text-[var(--js-muted)]">
                CLI의 13개 스킬을 제품 내비게이션에 그대로 반영했습니다.
              </p>
            </div>
            <nav className="space-y-5">
              {([1, 2, 3, 4] as SkillTier[]).map((tier) => {
                const items = grouped.get(tier) ?? [];
                return (
                  <div key={tier}>
                    <p className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--js-faint)]">
                      {tierLabel[tier]}
                    </p>
                    <ul className="space-y-1">
                      {items.map((s) => (
                        <li key={s.slug}>
                          <Link
                            href={`/skills/${s.slug}`}
                            className="flex flex-col rounded-lg px-2 py-2 text-sm transition-colors hover:bg-[var(--js-elevated)]"
                          >
                            <span className="font-medium text-[var(--js-ink)]">
                              {s.title}
                            </span>
                            <span className="text-xs text-[var(--js-muted)]">
                              {s.cliPath}
                            </span>
                          </Link>
                        </li>
                      ))}
                    </ul>
                  </div>
                );
              })}
            </nav>
            <div className="border-t border-[var(--js-border)] pt-4 text-xs text-[var(--js-muted)]">
              <Link href="/dashboard" className="font-medium text-[var(--js-accent-strong)] hover:underline">
                대시보드
              </Link>
              {" · "}
              <Link href="/" className="hover:underline">
                랜딩
              </Link>
            </div>
          </div>
        </aside>
        <div className="min-w-0 flex-1">{children}</div>
      </div>
    </div>
  );
}
