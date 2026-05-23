import Link from "next/link";

const links = [
  { href: "/jobclaw", label: "JobClaw" },
  { href: "/pricing", label: "요금제" },
  { href: "/skills", label: "스킬 체인" },
];

export function MarketingHeader() {
  return (
    <header className="sticky top-0 z-40 border-b border-[var(--js-border)] bg-[color-mix(in_oklab,var(--js-surface)_88%,transparent)] backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link
          href="/"
          className="font-semibold tracking-tight text-[var(--js-ink)]"
        >
          JobStack
        </Link>
        <nav className="flex items-center gap-6 text-sm">
          {links.map((l) => (
            <Link
              key={l.href}
              href={l.href}
              className="text-[var(--js-muted)] transition-colors hover:text-[var(--js-ink)]"
            >
              {l.label}
            </Link>
          ))}
          <Link
            href="/login"
            className="rounded-full border border-[var(--js-border)] px-3 py-1.5 text-[var(--js-ink)] transition-colors hover:bg-[var(--js-elevated)]"
          >
            로그인
          </Link>
          <Link
            href="/signup"
            className="rounded-full bg-[var(--js-accent)] px-3 py-1.5 font-medium text-white shadow-sm transition-opacity hover:opacity-95"
          >
            시작하기
          </Link>
        </nav>
      </div>
    </header>
  );
}
