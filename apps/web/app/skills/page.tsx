import Link from "next/link";
import { SKILLS } from "@/lib/skills";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "스킬 체인 | JobStack",
  description:
    "Auto부터 Review까지 13개 스킬을 한 워크플로에서 탐색합니다.",
};

export default function SkillsIndexPage() {
  return (
    <div className="space-y-10">
      <header className="space-y-3">
        <p className="text-xs font-semibold uppercase tracking-wide text-[var(--js-faint)]">
          Product map
        </p>
        <h1 className="text-3xl font-semibold tracking-tight text-[var(--js-ink)]">
          13개 스킬, 한 줄에 이어집니다
        </h1>
        <p className="max-w-2xl text-base leading-relaxed text-[var(--js-muted)]">
          전략·트래킹·리서치부터 자소서·모의면접·통합 점검까지. 각 스킬은 CLI
          경로와 동일한 이름으로 연결되어 있어 팀·사용자가 제품 안에서 흐름을
          공유할 수 있습니다.
        </p>
      </header>

      <section className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
        {SKILLS.map((s) => (
          <Link
            key={s.slug}
            href={`/skills/${s.slug}`}
            className="group rounded-2xl border border-[var(--js-border)] bg-[var(--js-surface)] p-5 shadow-sm transition-all hover:-translate-y-0.5 hover:border-[color-mix(in_oklab,var(--js-accent)_40%,var(--js-border))] hover:shadow-md"
          >
            <div className="flex items-center justify-between gap-2">
              <span className="rounded-full bg-[var(--js-elevated)] px-2 py-0.5 text-[11px] font-medium text-[var(--js-muted)]">
                Tier {s.tier}
              </span>
              <span className="font-mono text-[11px] text-[var(--js-faint)]">
                {s.cliPath}
              </span>
            </div>
            <h2 className="mt-3 text-lg font-semibold text-[var(--js-ink)] group-hover:text-[var(--js-accent-strong)]">
              {s.title}
            </h2>
            <p className="mt-2 text-sm leading-relaxed text-[var(--js-muted)]">
              {s.short}
            </p>
          </Link>
        ))}
      </section>
    </div>
  );
}
