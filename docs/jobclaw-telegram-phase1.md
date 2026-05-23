# JobClaw Phase 1 — 단일 Telegram 봇 (userId 파티션)

## 목표

- 하나의 봇 토큰으로 여러 사용자를 동시에 처리한다.
- `telegram user id` 단위로 런타임 세션과 디스크 레지스트리를 분리한다.
- 스킬 선택은 InlineKeyboard로 제공하고, 일반 메시지는 선택된 스킬 컨텍스트와 함께 Claude CLI 브릿지로 전달한다.

## 코드 위치

- 앱: `apps/jobclaw-telegram`
- 엔트리: `src/index.ts` → `createBot()` (`src/bot.ts`)

## 세션 격리

1. **메모리**: `src/session-state.ts`의 `Map<telegramUserId, ChatSession>` — 프로세스 내에서 사용자별 `activeSkillSlug` 유지.
2. **영속**: `data/telegram-users.json` (`UserRegistry`) — 등록 시각, 플랜 티어, 마지막 스킬 slug.

두 명 이상이 동시에 메시지를 보내면 각 `ctx.from.id` 키가 분리되므로 세션이 섞이지 않는다.

## 구독·등록

- `/start`, `/menu`: `src/subscription.ts`의 `evaluateSubscription()` 통과 후 `UserRegistry.register()`.
- Phase 1 기본값은 `JOBCLAW_SUBSCRIPTION_MODE=allowlist` + `JOBCLAW_ALLOWED_TELEGRAM_IDS` (로컬 테스트용).
- 로컬 전체 허용: `JOBCLAW_SUBSCRIPTION_MODE=open`.

웹앱 `subscription` 테이블과의 실시간 연동은 후속 단계에서 내부 API로 교체한다.

## Claude CLI 브릿지

- `src/claude-bridge.ts`가 사용자 프롬프트를 stdin으로 넘기고 stdout을 수집한다.
- 환경 변수 `CLAUDE_CLI_COMMAND`(기본 `claude`), `CLAUDE_CLI_CWD`로 실행 위치를 조정한다.

## 텔레그램 포맷

- `src/format/telegram.ts`: MarkdownV2 이스케이프, 4096자 청크 분할, 단순 표 텍스트 헬퍼.

## 실행

```bash
cd apps/jobclaw-telegram
cp ../../.env.example .env   # TELEGRAM_BOT_TOKEN 등 채우기
pnpm install
pnpm dev
```

## 다음 단계 (Phase 2+)

- PortOne/DB 기반 구독 검증 API와 연동.
- Redis 등 외부 세션 저장소로 확장 (다중 인스턴스).
- 문서 메시지 실제 파싱 후 스킬 입력으로 연결.
