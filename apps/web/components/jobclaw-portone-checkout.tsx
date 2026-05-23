"use client";

import {
  jobClawAmountKrw,
  parseJobClawPlanKey,
  type JobClawPlanKey,
} from "@/lib/billing/jobclaw-pricing";
import PortOne, {
  PaymentCurrency,
  PaymentPayMethod,
} from "@portone/browser-sdk/v2";
import { useRouter } from "next/navigation";
import { useState } from "react";

type Billing = "monthly" | "annual";

export function JobClawPortOneCheckout(props: {
  userId: string;
  planParam: string;
  billingParam: string;
  storeId: string;
  channelKey: string;
  appBaseUrl: string;
}) {
  const router = useRouter();
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  const plan = parseJobClawPlanKey(props.planParam) as JobClawPlanKey;
  const billing: Billing =
    props.billingParam.toLowerCase() === "annual" ? "annual" : "monthly";
  const amount = jobClawAmountKrw(plan, billing);
  const configured = props.storeId.length > 0 && props.channelKey.length > 0;

  async function pay() {
    setError(null);
    if (!configured) {
      setError(
        "PortOne 스토어·채널 키(NEXT_PUBLIC_PORTONE_*)가 설정되지 않았습니다.",
      );
      return;
    }
    setBusy(true);
    try {
      const paymentId = `jobclaw-${props.userId}-${Date.now()}`;
      const redirectUrl = new URL(
        "/jobclaw/onboarding",
        props.appBaseUrl.endsWith("/")
          ? props.appBaseUrl.slice(0, -1)
          : props.appBaseUrl,
      );
      redirectUrl.searchParams.set("from", "checkout");

      const response = await PortOne.requestPayment({
        storeId: props.storeId,
        paymentId,
        orderName: `JobClaw ${plan === "pro" ? "Pro" : "Basic"} (${billing})`,
        totalAmount: amount,
        currency: PaymentCurrency.KRW,
        payMethod: PaymentPayMethod.CARD,
        channelKey: props.channelKey,
        customData: {
          userId: props.userId,
          jobclawPlan: plan,
          billing,
        },
        redirectUrl: redirectUrl.toString(),
      });

      if (response == null) {
        return;
      }
      if (response.code != null) {
        setError(
          typeof response.message === "string"
            ? response.message
            : "결제 요청이 완료되지 않았습니다.",
        );
        return;
      }
      router.refresh();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="space-y-4">
      <div className="rounded-2xl border border-dashed border-white/15 bg-slate-950/60 p-4 text-sm text-slate-400">
        <p>
          <span className="font-medium text-slate-200">결제 금액(원)</span>{" "}
          <span className="text-white">
            {amount.toLocaleString("ko-KR")} KRW
          </span>
        </p>
        <p className="mt-2 text-xs text-slate-500">
          PortOne V2 브라우저 SDK — customData에 userId·jobclawPlan이 포함되어
          웹훅에서 구독·프로비저닝에 사용됩니다.
        </p>
      </div>

      {error ? (
        <p className="rounded-xl border border-rose-500/30 bg-rose-500/10 px-3 py-2 text-sm text-rose-100">
          {error}
        </p>
      ) : null}

      <button
        type="button"
        onClick={() => void pay()}
        disabled={busy}
        className="w-full rounded-xl bg-violet-500 py-3 text-sm font-semibold text-white hover:opacity-95 disabled:opacity-50"
      >
        {busy ? "결제창 여는 중…" : "PortOne으로 결제하기"}
      </button>

      {!configured ? (
        <p className="text-center text-xs text-amber-200/90">
          개발:{" "}
          <code className="font-mono text-[11px]">
            NEXT_PUBLIC_PORTONE_STORE_ID
          </code>{" "}
          ·{" "}
          <code className="font-mono text-[11px]">
            NEXT_PUBLIC_PORTONE_CHANNEL_KEY
          </code>
        </p>
      ) : null}
    </div>
  );
}
