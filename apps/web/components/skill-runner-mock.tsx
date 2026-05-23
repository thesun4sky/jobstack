"use client";

import { useEffect, useState } from "react";

type Phase = { label: string; detail: string };

export function SkillRunnerMock({
  skillTitle,
  phases,
}: {
  skillTitle: string;
  phases: Phase[];
}) {
  const [step, setStep] = useState(0);
  const [pulse, setPulse] = useState(false);

  useEffect(() => {
    const id = window.setInterval(() => {
      setStep((s) => (s + 1) % Math.max(phases.length, 1));
      setPulse(true);
      window.setTimeout(() => setPulse(false), 520);
    }, 4200);
    return () => window.clearInterval(id);
  }, [phases.length]);

  const active = phases[step] ?? phases[0];

  return (
    <div className="rounded-2xl border border-[var(--js-border)] bg-[var(--js-elevated)] p-6 shadow-[0_1px_0_rgba(15,23,42,0.04)]">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-xs font-medium uppercase tracking-wider text-[var(--js-faint)]">
            Auto 실행 미리보기
          </p>
          <h2 className="mt-1 text-lg font-semibold text-[var(--js-ink)]">
            {skillTitle}
          </h2>
        </div>
        <div
          className={`rounded-full px-3 py-1 text-xs font-medium transition-all duration-300 ${
            pulse
              ? "bg-[color-mix(in_oklab,var(--js-accent)_22%,white)] text-[var(--js-accent-strong)] ring-2 ring-[color-mix(in_oklab,var(--js-accent)_35%,transparent)]"
              : "bg-[var(--js-surface)] text-[var(--js-muted)] ring-1 ring-[var(--js-border)]"
          }`}
        >
          튜터 피드백 · 단계 {step + 1}/{phases.length}
        </div>
      </div>

      <div className="mt-6 space-y-4">
        {phases.map((p, i) => {
          const isActive = i === step;
          return (
            <div
              key={p.label}
              className={`rounded-xl border px-4 py-3 transition-all duration-300 ${
                isActive
                  ? "border-[color-mix(in_oklab,var(--js-accent)_45%,var(--js-border))] bg-[color-mix(in_oklab,var(--js-accent)_8%,var(--js-surface))] shadow-[inset_0_1px_0_rgba(255,255,255,0.6)]"
                  : "border-[var(--js-border)] bg-[var(--js-surface)] opacity-75"
              }`}
            >
              <div className="flex items-center justify-between gap-2">
                <p className="text-sm font-medium text-[var(--js-ink)]">
                  {p.label}
                </p>
                {isActive ? (
                  <span className="text-[10px] font-semibold uppercase tracking-wide text-[var(--js-accent-strong)]">
                    진행 중
                  </span>
                ) : null}
              </div>
              <p className="mt-1 text-sm leading-relaxed text-[var(--js-muted)]">
                {p.detail}
              </p>
            </div>
          );
        })}
      </div>

      {active ? (
        <div className="mt-6 rounded-xl border border-dashed border-[color-mix(in_oklab,var(--js-accent)_35%,var(--js-border))] bg-[color-mix(in_oklab,var(--js-surface)_96%,var(--js-accent))] px-4 py-3">
          <p className="text-xs font-medium text-[var(--js-accent-strong)]">
            코치 노트
          </p>
          <p className="mt-1 text-sm leading-relaxed text-[var(--js-ink)]">
            “{active.label}” 단계에서{" "}
            <span className="font-medium">근거 문장</span>을 한 줄 더 보강하면
            다음 단계 점수가 올라갑니다. (목업)
          </p>
        </div>
      ) : null}
    </div>
  );
}
