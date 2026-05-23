import Link from "next/link";

export function JobClawFooter() {
  return (
    <footer className="border-t border-white/10 bg-slate-950">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-12 sm:flex-row sm:items-start sm:justify-between sm:px-6">
        <div>
          <p className="font-semibold text-slate-50">JobClaw</p>
          <p className="mt-2 max-w-sm text-sm leading-relaxed text-slate-400">
            Claude CLI 기반 취업 코칭 에이전트를 구독으로 받고, 텔레그램에서
            JobStack 스킬과 연결합니다.
          </p>
        </div>
        <div className="flex flex-wrap gap-6 text-sm">
          <Link
            href="/"
            className="text-slate-400 hover:text-slate-200"
          >
            JobStack 홈
          </Link>
          <Link
            href="/jobclaw/pricing"
            className="text-slate-400 hover:text-slate-200"
          >
            구독 플랜
          </Link>
          <Link
            href="/pricing"
            className="text-slate-400 hover:text-slate-200"
          >
            JobStack 요금제
          </Link>
        </div>
      </div>
      <div className="border-t border-white/10 py-4 text-center text-xs text-slate-500">
        © {new Date().getFullYear()} JobClaw · JobStack 제품군
      </div>
    </footer>
  );
}
