"use client";

import Link from "next/link";
import { useState } from "react";

type Billing = "monthly" | "annual";

type PlanDef = {
  key: "free" | "basic" | "pro";
  name: string;
  monthlyHint: string;
  annualHint: string;
  desc: string;
  badge: string;
  features: string[];
  cta: { label: string; href: (b: Billing) => string; primary: boolean };
};

const plans: PlanDef[] = [
  {
    key: "free",
    name: "Free",
    monthlyHint: "₩0",
    annualHint: "₩0",
    desc: "체험 · 제한된 에이전트 호출",
    badge: "시작",
    features: [
      "텔레그램 봇 연결 안내 (실제 프로비저닝은 Basic+)",
      "JobStack 웹 스킬 미리보기",
      "월간 메시지·토큰 쿼터 (정책 확정 전)",
    ],
    cta: {
      label: "웹에서 무료 시작",
      href: () => "/signup",
      primary: false,
    },
  },
  {
    key: "basic",
    name: "Basic",
    monthlyHint: "월 정액",
    annualHint: "연 정액 (월 환산 표시)",
    desc: "1인 1에이전트 · 텔레그램 풀 플로",
    badge: "추천",
    features: [
      "구독 확인 후 Claude CLI 에이전트 1개",
      "텔레그램 /start 바인딩",
      "JobStack 스킬 체인 기본 세트",
    ],
    cta: {
      label: "Basic로 계속",
      href: (b) =>
        `/jobclaw/checkout?plan=basic&billing=${b === "annual" ? "annual" : "monthly"}`,
      primary: true,
    },
  },
  {
    key: "pro",
    name: "Pro",
    monthlyHint: "월 정액",
    annualHint: "연 정액 (월 환산 표시)",
    desc: "심화 스킬·우선 큐·PDF 내보내기 우선",
    badge: "Pro",
    features: [
      "13개 스킬 전부 + 우선 처리",
      "표·옵션 UX 고급 (이미지 폴백 포함)",
      "피플팀 자동 프로비저닝 로드맵 정렬",
    ],
    cta: {
      label: "Pro로 계속",
      href: (b) =>
        `/jobclaw/checkout?plan=pro&billing=${b === "annual" ? "annual" : "monthly"}`,
      primary: true,
    },
  },
];

export function JobClawPricingTiers() {
  const [billing, setBilling] = useState<Billing>("monthly");

  return (
    <>
      <div className="flex flex-col items-center gap-4 sm:flex-row sm:justify-center">
        <p className="text-sm text-slate-400">청구 주기</p>
        <div
          className="inline-flex rounded-full border border-white/15 bg-slate-900/80 p-1"
          role="group"
          aria-label="청구 주기 선택"
        >
          <button
            type="button"
            onClick={() => setBilling("monthly")}
            className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
              billing === "monthly"
                ? "bg-white text-slate-950"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            월간
          </button>
          <button
            type="button"
            onClick={() => setBilling("annual")}
            className={`rounded-full px-4 py-1.5 text-sm font-medium transition-colors ${
              billing === "annual"
                ? "bg-white text-slate-950"
                : "text-slate-400 hover:text-slate-200"
            }`}
          >
            연간
            <span className="ml-1.5 text-xs font-semibold text-emerald-400">
              할인 예정
            </span>
          </button>
        </div>
      </div>
      <p className="mx-auto max-w-xl text-center text-xs text-slate-500">
        연간은 월 환산 대비 할인율을 적용하는 형태로 공개 예정입니다. 실제
        과금은 PortOne V2 또는 Stripe 연동 후 활성화됩니다.
      </p>

      <div className="mt-12 grid gap-6 lg:grid-cols-3">
        {plans.map((p) => {
          const priceLine =
            p.key === "free"
              ? "₩0"
              : billing === "monthly"
                ? p.monthlyHint
                : p.annualHint;
          const primary = p.cta.primary;
          return (
            <div
              key={p.key}
              className={`rounded-3xl border p-8 shadow-lg ${
                primary
                  ? "border-violet-500/40 bg-gradient-to-b from-violet-500/10 to-slate-900/80"
                  : "border-white/10 bg-slate-900/50"
              }`}
            >
              <span
                className={`inline-flex rounded-full px-2 py-0.5 text-[11px] font-semibold uppercase tracking-wide ${
                  primary
                    ? "bg-violet-500/20 text-violet-200"
                    : "text-slate-500"
                }`}
              >
                {p.badge}
              </span>
              <h2 className="mt-3 text-2xl font-semibold text-white">
                {p.name}
              </h2>
              <p className="mt-1 text-3xl font-semibold text-white">
                {priceLine}
              </p>
              {p.key !== "free" && (
                <p className="mt-1 text-xs text-slate-500">
                  {billing === "monthly" ? "매월 청구" : "매년 청구 · 월 환산가 병기"}
                </p>
              )}
              <p className="mt-2 text-sm text-slate-400">{p.desc}</p>
              <ul className="mt-6 space-y-3 text-sm text-slate-200">
                {p.features.map((f) => (
                  <li key={f} className="flex gap-2">
                    <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-violet-400" />
                    {f}
                  </li>
                ))}
              </ul>
              <Link
                href={p.cta.href(billing)}
                className={`mt-8 inline-flex w-full items-center justify-center rounded-xl py-3 text-sm font-semibold ${
                  primary
                    ? "bg-violet-500 text-white hover:opacity-95"
                    : "border border-white/15 bg-white/5 text-slate-100 hover:bg-white/10"
                }`}
              >
                {p.cta.label}
              </Link>
            </div>
          );
        })}
      </div>
    </>
  );
}
