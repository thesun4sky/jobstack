# 텔레메트리 이벤트 규격 — skill-usage.jsonl

스킬 사용 흐름을 측정하는 로컬 이벤트 로그의 단일 정의. retro의 퍼널 집계가 이 규격을 기준으로 동작한다.

- **저장**: `$_JS_STATE/analytics/skill-usage.jsonl` (append-only)
- **범위**: CLI 로컬 파일 한정 — **네트워크 전송 없음**. 사용자 본인 기기 밖으로 나가지 않는다 (Council #1 Q7). jobclaw 등 서버측 per-user 환경에 배포할 경우 **consent_type 동의 항목 추가가 필수 전제**다.
- **PII 금지**: 문서 내용, 회사명, 사용자 식별정보를 이벤트에 기록하지 않는다 — 이벤트 메타(스킬명·단계·시각)만. (PII 3등급 정책: 서비스 사용자 데이터는 익명·집계만)

---

## 공통 필드

| 필드 | 타입 | 설명 |
|---|---|---|
| `skill` | string | 스킬 디렉토리명 리터럴 |
| `ts` | string | UTC ISO 8601 (`date -u +%Y-%m-%dT%H:%M:%SZ`) |
| `pid` | int | `$$` — 프리앰블 entry와 후속 이벤트를 같은 세션으로 연결하는 키 (v1). v0.4.0부터 프리앰블이 동적 주입(별도 셸)으로 실행되므로 entry의 `pid`는 그 셸의 PID이며 후속 이벤트의 `pid`와 다를 수 있다 — 연결 키로는 `session`을 우선한다 |
| `session` | string | (v0.4.0+, 선택) Claude Code `${CLAUDE_SESSION_ID}`. 프리앰블 entry가 기록하며, 후속 이벤트도 알 수 있으면 같은 값을 넣는다. 없으면 생략(v1 호환) |
| `event` | string | 아래 어휘 6종. **생략 시 v1 entry로 해석** (하위호환) |

## 이벤트 어휘 6종

| event | 기록 주체 | 시점 | 추가 필드 |
|---|---|---|---|
| `entry` | 프리앰블 (자동) | 스킬 시작 | 없음 — `event` 필드 생략 허용 (기존 v1 라인과 동일 형태) |
| `detected` | Claude (Bash append) | 단계/모드 감지 완료 직후 | `phase`(감지된 단계·케이스), `no_arg`(true\|false — no-arg 진입 별도 집계), `mode`(스킬별 세부 모드, 예: 면접 페르소나) |
| `submitted` | Claude | 사용자 문서 제출 시 | 없음 |
| `diagnosed` | Claude | 1차 진단 완료 시 | 없음 |
| `second_review` | Claude | 2차 점검(재리뷰) 요청 시 | 없음 |
| `exported` | Claude | jobstack-export 파일 산출 성공 시 | 없음 |

**이 6종이 닫힌 집합이다.** 스킬은 여기 없는 `event` 값이나 표에 없는 추가 필드(예: `done`/`recheck`/`combo`/`stage`/`tags`)를 임의로 append하지 않는다 — 그런 라인은 retro 집계가 해석하지 못하고, 검색어·회사명 같은 사용자 값이 섞이면 §PII 금지 규칙도 위반한다. 새 지표가 필요하면 먼저 이 문서에 이벤트/필드를 정식 추가한 뒤 스킬을 맞춘다. 회고·검색처럼 스킬 자체의 상세 데이터는 skill-usage.jsonl이 아니라 각 스킬의 산출 파일(회고 YAML 등)에 저장한다.

## append 관례

프리앰블과 동일 — 실패해도 스킬 동작에 영향이 없어야 한다:

```bash
echo '{"skill":"auto","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","pid":'$$',"event":"detected","phase":"case-2","no_arg":false}' \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

## 예시 JSONL (한 세션의 흐름)

```jsonl
{"skill":"auto","ts":"2026-07-03T09:00:01Z","pid":4242}
{"skill":"auto","ts":"2026-07-03T09:00:05Z","pid":4242,"event":"detected","phase":"case-3","no_arg":false}
{"skill":"cover-letter","ts":"2026-07-03T09:02:10Z","pid":4310}
{"skill":"cover-letter","ts":"2026-07-03T09:03:00Z","pid":4310,"event":"submitted"}
{"skill":"cover-letter","ts":"2026-07-03T09:08:40Z","pid":4310,"event":"diagnosed"}
{"skill":"cover-letter","ts":"2026-07-03T09:20:12Z","pid":4310,"event":"second_review"}
{"skill":"cover-letter","ts":"2026-07-03T09:31:55Z","pid":4310,"event":"exported"}
```

## 퍼널 지표 정의 (retro 집계 기준)

| 지표 | 정의 | 의미 |
|---|---|---|
| 문서 제출률 | `submitted` 수 / `entry` 수 | 진입 대비 실제 문서를 낸 비율 (신뢰 지표) |
| 2차 점검 요청률 | `second_review` 수 / `diagnosed` 수 | 진단 품질 + 재방문 지표 |

- 하위호환: `event` 필드가 없는 라인은 전부 `entry`로 집계한다 — 기존 v1 파일과 혼재해도 동작.
- 소비 스킬 반영 지점: auto(`detected` 필수 — 라우팅 결과 기록), cover-letter/resume/review(`submitted`/`diagnosed`/`second_review`), 파일 산출 스킬(`exported`).
