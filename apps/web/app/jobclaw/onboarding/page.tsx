import { auth } from "@/auth";
import { getEffectivePlan } from "@/lib/billing/plan";
import { getJobClawTelegramUrl } from "@/lib/jobclaw/public";
import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "연결 가이드",
  description:
    "구독 후 텔레그램 봇 /start · JobStack 스킬과 에이전트 연결 안내",
};

export default async function JobClawOnboardingPage({
  searchParams,
}: {
  searchParams: Promise<{ from?: string }>;
}) {
  const { from } = await searchParams;
  const session = await auth();
  const billing = session?.user?.id
    ? await getEffectivePlan(session.user.id)
    : null;
  const telegramUrl = getJobClawTelegramUrl();
  const fromCheckout = from === "checkout";

  return (
    <main className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
      <header className="space-y-2">
        <p className="text-xs font-semibold uppercase tracking-wide text-violet-300/90">
          Onboarding
        </p>
        <h1 className="text-3xl font-semibold text-white">
          텔레그램에 JobClaw 연결하기
        </h1>
        <p className="text-slate-400">
          구독이 활성화되면(웹훅 반영 후) 아래 순서로 봇과 대화를 시작합니다.
          {fromCheckout ? (
            <span className="block pt-2 text-violet-300/90">
              결제 플로우에서 넘어온 경우: 웹훅 처리 전에는 봇이 제한될 수
              있습니다.
            </span>
          ) : null}
        </p>
      </header>

      <ol className="mt-10 space-y-6">
        <li className="rounded-2xl border border-white/10 bg-slate-900/60 p-6">
          <p className="text-sm font-medium text-violet-300">1. 봇 열기</p>
          <p className="mt-2 text-slate-300">
            텔레그램에서 JobClaw 봇을 열고 대화를 시작합니다.
          </p>
          {telegramUrl ? (
            <a
              href={telegramUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="mt-4 inline-flex rounded-xl bg-violet-500 px-4 py-2.5 text-sm font-semibold text-white hover:opacity-95"
            >
              텔레그램에서 열기
            </a>
          ) : (
            <p className="mt-4 rounded-xl border border-dashed border-amber-500/40 bg-amber-500/5 px-3 py-2 text-sm text-amber-200/90">
              <code className="font-mono text-xs">NEXT_PUBLIC_JOBCLAW_TELEGRAM_URL</code>{" "}
              이 설정되면 여기에 딥링크가 표시됩니다.
            </p>
          )}
        </li>
        <li className="rounded-2xl border border-white/10 bg-slate-900/60 p-6">
          <p className="text-sm font-medium text-violet-300">2. /start</p>
          <p className="mt-2 text-slate-300">
            채팅창에 <code className="font-mono text-violet-200">/start</code>를
            보내 계정을 이 구독과 바인딩합니다. (Phase 1 봇:{" "}
            <code className="font-mono text-xs text-slate-500">
              apps/jobclaw-telegram
            </code>
            )
          </p>
        </li>
        <li className="rounded-2xl border border-white/10 bg-slate-900/60 p-6">
          <p className="text-sm font-medium text-violet-300">3. JobStack 스킬</p>
          <p className="mt-2 text-slate-300">
            에이전트는 내부적으로 JobStack 스킬 체인을 사용합니다. 웹에서 스킬
            목록과 흐름은 아래에서 확인할 수 있습니다.
          </p>
          <Link
            href="/skills"
            className="mt-4 inline-flex rounded-xl border border-white/15 bg-white/5 px-4 py-2.5 text-sm font-semibold text-white hover:bg-white/10"
          >
            스킬 체인 보기
          </Link>
        </li>
        <li className="rounded-2xl border border-white/10 bg-slate-900/60 p-6">
          <p className="text-sm font-medium text-violet-300">4. Paperclip 에이전트</p>
          <p className="mt-2 text-slate-300">
            구독이 확정되면 서버가 Paperclip API로 전용 에이전트를 생성하고,
            생성 ID는 구독 메타데이터에 저장됩니다. 대시보드에서 상태를 확인할 수
            있습니다.
          </p>
          {billing?.paperclipAgentId ? (
            <p className="mt-3 rounded-xl border border-emerald-500/25 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-100/90">
              에이전트 ID:{" "}
              <code className="font-mono text-xs">{billing.paperclipAgentId}</code>
            </p>
          ) : billing?.paperclipProvisionError ? (
            <p className="mt-3 rounded-xl border border-amber-500/30 bg-amber-500/10 px-3 py-2 text-xs text-amber-100/90">
              프로비저닝 오류: {billing.paperclipProvisionError}
            </p>
          ) : (
            <p className="mt-3 text-xs text-slate-500">
              아직 생성 기록이 없습니다. 결제 웹훅 처리 후 몇 초 뒤 대시보드를
              새로고침해 보세요.
            </p>
          )}
        </li>
      </ol>

      <div className="mt-12 rounded-2xl border border-white/10 bg-slate-900/40 p-6 text-sm text-slate-400">
        <p className="font-medium text-slate-200">결제 → 온보딩 플로 설계</p>
        <ul className="mt-3 list-inside list-disc space-y-2">
          <li>
            PG 성공 리다이렉트 URL을 이 페이지(
            <code className="font-mono text-xs text-violet-300">
              ?from=checkout
            </code>
            )로 두고, 로그인 세션과 구독 ID를 쿼리/세션에 실어 옵니다.
          </li>
          <li>
            PortOne 웹훅이 <code className="font-mono text-xs">active</code>를
            기록한 뒤에만 봇이 전체 기능을 열 수 있게 서버 플래그를 맞춥니다.
          </li>
          <li>
            Paperclip에서 CLI 에이전트가 준비되면 사용자에게 알림(텔레그램 메시지
            또는 이메일)을 보내는 단계를 추가할 수 있습니다.
          </li>
        </ul>
      </div>
    </main>
  );
}
