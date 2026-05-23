import { auth } from "@/auth";
import Link from "next/link";

const links = [
  { href: "/jobclaw/pricing", label: "구독 플랜" },
  { href: "/jobclaw/onboarding", label: "연결 가이드" },
  { href: "/skills", label: "JobStack 스킬" },
];

const dashboardPath = "/jobclaw/dashboard";

export async function JobClawHeader() {
  const session = await auth();
  const loginHref = `/login?callbackUrl=${encodeURIComponent(dashboardPath)}`;
  const signupHref = `/signup?callbackUrl=${encodeURIComponent(dashboardPath)}`;

  return (
    <header className="sticky top-0 z-40 border-b border-white/10 bg-slate-950/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-4 sm:px-6">
        <div className="flex items-center gap-3">
          <Link
            href="/jobclaw"
            className="font-semibold tracking-tight text-slate-50"
          >
            JobClaw
          </Link>
          <span className="hidden rounded-full border border-violet-500/30 bg-violet-500/10 px-2 py-0.5 text-[10px] font-medium uppercase tracking-wide text-violet-200 sm:inline">
            Agent
          </span>
        </div>
        <nav className="flex items-center gap-4 text-sm sm:gap-6">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="text-slate-400 transition-colors hover:text-white"
            >
              {l.label}
            </Link>
          ))}
          {session?.user ? (
            <Link
              href={dashboardPath}
              className="hidden rounded-full border border-emerald-500/40 bg-emerald-500/10 px-3 py-1.5 text-emerald-200 transition-colors hover:bg-emerald-500/20 sm:inline-block"
            >
              대시보드
            </Link>
          ) : (
            <>
              <Link
                href={loginHref}
                className="hidden rounded-full border border-white/15 px-3 py-1.5 text-slate-200 transition-colors hover:bg-white/5 sm:inline-block"
              >
                로그인
              </Link>
              <Link
                href={signupHref}
                className="hidden rounded-full border border-white/15 px-3 py-1.5 text-slate-200 transition-colors hover:bg-white/5 sm:inline-block"
              >
                시작하기
              </Link>
            </>
          )}
          <Link
            href="/jobclaw/pricing"
            className="rounded-full bg-violet-500 px-3 py-1.5 text-sm font-medium text-white shadow-sm transition-opacity hover:opacity-95"
          >
            구독하기
          </Link>
        </nav>
      </div>
    </header>
  );
}
