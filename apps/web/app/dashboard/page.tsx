import { auth, signOut } from "@/auth";
import { getDb, jobs } from "@jobstack/db";
import { desc, eq } from "drizzle-orm";
import Link from "next/link";
import { redirect } from "next/navigation";

export default async function DashboardPage() {
  const session = await auth();
  if (!session?.user?.id) {
    redirect("/login");
  }

  const db = getDb();
  const recentJobs = await db
    .select({
      id: jobs.id,
      skillKey: jobs.skillKey,
      status: jobs.status,
      createdAt: jobs.createdAt,
    })
    .from(jobs)
    .where(eq(jobs.userId, session.user.id))
    .orderBy(desc(jobs.createdAt))
    .limit(10);

  return (
    <div className="min-h-screen bg-[var(--background)]">
      <header className="border-b border-[var(--js-border)] bg-[var(--js-surface)]">
        <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-4 px-4 py-4 sm:px-6">
          <div>
            <p className="text-xs font-semibold uppercase tracking-wide text-[var(--js-faint)]">
              Workspace
            </p>
            <h1 className="text-xl font-semibold text-[var(--js-ink)]">
              대시보드
            </h1>
            <p className="text-sm text-[var(--js-muted)]">
              {session.user.email ?? session.user.name ?? "로그인됨"}
            </p>
          </div>
          <nav className="flex flex-wrap items-center gap-3 text-sm">
            <Link
              href="/skills"
              className="rounded-full border border-[var(--js-border)] px-3 py-1.5 font-medium text-[var(--js-ink)] hover:bg-[var(--js-elevated)]"
            >
              스킬 실행
            </Link>
            <Link
              href="/pricing"
              className="text-[var(--js-muted)] hover:text-[var(--js-ink)]"
            >
              요금제
            </Link>
            <Link href="/" className="text-[var(--js-muted)] hover:text-[var(--js-ink)]">
              랜딩
            </Link>
          </nav>
        </div>
      </header>

      <main className="mx-auto flex max-w-5xl flex-col gap-10 px-4 py-10 sm:px-6">
        <section className="rounded-2xl border border-[var(--js-border)] bg-[var(--js-surface)] p-6 shadow-sm">
          <div className="flex flex-wrap items-center justify-between gap-3">
            <h2 className="text-sm font-semibold text-[var(--js-ink)]">
              최근 작업 (job)
            </h2>
            <Link
              href="/api/v1/jobs"
              className="text-xs font-medium text-[var(--js-accent-strong)] hover:underline"
            >
              목록 JSON
            </Link>
          </div>
          {recentJobs.length === 0 ? (
            <p className="mt-4 rounded-xl border border-dashed border-[var(--js-border)] px-4 py-6 text-center text-sm text-[var(--js-muted)]">
              아직 실행한 작업이 없습니다.{" "}
              <code className="rounded bg-[var(--js-elevated)] px-1.5 py-0.5 font-mono text-xs">
                POST /api/v1/jobs
              </code>
              로 tracker 작업을 만들 수 있습니다. 스킬 UI는{" "}
              <Link href="/skills/tracker" className="font-medium text-[var(--js-accent-strong)] hover:underline">
                /skills/tracker
              </Link>
              에서 미리보기할 수 있습니다.
            </p>
          ) : (
            <ul className="mt-4 divide-y divide-[var(--js-border)] rounded-xl border border-[var(--js-border)]">
              {recentJobs.map((j) => (
                <li
                  key={j.id}
                  className="flex flex-col gap-1 px-4 py-3 text-sm sm:flex-row sm:items-center sm:justify-between"
                >
                  <div>
                    <span className="font-mono text-xs text-[var(--js-faint)]">
                      {j.id.slice(0, 8)}…
                    </span>
                    <span className="ml-2 font-medium text-[var(--js-ink)]">
                      {j.skillKey}
                    </span>
                    <span className="ml-2 rounded-full bg-[var(--js-elevated)] px-2 py-0.5 text-xs text-[var(--js-muted)]">
                      {j.status}
                    </span>
                  </div>
                  <Link
                    href={`/api/v1/jobs/${j.id}`}
                    className="text-xs font-medium text-[var(--js-accent-strong)] hover:underline"
                  >
                    상세(JSON)
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </section>

        <div className="flex flex-wrap items-center gap-4">
          <Link
            href="/api/me"
            className="text-sm font-medium text-[var(--js-accent-strong)] hover:underline"
          >
            보호된 API (/api/me)
          </Link>
          <form
            action={async () => {
              "use server";
              await signOut({ redirectTo: "/" });
            }}
          >
            <button
              type="submit"
              className="rounded-full border border-[var(--js-border)] px-4 py-2 text-sm font-medium text-[var(--js-ink)] hover:bg-[var(--js-elevated)]"
            >
              로그아웃
            </button>
          </form>
        </div>
      </main>
    </div>
  );
}
