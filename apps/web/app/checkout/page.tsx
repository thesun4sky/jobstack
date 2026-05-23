import { MarketingFooter } from "@/components/marketing-footer";
import { MarketingHeader } from "@/components/marketing-header";
import Link from "next/link";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "구독 결제 | JobStack",
  description: "Pro 플랜 결제 플로우 목업",
};

export default function CheckoutPage() {
  return (
    <div className="min-h-screen bg-[var(--background)]">
      <MarketingHeader />
      <main className="mx-auto max-w-3xl px-4 py-16 sm:px-6">
        <header className="space-y-2">
          <p className="text-xs font-semibold uppercase tracking-wide text-[var(--js-faint)]">
            Checkout
          </p>
          <h1 className="text-3xl font-semibold text-[var(--js-ink)]">
            Pro로 업그레이드
          </h1>
          <p className="text-[var(--js-muted)]">
            PortOne 웹훅(
            <code className="font-mono text-xs">/api/webhooks/portone</code>)과
            DB 구독 레코드가 연결되면 이 화면에서 실제 결제가 시작됩니다.
          </p>
        </header>

        <div className="mt-10 space-y-6 rounded-3xl border border-[var(--js-border)] bg-[var(--js-surface)] p-8 shadow-sm">
          <div className="flex flex-wrap items-end justify-between gap-4">
            <div>
              <p className="text-sm text-[var(--js-muted)]">선택한 플랜</p>
              <p className="text-xl font-semibold text-[var(--js-ink)]">
                JobStack Pro
              </p>
            </div>
            <div className="text-right">
              <p className="text-sm text-[var(--js-muted)]">청구</p>
              <p className="text-lg font-semibold text-[var(--js-ink)]">
                월 정액 (표시용)
              </p>
            </div>
          </div>

          <div className="space-y-3 rounded-2xl border border-dashed border-[var(--js-border)] bg-[var(--js-elevated)] p-4 text-sm text-[var(--js-muted)]">
            <p>
              <span className="font-medium text-[var(--js-ink)]">
                결제 수단 단계 (목업)
              </span>
              — 카드/간편결제 위젯이 이 영역에 임베드됩니다.
            </p>
            <ul className="list-inside list-disc space-y-1">
              <li>고객 식별자: 로그인 세션의 user id</li>
              <li>성공 시: PortOne 웹훅 → 구독 상태 active</li>
              <li>실패 시: 동일 페이지에 사유 메시지</li>
            </ul>
          </div>

          <button
            type="button"
            className="w-full rounded-xl bg-[var(--js-accent)] py-3 text-sm font-semibold text-white opacity-80"
            disabled
          >
            결제 시작 (백엔드 연동 후 활성화)
          </button>

          <p className="text-center text-xs text-[var(--js-faint)]">
            로그인이 필요합니다.{" "}
            <Link href="/login" className="font-medium text-[var(--js-accent-strong)] hover:underline">
              로그인
            </Link>
            {" · "}
            <Link href="/pricing" className="hover:underline">
              요금제로 돌아가기
            </Link>
          </p>
        </div>
      </main>
      <MarketingFooter />
    </div>
  );
}
