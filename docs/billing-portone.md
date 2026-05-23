# PortOne 구독·웹훅 MVP (PR-D)

## 지원하는 두 가지 웹훅 형태

| 경로 | 본문 식별 | 검증 방식 |
|------|-----------|-----------|
| **PortOne V2 결제** | `payment_id` + `tx_id` | `PORTONE_API_KEY`로 액세스 토큰 발급 후 `GET /v2/payments/{payment_id}` 로 재조회 |
| **Subscription Link** (PortOne Cloud) | `signature_hash` 등 | `PORTONE_SUBSCRIPTION_LINK_SECRET` 로 HMAC-SHA256(Base64) — [문서](https://docs.portone.cloud/docs/subscription-link-webhook-response) |

엔드포인트: `POST /api/webhooks/portone` (JSON)

## 스테이징에서 한 사이클 재현 (V2)

1. `.env.local`에 `PORTONE_API_KEY` 설정 (포트원 관리자 콘솔 V2 API Secret).
2. 공개 URL에 앱 배포 후 관리자 콘솔 **결제연동 → 웹훅**에 `https://<host>/api/webhooks/portone` 등록.
3. 클라이언트에서 결제 요청 시 `customData`에 `userId`와 (JobClaw의 경우) `jobclawPlan`: `"basic"` | `"pro"` 를 포함한다. 서버는 PortOne 결제 재조회 응답의 `customData`에서 동일 필드를 읽는다 (`apps/web/lib/billing/portone.ts`).
4. 테스트 결제 → 웹훅 수신 → `subscription` 행 갱신 → `GET /api/me` 의 `billing.planKey` 가 `basic` 또는 `pro` 인지 확인.
5. (선택) Paperclip 에이전트 자동 생성: `PAPERCLIP_API_URL`, `PAPERCLIP_COMPANY_ID`, `PAPERCLIP_PROVISION_BEARER_TOKEN` 등을 설정하면 웹훅 처리 직후 `POST /api/companies/:companyId/agents` 가 호출되고, 성공 시 구독 `metadata.paperclipAgentId` 에 ID가 기록된다.

## JobClaw 브라우저 결제 (E2E)

1. `.env.local`에 `NEXT_PUBLIC_PORTONE_STORE_ID`, `NEXT_PUBLIC_PORTONE_CHANNEL_KEY`(관리자 콘솔 **연동 정보**), `AUTH_URL`, 위와 동일한 `PORTONE_API_KEY` 를 둔다.
2. 로그인한 사용자로 `/jobclaw/checkout?plan=basic&billing=monthly` 접속 → **PortOne으로 결제하기** 로 결제창 호출.
3. 샌드박스/테스트 결제 완료 후 리다이렉트: `/jobclaw/onboarding?from=checkout`.
4. 서버 로그·DB에서 웹훅 처리 및 `subscription` 갱신 확인. 실패 시 `billing_webhook_event.processingError` 또는 구독 `metadata.paperclipProvisionError` 를 본다.

## Subscription Link 스파이크

1. `PORTONE_SUBSCRIPTION_LINK_SECRET` 를 포트원 Cloud 대시보드 시크릿과 동일하게 설정.
2. 구독 링크 생성 시 `merchant_order_ref`에 **Auth `user.id`(UUID)** 를 넣는다 (MVP 매핑 규칙).
3. 웹훅이 오면 `signature_hash` 분기에서 HMAC 검증 후 동일 사용자 `subscription` 갱신.

## 환경 변수 체크리스트

- `DATABASE_URL` — 마이그레이션 적용 후 웹훅이 DB에 기록됨.
- `PORTONE_API_KEY` — V2 결제 웹훅 처리 시 **필수**.
- `NEXT_PUBLIC_PORTONE_STORE_ID` / `NEXT_PUBLIC_PORTONE_CHANNEL_KEY` — JobClaw(및 브라우저 SDK) 결제창 호출 시 **필수**.
- `PORTONE_SUBSCRIPTION_LINK_SECRET` — Subscription Link만 쓸 때 **필수**.
- Paperclip 프로비저닝 — `PAPERCLIP_*` (`.env.example` 주석 참고). 없으면 구독만 갱신되고 에이전트 생성은 건너뜀.

## Job / 기능 플래그 훅

서버 코드에서 `getEffectivePlan(userId)` (`apps/web/lib/billing/plan.ts`)를 import 하여:

- 유료는 `planKey === "basic"` 또는 `planKey === "pro"` 일 때 (`getEffectivePlan`).
- `POST /api/v1/jobs` 등에서 `getEffectivePlan` 후 거절하려면 예시:

```typescript
import { getEffectivePlan } from "@/lib/billing/plan";

const plan = await getEffectivePlan(session.user.id);
if (plan.planKey === "free") {
  return NextResponse.json({ error: "Paid plan required" }, { status: 402 });
}
```

(실제 쿼터 숫자는 제품 정책에 맞게 별도 상수로 관리.)

## Stripe 대안 게이트 (TSK-477)

PortOne **국내 PG·구독 링크** 조합이 요구사항(세금계산서, 특정 PG, 해외 카드 제한 등)과 맞지 않으면:

- **Stripe Billing + Checkout** 으로 동일 스키마(`subscription`, `billing_webhook_event`)를 채우는 분기안을 검토한다.
- 웹훅 엔드포인트는 `POST /api/webhooks/stripe` 를 추가하고, `provider` 컬럼으로 `stripe` / `portone` 을 구분한다.
- 멱등 키는 Stripe `event.id` 를 사용한다.

이 저장소의 MVP는 PortOne V2 + Subscription Link 검증까지 포함하며, Stripe는 별도 PR로 연동하는 것이 안전하다.
