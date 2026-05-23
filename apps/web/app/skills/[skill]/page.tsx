import { SkillRunnerMock } from "@/components/skill-runner-mock";
import { getSkill, SKILLS } from "@/lib/skills";
import type { Metadata } from "next";
import Link from "next/link";
import { notFound } from "next/navigation";

type Props = { params: Promise<{ skill: string }> };

export function generateStaticParams() {
  return SKILLS.map((s) => ({ skill: s.slug }));
}

export async function generateMetadata({ params }: Props): Promise<Metadata> {
  const { skill } = await params;
  const def = getSkill(skill);
  if (!def) return { title: "스킬 | JobStack" };
  return {
    title: `${def.title} | JobStack`,
    description: def.pitch,
  };
}

export default async function SkillDetailPage({ params }: Props) {
  const { skill } = await params;
  const def = getSkill(skill);
  if (!def) notFound();

  return (
    <div className="space-y-8">
      <div className="space-y-2">
        <div className="flex flex-wrap items-center gap-2 text-sm text-[var(--js-muted)]">
          <span className="rounded-full bg-[var(--js-elevated)] px-2 py-0.5 text-xs font-medium">
            Tier {def.tier}
          </span>
          <span className="font-mono text-xs">{def.cliPath}</span>
          <Link
            href="/skills"
            className="ml-auto text-[var(--js-accent-strong)] hover:underline"
          >
            ← 전체 목록
          </Link>
        </div>
        <h1 className="text-3xl font-semibold tracking-tight text-[var(--js-ink)]">
          {def.title}
        </h1>
        <p className="max-w-2xl text-base leading-relaxed text-[var(--js-muted)]">
          {def.pitch}
        </p>
      </div>

      <SkillRunnerMock skillTitle={def.title} phases={def.phases} />

      <section className="rounded-2xl border border-[var(--js-border)] bg-[var(--js-surface)] p-6">
        <h2 className="text-sm font-semibold text-[var(--js-ink)]">
          연결된 다음 스킬 (목업)
        </h2>
        <p className="mt-2 text-sm text-[var(--js-muted)]">
          Auto 모드가 최근 로그를 바탕으로 제안하는 순서입니다. 실제 서비스에선
          사용자 상태와 목표에 따라 달라집니다.
        </p>
        <ul className="mt-4 flex flex-wrap gap-2">
          {SKILLS.filter((s) => s.slug !== def.slug)
            .slice(0, 4)
            .map((s) => (
              <li key={s.slug}>
                <Link
                  href={`/skills/${s.slug}`}
                  className="inline-flex rounded-full border border-[var(--js-border)] bg-[var(--js-elevated)] px-3 py-1 text-xs font-medium text-[var(--js-ink)] hover:border-[color-mix(in_oklab,var(--js-accent)_45%,var(--js-border))]"
                >
                  {s.title}
                </Link>
              </li>
            ))}
        </ul>
      </section>
    </div>
  );
}
