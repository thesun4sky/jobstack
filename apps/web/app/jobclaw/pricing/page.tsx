import Link from "next/link";
import type { Metadata } from "next";
import { JobClawPricingTiers } from "@/components/jobclaw-pricing-tiers";

export const metadata: Metadata = {
  title: "구독 플랜",
  description: "JobClaw Free · Basic · Pro — 에이전트·텔레그램 연동 요금",
};

export default function JobClawPricingPage() {
  return (
    <main className="mx-auto max-w-6xl px-4 py-16 sm:px-6">
      <header className="mx-auto max-w-2xl text-center">
        <p className="text-xs font-semibold uppercase tracking-wide text-violet-300/90">
          Subscription
        </p>
        <h1 className="mt-2 text-3xl font-semibold text-white">
          에이전트 구독형 요금제
        </h1>
        <p className="mt-3 text-slate-400">
          실제 과금은{" "}
          <span className="text-slate-300">PortOne V2</span> 또는{" "}
          <span className="text-slate-300">Stripe</span> 연동 후 활성화됩니다.
          CTA는 기존{" "}
          <code className="font-mono text-xs text-violet-300">/checkout</code>{" "}
          및{" "}
          <code className="font-mono text-xs text-violet-300">
            /api/webhooks/portone
          </code>{" "}
          흐름과 합류합니다.
        </p>
      </header>

      <div className="mt-10 space-y-8">
        <JobClawPricingTiers />
      </div>

      <div className="mt-12 rounded-2xl border border-white/10 bg-slate-900/60 p-6 text-sm text-slate-400">
        <p className="font-medium text-slate-200">구독 완료 후</p>
        <p className="mt-2">
          결제 성공 시{" "}
          <Link
            href="/jobclaw/onboarding"
            className="font-medium text-violet-300 hover:underline"
          >
            텔레그램 봇 연결 가이드
          </Link>
          로 이동해 <code className="font-mono text-xs">/start</code> 및
          JobStack 스킬 연동을 안내합니다.
        </p>
      </div>

      <p className="mt-8 text-center text-xs text-slate-500">
        세금·환불·약관은 출시 전 공지로 확정됩니다.
      </p>
    </main>
  );
}
