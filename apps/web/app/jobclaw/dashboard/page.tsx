import { auth, signOut } from "@/auth";
import { getEffectivePlan } from "@/lib/billing/plan";
import { SKILLS } from "@/lib/skills";
import { getDb, jobs } from "@jobstack/db";
import { desc, eq } from "drizzle-orm";
import Link from "next/link";
import { redirect } from "next/navigation";

const CALLBACK = "/jobclaw/dashboard";

export default async function JobClawDashboardPage() {
  const session = await auth();
  if (!session?.user?.id) {
    redirect(`/login?callbackUrl=${encodeURIComponent(CALLBACK)}`);
  }

  const userId = session.user.id;
  const billing = await getEffectivePlan(userId);

  const db = getDb();
  const recentJobs = await db
    .select({
      id: jobs.id,
      skillKey: jobs.skillKey,
      status: jobs.status,
      createdAt: jobs.createdAt,
    })
    .from(jobs)
    .where(eq(jobs.userId, userId))
    .orderBy(desc(jobs.createdAt))
    .limit(8);

  const telegramUrl = process.env.NEXT_PUBLIC_JOBCLAW_TELEGRAM_URL;

  return (
    <main className="mx-auto max-w-6xl space-y-10 px-4 py-10 sm:px-6">
      <div className="flex flex-col gap-4 border-b border-white/10 pb-8 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-xs font-semibold uppercase tracking-wide text-violet-300">
            내 워크스페이스
          </p>
          <h1 className="mt-2 text-3xl font-semibold tracking-tight text-white">
            대시보드
          </h1>
          <p className="mt-2 text-sm text-slate-400">
            {session.user.email ?? session.user.name ?? "로그인된 계정"}
          </p>
        </div>
        <div className="flex flex-wrap gap-3">
          <Link
            href="/jobclaw/onboarding"
            className="rounded-full border border-white/15 bg-white/5 px-4 py-2 text-sm font-medium text-slate-100 hover:bg-white/10"
          >
            연결 가이드
          </Link>
          <form
            action={async () => {
              "use server";
              await signOut({ redirectTo: "/jobclaw" });
            }}
          >
            <button
              type="submit"
              className="rounded-full border border-white/15 px-4 py-2 text-sm font-medium text-slate-200 hover:bg-white/5"
            >
              로그아웃
            </button>
          </form>
        </div>
      </div>

      <section className="grid gap-6 lg:grid-cols-2">
        <div className="rounded-2xl border border-white/10 bg-slate-900/50 p-6">
          <h2 className="text-lg font-semibold text-white">에이전트 · 구독</h2>
          <p className="mt-1 text-sm text-slate-400">
            PortOne 결제 웹훅이 구독을 확정하면 Paperclip 에이전트가 생성됩니다
            (서버 환경 변수 설정 시).
          </p>
          <dl className="mt-4 space-y-3 text-sm">
            <div className="flex justify-between gap-4 border-t border-white/10 pt-3">
              <dt className="text-slate-500">플랜</dt>
              <dd className="font-medium text-emerald-300">
                {billing.planKey === "pro"
                  ? "Pro"
                  : billing.planKey === "basic"
                    ? "Basic"
                    : "Free"}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-slate-500">구독 상태</dt>
              <dd className="text-slate-200">
                {billing.subscriptionStatus ?? "—"}
              </dd>
            </div>
            <div className="flex justify-between gap-4">
              <dt className="text-slate-500">Paperclip 에이전트</dt>
              <dd className="text-slate-200">
                {billing.paperclipAgentId
                  ? `연결됨 (${billing.paperclipAgentId.slice(0, 8)}…)`
                  : billing.paperclipProvisionError
                    ? "오류 (메타데이터 참고)"
                    : "미생성 또는 미설정"}
              </dd>
            </div>
          </dl>
          {telegramUrl ? (
            <a
              href={telegramUrl}
              target="_blank"
              rel="noreferrer"
              className="mt-4 inline-flex text-sm font-medium text-violet-300 hover:underline"
            >
              텔레그램 봇 열기 →
            </a>
          ) : (
            <p className="mt-4 text-xs text-slate-500">
              <code className="rounded bg-slate-950/80 px-1.5 py-0.5 font-mono">
                NEXT_PUBLIC_JOBCLAW_TELEGRAM_URL
              </code>
              을 설정하면 봇 링크가 표시됩니다.
            </p>
          )}
        </div>

        <div className="rounded-2xl border border-dashed border-violet-500/30 bg-violet-500/5 p-6">
          <h2 className="text-lg font-semibold text-white">사용 내역 (작업)</h2>
          <p className="mt-1 text-sm text-slate-400">
            스킬 실행·트래커 등은 job 단위로 기록됩니다. 데이터가 없으면 빈
            상태를 보여줍니다.
          </p>
          {recentJobs.length === 0 ? (
            <p className="mt-6 rounded-xl border border-white/10 bg-slate-950/40 px-4 py-8 text-center text-sm text-slate-500">
              아직 기록된 작업이 없습니다.{" "}
              <Link
                href="/skills"
                className="font-medium text-violet-300 hover:underline"
              >
                스킬 실행
              </Link>
              으로 이동하거나{" "}
              <code className="font-mono text-xs text-slate-400">
                POST /api/v1/jobs
              </code>
              로 생성할 수 있습니다.
            </p>
          ) : (
            <ul className="mt-4 divide-y divide-white/10 rounded-xl border border-white/10">
              {recentJobs.map((j) => (
                <li
                  key={j.id}
                  className="flex flex-col gap-1 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between"
                >
                  <div>
                    <span className="font-mono text-xs text-slate-500">
                      {j.id.slice(0, 8)}…
                    </span>
                    <span className="ml-2 font-medium text-slate-100">
                      {j.skillKey}
                    </span>
                    <span className="ml-2 rounded-full bg-white/10 px-2 py-0.5 text-xs text-slate-300">
                      {j.status}
                    </span>
                  </div>
                  <Link
                    href={`/api/v1/jobs/${j.id}`}
                    className="text-xs font-medium text-violet-300 hover:underline"
                  >
                    JSON
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </div>
      </section>

      <section className="rounded-2xl border border-white/10 bg-slate-900/40 p-6">
        <div className="flex flex-wrap items-end justify-between gap-3">
          <div>
            <h2 className="text-lg font-semibold text-white">JobStack 스킬</h2>
            <p className="mt-1 text-sm text-slate-400">
              CLI와 동일한 13개 스킬. 웹에서는 미리보기·실행 UI로 연결됩니다.
            </p>
          </div>
          <Link
            href="/skills"
            className="text-sm font-medium text-violet-300 hover:underline"
          >
            전체 스킬 →
          </Link>
        </div>
        <div className="mt-6 grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
          {SKILLS.map((s) => (
            <Link
              key={s.slug}
              href={`/skills/${s.slug}`}
              className="rounded-xl border border-white/10 bg-slate-950/50 p-4 transition-colors hover:border-violet-500/40 hover:bg-slate-950/80"
            >
              <div className="flex items-center justify-between gap-2">
                <span className="font-medium text-slate-100">{s.title}</span>
                <span className="rounded-full bg-white/10 px-2 py-0.5 text-[10px] font-medium text-slate-400">
                  T{s.tier}
                </span>
              </div>
              <p className="mt-2 line-clamp-2 text-xs leading-relaxed text-slate-500">
                {s.short}
              </p>
            </Link>
          ))}
        </div>
      </section>
    </main>
  );
}
