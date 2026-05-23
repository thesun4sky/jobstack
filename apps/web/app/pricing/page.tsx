import { MarketingFooter } from "@/components/marketing-footer";
import { MarketingHeader } from "@/components/marketing-header";
import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "요금제 | JobStack",
  description: "Free와 Pro 플랜 요약 — JobStack 웹 서비스",
};

const plans = [
  {
    name: "Free",
    price: "₩0",
    desc: "핵심 기능 체험 · 월 사용량 제한",
    features: [
      "기본 스킬 실행 (제한적)",
      "주간 플랜 미리보기",
      "대시보드 작업 이력",
    ],
    cta: { href: "/signup", label: "무료로 시작" },
    highlight: false,
  },
  {
    name: "Pro",
    price: "월 정액",
    desc: "전 스킬·심화 코칭 · 우선 처리",
    features: [
      "13개 스킬 전부",
      "Auto 오케스트레이션 고급",
      "튜터 피드백 심화·우선 큐",
    ],
    cta: { href: "/checkout", label: "결제 플로우로 이동" },
    highlight: true,
  },
];

export default function PricingPage() {
  return (
    <div className="min-h-screen bg-[var(--background)]">
      <MarketingHeader />
      <main className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
        <header className="mx-auto max-w-2xl text-center">
          <p className="text-xs font-semibold uppercase tracking-wide text-[var(--js-faint)]">
            Pricing
          </p>
          <h1 className="mt-2 text-3xl font-semibold text-[var(--js-ink)]">
            팀과 사용자가 같은 언어로 이야기할 수 있게
          </h1>
          <p className="mt-3 text-[var(--js-muted)]">
            실제 과금은 PortOne/Stripe 연동 후 활성화됩니다. 아래는 제품 목업의
            정보 구조입니다.
          </p>
        </header>

        <div className="mt-12 grid gap-6 lg:grid-cols-2">
          {plans.map((p) => (
            <div
              key={p.name}
              className={`rounded-3xl border p-8 shadow-sm ${
                p.highlight
                  ? "border-[color-mix(in_oklab,var(--js-accent)_45%,var(--js-border))] bg-[color-mix(in_oklab,var(--js-surface)_92%,var(--js-accent))]"
                  : "border-[var(--js-border)] bg-[var(--js-surface)]"
              }`}
            >
              {p.highlight ? (
                <span className="inline-flex rounded-full bg-[var(--js-accent)] px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide text-white">
                  추천
                </span>
              ) : (
                <span className="text-xs font-medium text-[var(--js-faint)]">
                  Starter
                </span>
              )}
              <h2 className="mt-3 text-2xl font-semibold text-[var(--js-ink)]">
                {p.name}
              </h2>
              <p className="mt-1 text-3xl font-semibold text-[var(--js-ink)]">
                {p.price}
              </p>
              <p className="mt-2 text-sm text-[var(--js-muted)]">{p.desc}</p>
              <ul className="mt-6 space-y-3 text-sm text-[var(--js-ink)]">
                {p.features.map((f) => (
                  <li key={f} className="flex gap-2">
                    <span className="mt-1 h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--js-accent)]" />
                    {f}
                  </li>
                ))}
              </ul>
              <Link
                href={p.cta.href}
                className={`mt-8 inline-flex w-full items-center justify-center rounded-xl py-3 text-sm font-semibold ${
                  p.highlight
                    ? "bg-[var(--js-accent)] text-white hover:opacity-95"
                    : "border border-[var(--js-border)] bg-[var(--js-elevated)] text-[var(--js-ink)] hover:bg-[var(--js-surface)]"
                }`}
              >
                {p.cta.label}
              </Link>
            </div>
          ))}
        </div>

        <p className="mt-10 text-center text-xs text-[var(--js-faint)]">
          세금·결제 수단·환불 정책은 출시 전 공지로 확정됩니다.
        </p>
      </main>
      <MarketingFooter />
    </div>
  );
}
