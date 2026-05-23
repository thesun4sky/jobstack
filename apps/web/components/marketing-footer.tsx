import Link from "next/link";

export function MarketingFooter() {
  return (
    <footer className="border-t border-[var(--js-border)] bg-[var(--js-surface)]">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-4 py-12 sm:flex-row sm:items-start sm:justify-between sm:px-6">
        <div>
          <p className="font-semibold text-[var(--js-ink)]">JobStack</p>
          <p className="mt-2 max-w-sm text-sm leading-relaxed text-[var(--js-muted)]">
            취업 준비 전 과정이 끊기지 않도록 돕는 AI 코칭 워크스페이스입니다.
          </p>
        </div>
        <div className="flex flex-wrap gap-6 text-sm">
          <Link href="/jobclaw" className="text-[var(--js-muted)] hover:text-[var(--js-ink)]">
            JobClaw
          </Link>
          <Link href="/pricing" className="text-[var(--js-muted)] hover:text-[var(--js-ink)]">
            요금제
          </Link>
          <Link href="/skills" className="text-[var(--js-muted)] hover:text-[var(--js-ink)]">
            스킬
          </Link>
          <Link href="/login" className="text-[var(--js-muted)] hover:text-[var(--js-ink)]">
            로그인
          </Link>
        </div>
      </div>
      <div className="border-t border-[var(--js-border)] py-4 text-center text-xs text-[var(--js-faint)]">
        © {new Date().getFullYear()} JobStack · 목업·베타 UI
      </div>
    </footer>
  );
}
