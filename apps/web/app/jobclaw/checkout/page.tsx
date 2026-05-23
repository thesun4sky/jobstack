import { JobClawPortOneCheckout } from "@/components/jobclaw-portone-checkout";
import { auth } from "@/auth";
import Link from "next/link";
import type { Metadata } from "next";
import { redirect } from "next/navigation";

export const metadata: Metadata = {
  title: "구독 결제",
  description: "JobClaw Basic / Pro 결제 플로우",
};

const CALLBACK = "/jobclaw/checkout";

const planCopy: Record<string, { label: string; blurb: string }> = {
  basic: {
    label: "JobClaw Basic",
    blurb: "1인 1 에이전트 · 텔레그램 풀 연동",
  },
  pro: {
    label: "JobClaw Pro",
    blurb: "전 스킬 · 우선 큐 · 고급 텔레그램 UX",
  },
};

export default async function JobClawCheckoutPage({
  searchParams,
}: {
  searchParams: Promise<{ plan?: string; billing?: string }>;
}) {
  const session = await auth();
  if (!session?.user?.id) {
    const { plan: p, billing: b } = await searchParams;
    const qs = new URLSearchParams();
    if (p) qs.set("plan", p);
    if (b) qs.set("billing", b);
    const suffix = qs.toString();
    redirect(
      `/login?callbackUrl=${encodeURIComponent(
        `${CALLBACK}${suffix ? `?${suffix}` : ""}`,
      )}`,
    );
  }

  const { plan: planParam, billing: billingParam } = await searchParams;
  const key = (planParam ?? "basic").toLowerCase();
  const plan = planCopy[key] ?? planCopy.basic;
  const billing =
    (billingParam ?? "monthly").toLowerCase() === "annual"
      ? "annual"
      : "monthly";

  const appBase =
    process.env.AUTH_URL?.replace(/\/$/, "") ?? "http://localhost:3000";
  const storeId = process.env.NEXT_PUBLIC_PORTONE_STORE_ID ?? "";
  const channelKey = process.env.NEXT_PUBLIC_PORTONE_CHANNEL_KEY ?? "";

  return (
    <main className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
        <header className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wide text-violet-300/90">
            JobClaw Checkout
          </p>
          <h1 className="text-3xl font-semibold text-white">구독 결제</h1>
          <p className="text-slate-400">
            PortOne(
            <code className="font-mono text-xs text-slate-300">
              /api/webhooks/portone
            </code>
            ) 또는 Stripe 웹훅이 구독 레코드와 연결되면 이 화면에서 실제 결제가
            시작됩니다. 성공 URL은 온보딩으로 보냅니다.
          </p>
        </header>

        <div className="mt-10 space-y-6 rounded-3xl border border-white/10 bg-slate-900/70 p-8 shadow-xl">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p className="text-sm text-slate-400">선택한 플랜</p>
              <p className="text-xl font-semibold text-white">{plan.label}</p>
              <p className="mt-1 text-sm text-slate-500">{plan.blurb}</p>
            </div>
            <div className="text-right">
              <p className="text-sm text-slate-400">청구</p>
              <p className="text-lg font-semibold text-white">
                {billing === "annual" ? "연 정액 (표시용)" : "월 정액 (표시용)"}
              </p>
              <p className="mt-1 text-xs text-slate-500">
                쿼리{" "}
                <code className="font-mono text-[11px] text-violet-300">
                  billing={billing}
                </code>
              </p>
            </div>
          </div>

          <JobClawPortOneCheckout
            userId={session.user.id}
            planParam={planParam ?? "basic"}
            billingParam={billingParam ?? "monthly"}
            storeId={storeId}
            channelKey={channelKey}
            appBaseUrl={appBase}
          />

          <ul className="list-inside list-disc space-y-1 text-xs text-slate-500">
            <li>
              성공 리다이렉트:{" "}
              <code className="font-mono text-[11px] text-violet-300">
                /jobclaw/onboarding?from=checkout
              </code>
            </li>
            <li>
              웹훅{" "}
              <code className="font-mono text-[11px]">/api/webhooks/portone</code>{" "}
              → 구독 반영 → Paperclip 에이전트(환경 변수 설정 시)
            </li>
            <li>
              쿼리{" "}
              <code className="font-mono text-[11px]">
                {`plan=${key}&billing=${billing}`}
              </code>
            </li>
          </ul>

          <p className="text-center text-xs text-slate-500">
            <Link href="/jobclaw/pricing" className="hover:underline">
              플랜으로 돌아가기
            </Link>
          </p>
        </div>

        <p className="mt-8 text-center text-sm text-slate-500">
          JobStack 공통 결제 UI는{" "}
          <Link href="/checkout" className="text-violet-300 hover:underline">
            /checkout
          </Link>
          에서도 확인할 수 있습니다.
        </p>
    </main>
  );
}
