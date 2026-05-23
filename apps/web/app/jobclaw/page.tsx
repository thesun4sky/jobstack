import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "JobClaw — 구독형 취업 에이전트",
  description:
    "JobClaw — 구독으로 Claude CLI 에이전트와 텔레그램·JobStack 스킬을 한 번에.",
};

const pillars = [
  {
    title: "구독 → 프로비저닝",
    body: "결제 웹훅 이후 에이전트 생성·텔레그램 토큰 연계까지 한 흐름으로 설계합니다.",
  },
  {
    title: "CLI 옵션을 채팅으로",
    body: "Claude CLI에서 나오는 분기·표는 텔레그램 버튼·서식 또는 이미지로 대응합니다.",
  },
  {
    title: "결과물은 PDF로",
    body: "에이전트 출력·파일은 PDF 변환 후 방에 업로드하는 경로를 기본값으로 둡니다.",
  },
];

const capabilities = [
  {
    title: "Paperclip 연동",
    body: "에이전트 생성·실행 워크스페이스를 Paperclip 런과 맞춥니다.",
  },
  {
    title: "JobStack 스킬 체인",
    body: "웹에서 노출되는 스킬과 동일한 Markdown 스킬을 CLI 측에서 재사용합니다.",
  },
  {
    title: "텔레그램 세션",
    body: "/start로 계정을 묶고, 이후 대화는 동일 맥락으로 이어집니다.",
  },
  {
    title: "구독 상태 반영",
    body: "PortOne·Stripe 웹훅으로 플랜을 확정하고 기능 플래그에 연결합니다.",
  },
  {
    title: "온보딩 가이드",
    body: "봇 토큰·환경 변수·헬스 체크를 단계별로 안내합니다.",
  },
  {
    title: "로드맵 정렬",
    body: "피플팀 자동 프로비저닝 등 후속 과제를 부모 이슈와 동기화합니다.",
  },
];

const steps = [
  {
    step: "01",
    title: "플랜 선택",
    body: "Free로 미리보기하거나 Basic/Pro로 전체 스킬을 켭니다.",
  },
  {
    step: "02",
    title: "결제·웹훅",
    body: "구독이 활성화되면 에이전트 프로비저닝 큐가 열립니다.",
  },
  {
    step: "03",
    title: "텔레그램 연결",
    body: "온보딩 링크에서 봇을 묶고 JobStack 스킬을 그대로 실행합니다.",
  },
];

export default function JobClawLandingPage() {
  return (
    <main>
      <section className="relative overflow-hidden border-b border-white/10">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,rgba(139,92,246,0.22),transparent_45%),radial-gradient(circle_at_80%_0%,rgba(45,212,191,0.12),transparent_42%)]" />
        <div className="relative mx-auto grid max-w-6xl gap-12 px-4 py-20 sm:px-6 lg:grid-cols-2 lg:items-center lg:py-28">
          <div className="space-y-6">
            <p className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs font-medium text-slate-300">
              <span
                className="h-1.5 w-1.5 rounded-full bg-emerald-400 shadow-[0_0_12px_rgba(52,211,153,0.8)]"
                aria-hidden
              />
              JobStack + Claude CLI 에이전트
            </p>
            <h1 className="text-4xl font-semibold tracking-tight text-white sm:text-5xl">
              구독 한 번으로
              <br />
              텔레그램 취업 에이전트
            </h1>
            <p className="max-w-xl text-lg leading-relaxed text-slate-400">
              JobClaw는 Claude 기반 CLI 에이전트를 Paperclip에 프로비저닝하고,
              텔레그램 봇과 연결합니다. 내부 동작은 JobStack의 검증된 스킬
              체인을 그대로 사용합니다.
            </p>
            <div className="flex flex-wrap gap-3">
              <Link
                href="/jobclaw/pricing"
                className="rounded-full bg-violet-500 px-5 py-2.5 text-sm font-semibold text-white shadow-lg shadow-violet-500/25 transition-opacity hover:opacity-95"
              >
                플랜 보기
              </Link>
              <Link
                href="/jobclaw/onboarding"
                className="rounded-full border border-white/15 bg-white/5 px-5 py-2.5 text-sm font-semibold text-slate-100 hover:bg-white/10"
              >
                연결 가이드
              </Link>
            </div>
            <p className="text-sm text-slate-500">
              결제는 PortOne V2 또는 Stripe 연동 후 활성화 · 웹훅으로 구독 상태
              반영
            </p>
          </div>
          <div className="relative mx-auto w-full max-w-md">
            <div className="rounded-3xl border border-white/10 bg-slate-900/80 p-6 shadow-2xl shadow-violet-500/10 backdrop-blur">
              <div className="flex items-center justify-between text-xs text-slate-400">
                <span className="font-mono text-violet-300">jobclaw agent</span>
                <span className="rounded-full bg-emerald-500/15 px-2 py-0.5 font-medium text-emerald-300">
                  linked
                </span>
              </div>
              <div className="mt-4 space-y-3 font-mono text-sm text-slate-200">
                {[
                  "Paperclip → Claude CLI 에이전트 생성",
                  "텔레그램 /start → 세션 바인딩",
                  "표·옵션 → 텔레그램 UI / PDF 내보내기",
                ].map((t) => (
                  <div
                    key={t}
                    className="flex items-start gap-3 rounded-xl border border-white/10 bg-slate-950/60 px-3 py-2.5"
                  >
                    <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-violet-400" />
                    {t}
                  </div>
                ))}
              </div>
              <div className="mt-4 rounded-xl border border-dashed border-violet-500/35 bg-violet-500/5 px-3 py-2 text-xs leading-relaxed text-violet-200/90">
                구독이 확인되면 JobStack 스킬이 에이전트에 탑재되고, 봇에서 같은
                맥락으로 이어집니다.
              </div>
            </div>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl space-y-10 px-4 py-20 sm:px-6">
        <div className="max-w-2xl space-y-3">
          <h2 className="text-2xl font-semibold text-white">왜 JobClaw인가</h2>
          <p className="text-slate-400">
            “에이전트 SaaS”처럼 보이되, 내부는 JobStack 스킬로 통제합니다. 채팅
            한 곳에서 취업 준비가 끊기지 않게 만드는 것이 목표입니다.
          </p>
        </div>
        <div className="grid gap-6 md:grid-cols-3">
          {pillars.map((c) => (
            <div
              key={c.title}
              className="rounded-2xl border border-white/10 bg-slate-900/50 p-6"
            >
              <h3 className="text-lg font-semibold text-white">{c.title}</h3>
              <p className="mt-3 text-sm leading-relaxed text-slate-400">
                {c.body}
              </p>
            </div>
          ))}
        </div>
      </section>

      <section className="border-y border-white/10 bg-slate-900/35 py-20">
        <div className="mx-auto max-w-6xl space-y-10 px-4 sm:px-6">
          <div className="max-w-2xl space-y-3">
            <h2 className="text-2xl font-semibold text-white">주요 기능</h2>
            <p className="text-slate-400">
              랜딩·온보딩·결제·봇이 같은 제품 스토리를 공유하도록 구성했습니다.
            </p>
          </div>
          <div className="grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
            {capabilities.map((item) => (
              <div
                key={item.title}
                className="rounded-2xl border border-white/10 bg-slate-950/40 p-5"
              >
                <h3 className="text-base font-semibold text-white">
                  {item.title}
                </h3>
                <p className="mt-2 text-sm leading-relaxed text-slate-400">
                  {item.body}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl space-y-10 px-4 py-20 sm:px-6">
        <div className="max-w-2xl space-y-3">
          <h2 className="text-2xl font-semibold text-white">시작 흐름</h2>
          <p className="text-slate-400">
            무료 체험에서 유료 전환까지 동일한 온보딩을 유지합니다.
          </p>
        </div>
        <div className="grid gap-6 md:grid-cols-3">
          {steps.map((s) => (
            <div
              key={s.step}
              className="rounded-2xl border border-white/10 bg-slate-900/50 p-6"
            >
              <p className="text-xs font-semibold uppercase tracking-wide text-violet-300">
                {s.step}
              </p>
              <h3 className="mt-2 text-lg font-semibold text-white">
                {s.title}
              </h3>
              <p className="mt-2 text-sm text-slate-400">{s.body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="border-y border-white/10 bg-slate-900/40 py-16">
        <div className="mx-auto flex max-w-6xl flex-col items-start gap-6 px-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
          <div className="space-y-2">
            <h2 className="text-2xl font-semibold text-white">
              Free · Basic · Pro
            </h2>
            <p className="text-slate-400">
              월간·연간 토글과 함께 플랜별 기능을 비교할 수 있습니다.
            </p>
          </div>
          <Link
            href="/jobclaw/pricing"
            className="rounded-full bg-white px-5 py-2.5 text-sm font-semibold text-slate-950 hover:bg-slate-200"
          >
            구독 플랜 열기
          </Link>
        </div>
      </section>

      <section className="relative overflow-hidden py-20">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_120%,rgba(139,92,246,0.25),transparent_55%)]" />
        <div className="relative mx-auto max-w-4xl space-y-6 px-4 text-center sm:px-6">
          <h2 className="text-3xl font-semibold text-white">
            지금 JobClaw 플로를 따라가 보세요
          </h2>
          <p className="text-slate-400">
            디자인 레퍼런스는 MyClaw 랜딩의 정보 구조를 참고했으며, 카피·브랜드는
            JobClaw에 맞게 재작성했습니다.
          </p>
          <div className="flex flex-wrap justify-center gap-3">
            <Link
              href="/jobclaw/pricing"
              className="rounded-full bg-violet-500 px-6 py-3 text-sm font-semibold text-white shadow-lg shadow-violet-500/30 hover:opacity-95"
            >
              요금제 확인
            </Link>
            <Link
              href="/skills"
              className="rounded-full border border-white/15 bg-white/5 px-6 py-3 text-sm font-semibold text-slate-100 hover:bg-white/10"
            >
              JobStack 스킬 둘러보기
            </Link>
          </div>
        </div>
      </section>
    </main>
  );
}
