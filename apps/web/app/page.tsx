import { MarketingFooter } from "@/components/marketing-footer";
import { MarketingHeader } from "@/components/marketing-header";
import Link from "next/link";

export default function Home() {
  return (
    <div className="min-h-screen bg-[var(--background)]">
      <MarketingHeader />
      <main>
        <section className="relative overflow-hidden border-b border-[var(--js-border)]">
          <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_20%_20%,color-mix(in_oklab,var(--js-accent)_18%,transparent),transparent_45%),radial-gradient(circle_at_80%_0%,color-mix(in_oklab,#6366f1_12%,transparent),transparent_40%)]" />
          <div className="relative mx-auto grid max-w-6xl gap-12 px-4 py-20 sm:px-6 lg:grid-cols-2 lg:items-center lg:py-28">
            <div className="space-y-6">
              <p className="inline-flex rounded-full border border-[var(--js-border)] bg-[var(--js-surface)] px-3 py-1 text-xs font-medium text-[var(--js-muted)] shadow-sm">
                한국 취업 준비생을 위한 AI 코칭 워크스페이스
              </p>
              <h1 className="text-4xl font-semibold tracking-tight text-[var(--js-ink)] sm:text-5xl">
                취업 준비,
                <br />
                여기서 끊기지 않게.
              </h1>
              <p className="max-w-xl text-lg leading-relaxed text-[var(--js-muted)]">
                검증된 방법론과 13개 AI 스킬로 기업 리서치부터 자소서·면접까지{" "}
                <span className="text-[var(--js-ink)]">한 워크플로</span>에서.
                브라우저만 있으면 됩니다.
              </p>
              <div className="flex flex-wrap gap-3">
                <Link
                  href="/signup"
                  className="rounded-full bg-[var(--js-accent)] px-5 py-2.5 text-sm font-semibold text-white shadow-md transition-opacity hover:opacity-95"
                >
                  무료로 시작하기
                </Link>
                <Link
                  href="/skills"
                  className="rounded-full border border-[var(--js-border)] bg-[var(--js-surface)] px-5 py-2.5 text-sm font-semibold text-[var(--js-ink)] shadow-sm hover:bg-[var(--js-elevated)]"
                >
                  스킬 체인 보기
                </Link>
              </div>
              <p className="text-sm text-[var(--js-faint)]">
                신용카드 없이 Free로 체험 · Pro로 전 과정 해제
              </p>
            </div>
            <div className="js-hero-art relative mx-auto w-full max-w-md">
              <div className="rounded-3xl border border-[var(--js-border)] bg-[var(--js-surface)] p-6 shadow-xl">
                <div className="flex items-center justify-between text-xs text-[var(--js-muted)]">
                  <span>주간 플랜</span>
                  <span className="rounded-full bg-[var(--js-elevated)] px-2 py-0.5 font-medium text-[var(--js-ink)]">
                    Auto
                  </span>
                </div>
                <div className="mt-4 space-y-3">
                  {[
                    "기업 리서치 요약 초안",
                    "이력서 성과 문장 2개 보강",
                    "모의면접 질문 5개 생성",
                  ].map((t) => (
                    <div
                      key={t}
                      className="flex items-center gap-3 rounded-xl border border-[var(--js-border)] bg-[var(--js-elevated)] px-3 py-2 text-sm text-[var(--js-ink)]"
                    >
                      <span className="h-2 w-2 rounded-full bg-[var(--js-accent)]" />
                      {t}
                    </div>
                  ))}
                </div>
                <div className="mt-4 rounded-xl border border-dashed border-[color-mix(in_oklab,var(--js-accent)_35%,var(--js-border))] bg-[color-mix(in_oklab,var(--js-surface)_90%,var(--js-accent))] px-3 py-2 text-xs text-[var(--js-accent-strong)]">
                  튜터 피드백: 지표가 있는 문장을 하나 더하면 자소서 설득력이
                  올라갑니다.
                </div>
              </div>
            </div>
          </div>
        </section>

        <section className="mx-auto max-w-6xl space-y-10 px-4 py-20 sm:px-6">
          <div className="max-w-2xl space-y-3">
            <h2 className="text-2xl font-semibold text-[var(--js-ink)]">
              왜 끊기면 안 되나요
            </h2>
            <p className="text-[var(--js-muted)]">
              자소서만 GPT에 던지면 이전 단계와 말이 어긋납니다. 사이트마다 흩어진
              기능 대신, 내 상황에 맞는 순서가 필요합니다.
            </p>
          </div>
          <div className="grid gap-6 md:grid-cols-3">
            {[
              {
                title: "검증된 방법론",
                body: "4년간 다듬어 온 프로세스로 빈 말이 아니라 합격 논리에 맞춥니다.",
              },
              {
                title: "13개 통합 스킬",
                body: "이력서·자소서·리서치·면접·회고까지 끊기지 않게 이어집니다.",
              },
              {
                title: "웹에서 바로",
                body: "설치 없이 시작. 어디서나 같은 컨텍스트로 이어집니다.",
              },
            ].map((c) => (
              <div
                key={c.title}
                className="rounded-2xl border border-[var(--js-border)] bg-[var(--js-surface)] p-6 shadow-sm"
              >
                <h3 className="text-lg font-semibold text-[var(--js-ink)]">
                  {c.title}
                </h3>
                <p className="mt-3 text-sm leading-relaxed text-[var(--js-muted)]">
                  {c.body}
                </p>
              </div>
            ))}
          </div>
        </section>

        <section className="border-y border-[var(--js-border)] bg-[var(--js-surface)] py-20">
          <div className="mx-auto flex max-w-6xl flex-col items-start gap-8 px-4 sm:px-6 lg:flex-row lg:items-center lg:justify-between">
            <div className="space-y-2">
              <h2 className="text-2xl font-semibold text-[var(--js-ink)]">
                요금제를 확인해 보세요
              </h2>
              <p className="text-[var(--js-muted)]">
                Free로 핵심을 체험하고, Pro에서 전 스킬과 심화 코칭을 엽니다.
              </p>
            </div>
            <Link
              href="/pricing"
              className="rounded-full bg-[var(--js-ink)] px-5 py-2.5 text-sm font-semibold text-[var(--js-surface)] hover:opacity-90"
            >
              요금제 보기
            </Link>
          </div>
        </section>
      </main>
      <MarketingFooter />
    </div>
  );
}
