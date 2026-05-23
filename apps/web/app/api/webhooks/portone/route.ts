import {
  extractJobClawPlanFromPortOnePayment,
  extractUserIdFromPortOnePayment,
  fetchPortOneV2Payment,
  getPortOneV2AccessToken,
  normalizePortOnePaymentStatus,
  verifyPortOneSubscriptionLinkSignature,
  type PortOneSubscriptionLinkBody,
  type PortOneV2WebhookBody,
} from "@/lib/billing/portone";
import {
  provisionPaperclipAgentForJobClawUser,
  recordPaperclipProvisionFailure,
} from "@/lib/billing/paperclip-provision";
import { billingWebhookEvents, getDb, subscriptions } from "@jobstack/db";
import { eq } from "drizzle-orm";
import { NextResponse } from "next/server";

export const runtime = "nodejs";

function jsonError(message: string, status: number) {
  return NextResponse.json({ error: message }, { status });
}

/** 멱등: 동일 키는 한 번만 처리. 이전 시도가 오류로 끝난 경우에는 재시도를 허용. */
async function claimWebhookEvent(params: {
  provider: string;
  idempotencyKey: string;
  eventKind: string;
  payload: Record<string, unknown>;
}): Promise<{ isNew: boolean }> {
  const db = getDb();
  const inserted = await db
    .insert(billingWebhookEvents)
    .values({
      provider: params.provider,
      idempotencyKey: params.idempotencyKey,
      eventKind: params.eventKind,
      payload: params.payload,
      receivedAt: new Date(),
    })
    .onConflictDoNothing({ target: billingWebhookEvents.idempotencyKey })
    .returning({ id: billingWebhookEvents.id });

  if (inserted.length > 0) {
    return { isNew: true };
  }

  // 이미 존재: 이전 시도가 오류로 끝났다면 재시도 허용 (오류 플래그 초기화)
  const existing = await db
    .select({ processingError: billingWebhookEvents.processingError })
    .from(billingWebhookEvents)
    .where(eq(billingWebhookEvents.idempotencyKey, params.idempotencyKey))
    .limit(1);

  if (existing[0]?.processingError) {
    await db
      .update(billingWebhookEvents)
      .set({ processingError: null })
      .where(eq(billingWebhookEvents.idempotencyKey, params.idempotencyKey));
    return { isNew: true };
  }

  return { isNew: false };
}

async function markEventError(idempotencyKey: string, err: string): Promise<void> {
  const db = getDb();
  await db
    .update(billingWebhookEvents)
    .set({ processingError: err })
    .where(eq(billingWebhookEvents.idempotencyKey, idempotencyKey));
}

/**
 * PortOne V2 결제 웹훅: 본문의 payment_id로 API 재조회 후 금액·사용자 일치 시 구독 반영.
 * 결제 생성 시 `customData: JSON.stringify({ userId })` 를 넣어야 사용자 매칭이 됩니다.
 */
async function handleV2PaymentWebhook(body: PortOneV2WebhookBody): Promise<NextResponse> {
  const paymentId = body.payment_id?.trim();
  const txId = body.tx_id?.trim();
  if (!paymentId || !txId) {
    return jsonError("Missing payment_id or tx_id", 400);
  }

  const apiKey = process.env.PORTONE_API_KEY?.trim();
  if (!apiKey) {
    return jsonError("Server misconfiguration: PORTONE_API_KEY", 500);
  }

  const idempotencyKey = `portone:v2:${paymentId}:${txId}`;
  const { isNew } = await claimWebhookEvent({
    provider: "portone",
    idempotencyKey,
    eventKind: "v2.payment",
    payload: body as Record<string, unknown>,
  });
  if (!isNew) {
    return NextResponse.json({ ok: true, duplicate: true });
  }

  try {
    const token = await getPortOneV2AccessToken(apiKey);
    const paymentJson = await fetchPortOneV2Payment(token, paymentId);
    const userId = extractUserIdFromPortOnePayment(paymentJson);

    if (!userId) {
      await markEventError(
        idempotencyKey,
        "Could not resolve userId from payment (set customData.userId on payment request)",
      );
      return jsonError("User resolution failed", 422);
    }

    const root = paymentJson as Record<string, unknown>;
    const payment = (root.payment ?? root) as Record<string, unknown>;
    const status = normalizePortOnePaymentStatus(payment.status);

    const paid = status === "paid" || status === "succeeded";
    const jobclawPlan = extractJobClawPlanFromPortOnePayment(paymentJson);
    const planKey = paid ? jobclawPlan : "free";
    const subStatus = paid ? "active" : status || "unknown";

    const metaV2 = {
      webhook: "v2",
      txId,
      rawStatus: payment.status,
      jobclawPlan,
    };
    const db = getDb();
    await db
      .insert(subscriptions)
      .values({
        userId,
        planKey,
        status: subStatus,
        provider: "portone",
        providerPaymentId: paymentId,
        merchantOrderRef: typeof payment.id === "string" ? payment.id : paymentId,
        metadata: metaV2,
        updatedAt: new Date(),
      })
      .onConflictDoUpdate({
        target: subscriptions.userId,
        set: {
          planKey,
          status: subStatus,
          provider: "portone",
          providerPaymentId: paymentId,
          updatedAt: new Date(),
          metadata: metaV2,
        },
      });

    if (paid && (planKey === "basic" || planKey === "pro")) {
      const pr = await provisionPaperclipAgentForJobClawUser({
        userId,
        planKey,
        userEmail: null,
      });
      if (!pr.ok && !pr.skipped) {
        await recordPaperclipProvisionFailure(userId, pr.error);
      }
    }

    return NextResponse.json({ ok: true });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    await markEventError(idempotencyKey, msg);
    return jsonError(msg, 502);
  }
}

function mapSubscriptionLinkStatus(raw: string): { planKey: "free" | "pro"; status: string } {
  const s = raw.trim().toLowerCase();
  if (s === "active") {
    return { planKey: "pro", status: "active" };
  }
  if (s === "cancelled" || s === "canceled" || s === "expired" || s === "inactive") {
    return { planKey: "free", status: s };
  }
  return { planKey: "free", status: raw };
}

/**
 * Subscription Link 웹훅 (PortOne Cloud): signature_hash + HMAC 검증.
 * merchant_order_ref에 Auth `user.id` (UUID)를 넣는 것을 권장.
 */
async function handleSubscriptionLinkWebhook(
  body: PortOneSubscriptionLinkBody,
): Promise<NextResponse> {
  const secret = process.env.PORTONE_SUBSCRIPTION_LINK_SECRET?.trim();
  if (!secret) {
    return jsonError("Server misconfiguration: PORTONE_SUBSCRIPTION_LINK_SECRET", 500);
  }

  if (!verifyPortOneSubscriptionLinkSignature(body, secret)) {
    return jsonError("Invalid signature_hash", 401);
  }

  const orderRef = String(body.order_ref ?? "");
  const statusRaw = String(body.status ?? "");
  const merchantOrderRef = String(body.merchant_order_ref ?? "");
  const idempotencyKey = `portone:sl:${orderRef}:${statusRaw}`;

  const { isNew } = await claimWebhookEvent({
    provider: "portone",
    idempotencyKey,
    eventKind: "subscription_link.status",
    payload: body as Record<string, unknown>,
  });
  if (!isNew) {
    return NextResponse.json({ ok: true, duplicate: true });
  }

  const userId = merchantOrderRef.trim();
  if (!userId || userId.length < 10) {
    await markEventError(idempotencyKey, "merchant_order_ref must be user id (UUID)");
    return jsonError("Invalid merchant_order_ref", 422);
  }

  const { planKey, status } = mapSubscriptionLinkStatus(statusRaw);

  const metaSl = {
    webhook: "subscription_link",
    name: body.name,
  };
  const db = getDb();
  await db
    .insert(subscriptions)
    .values({
      userId,
      planKey,
      status,
      provider: "portone",
      providerPaymentId: orderRef || null,
      merchantOrderRef: merchantOrderRef,
      metadata: metaSl,
      updatedAt: new Date(),
    })
    .onConflictDoUpdate({
      target: subscriptions.userId,
      set: {
        planKey,
        status,
        provider: "portone",
        providerPaymentId: orderRef || null,
        merchantOrderRef: merchantOrderRef,
        updatedAt: new Date(),
        metadata: metaSl,
      },
    });

  return NextResponse.json({ ok: true });
}

export async function POST(req: Request) {
  let raw: unknown;
  try {
    raw = await req.json();
  } catch {
    return jsonError("Invalid JSON", 400);
  }

  if (!raw || typeof raw !== "object") {
    return jsonError("Expected JSON object", 400);
  }

  const body = raw as Record<string, unknown>;

  if ("signature_hash" in body && body.signature_hash) {
    return handleSubscriptionLinkWebhook(body as PortOneSubscriptionLinkBody);
  }

  if (body.payment_id && body.tx_id) {
    return handleV2PaymentWebhook(body as PortOneV2WebhookBody);
  }

  return jsonError(
    "Unsupported webhook shape: need Subscription Link (signature_hash) or V2 payment (payment_id + tx_id)",
    400,
  );
}
