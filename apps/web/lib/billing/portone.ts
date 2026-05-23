import { createHmac, timingSafeEqual } from "node:crypto";

/** PortOne V2 payment webhook body (관리자 콘솔 / noticeUrls). */
export type PortOneV2WebhookBody = {
  payment_id?: string;
  tx_id?: string;
  status?: string;
};

/** PortOne Subscription Link webhook (docs.portone.cloud). */
export type PortOneSubscriptionLinkBody = {
  signature_hash?: string;
  currency?: string;
  order_ref?: string;
  merchant_order_ref?: string;
  status?: string;
  [key: string]: unknown;
};

function timingSafeEqualB64(a: string, b: string): boolean {
  try {
    const ba = Buffer.from(a, "base64");
    const bb = Buffer.from(b, "base64");
    if (ba.length !== bb.length) return false;
    return timingSafeEqual(ba, bb);
  } catch {
    return false;
  }
}

/**
 * Subscription Link 웹훅 서명 검증 (공식 문서: currency, merchant_order_ref, order_ref, status 알파벳순 → url-encoded → HMAC-SHA256 → Base64).
 * @see https://docs.portone.cloud/docs/subscription-link-webhook-response
 */
export function verifyPortOneSubscriptionLinkSignature(
  body: PortOneSubscriptionLinkBody,
  secretKey: string,
): boolean {
  const signatureHash = body.signature_hash;
  if (!signatureHash || !secretKey) return false;

  const params = new URLSearchParams();
  params.append("currency", String(body.currency ?? ""));
  params.append("merchant_order_ref", String(body.merchant_order_ref ?? ""));
  params.append("order_ref", String(body.order_ref ?? ""));
  params.append("status", String(body.status ?? ""));
  const data = params.toString();

  const h = createHmac("sha256", secretKey);
  h.update(data);
  const expected = h.digest("base64");
  return timingSafeEqualB64(expected, signatureHash);
}

type SignInResponse = { access_token?: string };

export async function getPortOneV2AccessToken(apiKey: string): Promise<string> {
  const res = await fetch("https://api.portone.io/v2/signin/api-key", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ api_key: apiKey }),
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`PortOne signin failed: ${res.status} ${t}`);
  }
  const data = (await res.json()) as SignInResponse;
  if (!data.access_token) throw new Error("PortOne signin: missing access_token");
  return data.access_token;
}

/** 결제 단건 조회 — 웹훅 본문만 믿지 않고 서버에서 재검증. */
export async function fetchPortOneV2Payment(
  accessToken: string,
  paymentId: string,
): Promise<unknown> {
  const res = await fetch(`https://api.portone.io/v2/payments/${encodeURIComponent(paymentId)}`, {
    method: "GET",
    headers: { Authorization: `Bearer ${accessToken}` },
  });
  if (!res.ok) {
    const t = await res.text();
    throw new Error(`PortOne payment fetch failed: ${res.status} ${t}`);
  }
  return res.json();
}

/** customData(JSON 문자열) 또는 customer_id 등에서 user id 추출 (MVP). */
export function extractUserIdFromPortOnePayment(paymentRoot: unknown): string | null {
  const root = paymentRoot as Record<string, unknown>;
  const payment = (root.payment ?? root) as Record<string, unknown>;

  const custom = payment.customData;
  if (typeof custom === "string" && custom.length > 0) {
    try {
      const j = JSON.parse(custom) as Record<string, unknown>;
      if (typeof j.userId === "string" && j.userId.length > 0) return j.userId;
    } catch {
      /* ignore */
    }
  }

  const customer = payment.customer as Record<string, unknown> | undefined;
  if (customer && typeof customer.id === "string" && customer.id.length > 0) {
    return customer.id;
  }

  return null;
}

/** customData에서 JobClaw 플랜(basic|pro) — 없으면 basic */
export function extractJobClawPlanFromPortOnePayment(
  paymentRoot: unknown,
): "basic" | "pro" {
  const root = paymentRoot as Record<string, unknown>;
  const payment = (root.payment ?? root) as Record<string, unknown>;
  const custom = payment.customData;
  let obj: Record<string, unknown> | null = null;
  if (typeof custom === "string" && custom.length > 0) {
    try {
      obj = JSON.parse(custom) as Record<string, unknown>;
    } catch {
      obj = null;
    }
  } else if (custom && typeof custom === "object") {
    obj = custom as Record<string, unknown>;
  }
  const raw = obj?.jobclawPlan ?? obj?.jobclaw_plan;
  if (raw === "pro" || raw === "basic") return raw;
  return "basic";
}

/** PortOne 결제 객체 status → 소문자 정규화 */
export function normalizePortOnePaymentStatus(raw: unknown): string {
  return String(raw ?? "").toLowerCase();
}
