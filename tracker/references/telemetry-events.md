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

# (초안) docs/telemetry-events.md 에 추가할 절 — 운영 학습 로그(learnings.jsonl)

> **통합 방법**: 이 파일 전체를 `docs/telemetry-events.md` 파일 끝에 그대로 이어 붙인다(기존 문서의
> "## 퍼널 지표 정의" 절 다음). 제목 레벨은 기존 문서 안에서 하나의 새 절로 들어가도록 이미
> `##`로 맞춰 놓았다. 통합 시 아래 "부록: 원본 U-20 요구사항" 절은 지우고 본문만 남긴다.
> (검토 보고서 U-20, v1.0 후보 — 2026-09 draft, 미확정)

---

## 운영 학습 로그 — learnings.jsonl

skill-usage.jsonl 이 "스킬이 얼마나 쓰였는지"를 재는 것과 달리, 이 로그는 "스킬을 운영하면서
무엇이 반복해서 문제였는지"를 재는 **별도 파일**이다. gstack `learnings.jsonl` 패턴을 축소
도입했다(검토 보고서 §2-3, §3 U-20). 목적은 두 가지뿐이다 — ① auto 대시보드에 "요즘 반복해서
막히는 지점 상위 3건"을 보여주는 것, ② 다음 버전업 검토 시 어느 플랫폼 셀렉터·자료 요청이
실제로 반복되는지 근거로 쓰는 것. **사용자 개인의 사용 이력이나 만족도를 추적하는 용도가
아니다** — 그 목적이면 skill-usage.jsonl 의 퍼널 지표를 쓴다.

- **저장**: `$_JS_STATE/analytics/learnings.jsonl` (append-only, `bin/jobstack-learn` 이 유일한
  쓰기 경로 — 스킬이 이 파일에 직접 Bash로 append 하지 않는다. 결정적 스크립트 계층 원칙, U-09
  와 동일)
- **범위**: skill-usage.jsonl 과 동일하게 CLI 로컬 파일 한정 — **네트워크 전송 없음**, 사용자
  본인 기기 밖으로 나가지 않는다. jobclaw 등 서버측 배포 시 consent_type 동의 항목이 먼저
  필요하다는 원칙도 동일하게 적용된다.
- **PII 금지**: 문서 내용, 회사명, 사용자 식별정보를 기록하지 않는다 — "무엇이(플랫폼·필드 종류)
  문제였는지"만 남기고 "누구의 무엇이 문제였는지"는 남기지 않는다. PII 3등급 정책(서비스 사용자
  데이터는 익명·집계만, `templates/guardrails.md` §1)과 동일 원칙이며, `bin/jobstack-learn` 이
  `key`·`note` 에 이메일·전화번호·URL 쿼리·한글 이름으로 보이는 값이 있으면 **기계적으로
  거부**한다(정규식 휴리스틱 — 완전하지 않으므로 규칙을 대신하지 않는다. 아래 §PII 참조).

### 스키마

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `ts` | string | 예 | UTC ISO 8601 (`YYYY-MM-DDTHH:MM:SSZ`) — skill-usage.jsonl 의 `ts` 와 같은 형식 |
| `skill` | string | 예 | 스킬 디렉토리명 리터럴 (예: `job-search`) |
| `kind` | string | 예 | 아래 어휘 6종 중 하나 (닫힌 집합) |
| `key` | string | 예 | 짧은 식별자. `[a-z0-9][a-z0-9_.-]{1,79}` — 소문자·숫자·`.`·`_`·`-` 만, 2~80자. 예: `saramin.item_recruit`, `jobstack-export.pandoc` |
| `note` | string | 선택 | 60자 이내. **운영 메타 한 줄만** — 사용자 문서 내용·회사명·개인정보 금지 |
| `session` | string | 선택 | `${CLAUDE_SESSION_ID}` 등 세션 식별자. skill-usage.jsonl 의 `session` 필드와 같은 용도(연결 키) |
| `dup` | boolean | 선택 | 같은 (`skill`,`kind`,`key`) 가 24시간 안에 이미 있을 때만 `true`. 값은 `true` 만 허용 — 불필요하면 필드 자체를 생략한다 |

`count` 필드는 **저장하지 않는다.** 같은 (`skill`,`kind`,`key`) 가 24시간 안에 다시 감지되면
기존 줄을 고쳐 쓰지 않고(append-only 원칙 — skill-usage.jsonl 과 동일하게 원자적 재작성 없이
그냥 이어 쓴다) 새 줄을 `dup:true` 로 추가한다. 건수는 저장된 숫자가 아니라 **집계 시점에 줄
수를 세어** 구하므로, `dup` 여부와 무관하게 항상 정확하다.

### kind 어휘 6종 (닫힌 집합)

`docs/telemetry-events.md` 의 이벤트 어휘 6종과 같은 원칙 — **이 6종이 닫힌 집합이다.** 여기
없는 `kind` 값을 스킬이 임의로 만들어 쓰지 않는다. 새 kind 가 필요하면 이 문서에 먼저 정식으로
추가하고, `bin/jobstack-learn` 의 `KIND_CHOICES` 를 같은 PR에서 함께 바꾼다(문서와 코드가
어긋나면 `validate` 가 기존 줄을 오탐 처리하게 된다).

| kind | 의미 | 기록 시점 예시 |
|---|---|---|
| `selector_broken` | 플랫폼 페이지 구조가 바뀌어 셀렉터·파서가 깨짐(파싱 0건·구조 불일치) | 사람인 목록 파싱이 계속 0건 |
| `source_blocked` | 소스가 접근 자체를 차단(403·챌린지·네트워크 차단 등) | 원티드 API 가 챌린지로 막힘 |
| `data_requested` | 자동 수집·추출에 실패해 사용자에게 자료를 요청하는 흐름으로 전환됨 | 이력서에서 경력 공백 사유를 못 읽어 사용자에게 되물음 |
| `tool_missing` | 외부 도구·의존성이 없어 폴백 경로를 탐(설치 안내로 대체) | pandoc·hwp 변환기 미설치 |
| `format_mismatch` | 산출물 형식이 기대와 달라 후속 처리가 실패·중단됨 | 변환된 docx에 미확인 placeholder 잔존(exit 4 반복) |
| `other` | 위 5종에 해당하지 않는 운영 이슈 | (신중히 사용 — 반복되면 새 kind 신설을 먼저 검토) |

### PII 휴리스틱 (거부 규칙)

`bin/jobstack-learn add` 는 `--key`·`--note` 값에서 아래 패턴이 발견되면 **기록 자체를
거부**하고 exit 1 한다(파일에는 아무것도 남지 않는다):

- 이메일 주소
- 한국 전화번호 (예: `010-1234-5678`)
- URL 쿼리 토큰 (`?key=value`, `&id=1` 형태 — 플랫폼·엔드포인트 이름 자체는 허용)
- 한글 이름으로 보이는 값: "라벨: 성+이름"(예: "담당자: 김민수") 형태, 또는 한국 문서에서
  예시로 흔히 쓰이는 이름(예: "홍길동")

**휴리스틱은 완전하지 않다.** 접미사·라벨·콜론 없이 홀로 등장하는 한글 이름은 못 잡을 수
있고, 반대로 "고객님"처럼 이름이 아닌 일반 존칭과의 오탐을 피하려고 신호를 일부러 좁게
잡았다. 즉 **이 검사를 최종 방어선으로 쓰지 않는다** — 스킬이 `add` 를 호출할 때 애초에
`key`/`note` 에 사람 이름·회사명·문서 인용을 넣지 않는 것이 1차 규칙이고, 정규식 검사는
그 규칙을 어긴 명백한 경우를 잡아내는 기계적 backstop이다. `key` 는 charset 자체가
`[a-z0-9_.-]` 로 좁아 이메일·한글 이름이 애초에 들어갈 수 없으므로, 실질적인 PII 위험은
자유 텍스트인 `note` 쪽에 있다 — **note 를 쓸 때 특히 주의한다.**

`jobstack-learn validate` 는 이미 기록된 줄도 같은 휴리스틱으로 재검사한다(스키마 변경 이전
줄, 수기 편집된 줄 대비).

### 보존 기간

- 이 로그는 **자동으로 삭제·순환(rotate)하지 않는다** — skill-usage.jsonl 과 같은 append-only
  철학이다. "운영상 반복되는 문제"만 기록 대상이라 이벤트 빈도가 낮게 설계되어 있고(스킬을 쓸
  때마다가 아니라 진단된 문제가 있을 때만), 무기한 보존해도 파일 크기 부담이 크지 않다.
  로컬·사용자 소유 파일이라는 점도 skill-usage.jsonl 과 같다(§범위).
- "최근" 신호를 유지하는 역할은 삭제가 아니라 **필터**가 맡는다 — `jobstack-learn top` 은
  `--since` 로 기간을 한정할 수 있고, auto 대시보드는 기본(전체 기간·상위 3건)으로 호출한다.
- 이미 고친 문제가 계속 상위 3건에 남아 대시보드 소음이 되는 상황을 막는 "해결 표시"
  (예: `jobstack-learn resolve`) 는 **이 초안 범위에 없다.** 실제로 반복 노출이 문제로
  확인되면 후속 항목으로 추가한다(NOTES.md 의 "이번 초안이 하지 않은 것" 참조) — 정식 등록 전
  임의로 스킬 본문에서 흉내 내지 않는다.
- 사용자가 직접 정리하고 싶으면 `learnings.jsonl` 파일을 지우거나 편집해도 안전하다(다른
  상태 파일과의 참조 관계가 없는 독립 로그).

### auto 대시보드 소비 규칙

- auto Phase 3(진행 상태 대시보드) 이 대시보드 출력 끝에 "운영 메모 상위 3건"을 추가로 보여줄
  수 있다 — 구체적 문구·Bash 스니펫 초안은 `OUT/auto-dashboard-patch.md` 참조.
- 호출은 정확히 `"$_JS_BIN/jobstack-learn" top --n 3` 한 줄이다. **출력이 빈 문자열이면 그
  절 전체를 표시하지 않는다** — "기록 없음"류 문구를 대신 보여주지 않는다. 운영 메모는 내부
  신호이지 사용자에게 매번 확인시켜야 하는 항목이 아니므로, 문제가 없으면 조용히 생략되는 쪽이
  맞다(반대로 fetch-diag 같은 진단 도구는 "기록 없음"을 명시적으로 보여준다 — 목적이 다르다).
- 대시보드는 **집계만 소비**한다 — `list`/`add`/`validate` 는 사람이 터미널에서 직접 쓰는
  하위 명령이지 스킬 본문에서 호출하는 대상이 아니다.

### 어느 스킬이 언제 `add` 를 호출하는가

아래 표는 이 로그를 실제로 채우는 지점의 초안이다. **공통 원칙**: 매 실패·매 재시도마다
기록하지 않는다 — 진단이 끝나 "이건 반복될 만한 운영 문제"로 판단된 시점에만 1회 기록한다
(예: job-search 는 "수집 0건"이라는 진단이 끝난 뒤에만 기록하지, 네트워크 타임아웃 한 번마다
기록하지 않는다). 이 표는 초안이므로 실제 SKILL.md 반영 시 각 스킬의 진단 로직과 맞춰
조정한다.

| 스킬 | 호출 시점 | kind | key 예시 |
|---|---|---|---|
| job-search | 채용공고 수집 0건 진단 후, 원인이 페이지 구조 변경(파서 실패)으로 보일 때 | `selector_broken` | `saramin.item_recruit` |
| job-search | 채용공고 수집 0건 진단 후, 원인이 접근 차단(챌린지·403)으로 보일 때 | `source_blocked` | `wanted.search_api` |
| company-research | 조회 소스가 차단돼 "자료를 붙여넣어 달라"는 요청으로 전환할 때 | `source_blocked` | `jobplanet.review` |
| salary | 조회 소스가 차단돼 자료 요청으로 전환할 때 | `source_blocked` | `catch.salary_page` |
| resume / cover-letter | 이력서·자소서에서 자동 추출이 안 되는 항목이 있어 사용자에게 되물을 때(같은 필드가 반복되면) | `data_requested` | `resume.career_gap_reason` |
| auto | `.hwp` 변환기(kordoc/rhwp) 부재로 "HWPX로 저장해 재업로드" 안내로 폴백할 때(exit 3) | `tool_missing` | `hwpx2md.hwp_converter` |
| export(jobstack-export) | pandoc·Node docx 폴백 모두 불가할 때(exit 2) | `tool_missing` | `jobstack-export.pandoc` |
| export(jobstack-export) | 변환 결과에 미확인 placeholder 가 반복해서 남을 때(exit 4) | `format_mismatch` | `jobstack-export.placeholder` |
| (모든 스킬 공통) | 위 5종 어디에도 안 맞는 운영 이슈 | `other` | 스킬별로 정의 |

---

## 부록: 원본 U-20 요구사항 (통합 시 삭제)

> 검토 보고서 `docs/plans/version-upgrade-review-2026-09.md` §3 U-20 행 원문:
> "운영 학습 로그 — gstack `learnings.jsonl` 패턴을 축소 도입: 스킬 종료 시 '운영상 배운
> 것'(어느 플랫폼 셀렉터가 깨졌는지, 어떤 자료 요청이 반복되는지)을
> `$_JS_STATE/analytics/learnings.jsonl`에 메타만 기록하고 auto 대시보드가 상위 3건을
> 보여줌. 사용자 문서 내용은 기록하지 않음(telemetry-events.md PII 규칙 준수)." 수용 기준:
> "이벤트 어휘를 `docs/telemetry-events.md`에 정식 추가한 뒤에만 append."
>
> 이 초안 문서가 그 수용 기준의 "정식 추가" 절차 자체다 — 리뷰·확정 전까지는 스킬 본문에서
> `jobstack-learn add` 를 호출하지 않는다.
