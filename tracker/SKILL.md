---
name: tracker
preamble-tier: 1
version: 0.2.0
description: |
  지원 현황 관리 스킬. 지원 기업/직무 추적, 진행 상태, 일정 관리.
  "지원 현황", "어디 지원했지", "일정", "트래커" 등의 요청 시 활용.
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
---

```bash
# ─── jobstack 프리앰블 ─────────────────────────
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/profiles" "$_JS_STATE/tracker" \
         "$_JS_STATE/company-cache" "$_JS_STATE/interview-history" "$_JS_STATE/sessions"

# 세션 추적
echo "$$" > "$_JS_STATE/sessions/$$"
trap 'rm -f "$_JS_STATE/sessions/$$"' EXIT

# 설정 로딩
_JS_CONFIG="${CLAUDE_SKILL_DIR}/../bin/jobstack-config"
if [ -x "$_JS_CONFIG" ]; then
  PROACTIVE=$("$_JS_CONFIG" get proactive 2>/dev/null || echo "true")
else
  PROACTIVE="true"
fi

# 트래커 파일
TRACKER_FILE="$_JS_STATE/tracker/applications.jsonl"
[ -f "$TRACKER_FILE" ] || touch "$TRACKER_FILE"
echo "TRACKER_FILE=$TRACKER_FILE"
ENTRY_COUNT=$(wc -l < "$TRACKER_FILE" | tr -d ' ')
echo "ENTRY_COUNT=$ENTRY_COUNT"
if [ "$ENTRY_COUNT" -gt 0 ]; then
  echo "--- 최근 지원 ---"
  tail -5 "$TRACKER_FILE"
fi

# 활성 세션 수
for _f in "$_JS_STATE/sessions/"*; do
  [ -f "$_f" ] || continue
  kill -0 "$(basename "$_f")" 2>/dev/null || rm -f "$_f"
done
ACTIVE_SESSIONS=$(ls "$_JS_STATE/sessions/" 2>/dev/null | wc -l | tr -d ' ')
echo "ACTIVE_SESSIONS=$ACTIVE_SESSIONS"
echo "PROACTIVE=$PROACTIVE"
echo "SKILL_NAME=tracker"

# 텔레메트리
echo "{\"skill\":\"tracker\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

> **공통 가드레일**: 작업 시작 전 `${CLAUDE_SKILL_DIR}/../templates/guardrails.md` 를 Read 도구로 읽고 §1~§6 전 규칙을 준수하세요.


# 지원 현황 관리

사용자의 취업 지원 현황을 추적하고 관리합니다.

---

## 상태 모델

지원 상태는 `docs/tracker-states.md`의 canonical 9상태를 따릅니다. **저장은 영문 키, 표시는 한글 라벨**입니다.

| 영문 키 (저장) | 한글 라벨 (표시) | 구분 |
|---|---|---|
| `preparing` | 준비중 | 진행 |
| `applied` | 지원완료 | 진행 |
| `document_pass` | 서류합격 | 진행 |
| `interview_1` | 1차면접 | 진행 |
| `interview_2` | 2차면접 | 진행 |
| `final` | 최종면접 | 진행 |
| `offer` | 최종합격 | 종결(합격) |
| `rejected` | 불합격 | 종결(탈락) |
| `withdrawn` | 지원취소 | 종결(철회) |

- `final`(최종 면접 단계)과 `offer`(최종 합격 결과)는 구분합니다. 전형이 짧으면 중간 단계를 건너뛸 수 있습니다(예: `interview_1` → `offer`).
- `withdrawn`은 `rejected`와 반드시 구분합니다 — 합격률·전환율 산출 시 철회를 탈락으로 집계하면 수치가 왜곡됩니다.

**하위호환 (v1 한글 status 정규화)**: 기존 `applications.jsonl`에 한글 status 값(`서류전형` 등)이 있으면 읽기 시점에 아래 매핑표로 영문 키로 정규화합니다. 파일을 강제로 재작성하지 않습니다.

| v1 값 (기존 파일) | v2 영문 키 |
|---|---|
| 준비중 | `preparing` |
| 서류전형 | `applied` |
| 서류합격 | `document_pass` |
| 1차면접 | `interview_1` |
| 2차면접 | `interview_2` |
| 최종합격 | `offer` |
| 불합격 | `rejected` |

매핑표에 없는 값은 원문을 유지하고 표시 시 `(구버전 상태)`를 붙입니다(임의 추정 변환 금지). 일괄 재작성은 `docs/tracker-states.md`의 마이그레이션 절차(사용자 승인 시에만 재작성, 원본은 `applications.jsonl.bak`으로 백업)를 따릅니다.

---

## 명령 감지

사용자 입력에서 다음 하위 명령을 자동 감지합니다:

| 키워드 | 명령 | 동작 |
|--------|------|------|
| "추가", "add", "새로", "지원했어" | add | 새 지원 항목 추가 |
| "목록", "list", "현황", "보여줘" | list | 전체 지원 목록 표시 |
| "업데이트", "update", "변경", "합격", "불합격" | update | 상태 업데이트 |
| "일정", "calendar", "마감", "데드라인" | calendar | 마감일 캘린더 |
| "통계", "stats", "분석" | stats | 지원 통계 |

키워드가 없으면 현재 지원 현황 요약을 보여주고 AskUserQuestion으로 작업을 선택합니다.

하위 명령 감지가 끝나면 `$_JS_STATE/analytics/skill-usage.jsonl`에 후속 이벤트 1건을 append합니다(`docs/telemetry-events.md` 규격) — `event=detected`, `phase`에 감지된 하위 명령명(add/list/update/calendar/stats), no-arg 진입이면 `no_arg=true`:

```bash
echo '{"skill":"tracker","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","pid":'$$',"event":"detected","phase":"list","no_arg":false}' \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

진입 이벤트(프리앰블 자동 기록)와 구분되는 `detected` 이벤트가 쌓이면, 트래커를 열고도 아무 명령을 쓰지 않는 이탈 지점을 측정할 수 있습니다.

---

## 정체 감지 (진입 시)

스킬 진입 시(모든 하위 명령 공통) `applications.jsonl`을 읽어, `updated_at`이 오늘 기준 7일 이상 지난 **진행 상태**(상태 모델의 preparing~final) 항목을 감지합니다. 오늘 날짜는 `date` 명령으로 확인합니다(훈련 데이터 날짜로 계산 금지). 감지되면 하위 명령 처리 전에 먼저 출력하고 update로 유도합니다:

> 📋 [회사명] 지원 N일째, 결과 업데이트할까요?

규칙:
- **PROACTIVE=false면 넛지 자체를 생략합니다** (프리앰블이 emit한 `PROACTIVE` 값 참조).
- 종결 상태(offer/rejected/withdrawn)는 대상에서 제외합니다.
- 넛지를 출력한 항목은 `last_nudged_at`을 현재 시각(ISO, KST)으로 갱신합니다.
- `last_nudged_at`이 7일 미경과인 항목은 재출력하지 않습니다('7일마다 반복' 성립).
- 사용자가 '나중에'를 선택하면 해당 세션 내에서는 재출력하지 않습니다.

---

## add: 새 지원 항목 추가

AskUserQuestion으로 하나씩 정보를 수집합니다:

1. "지원한 기업명을 알려주세요."
2. "지원 직무를 알려주세요. (예: 백엔드 개발자)"
3. "현재 진행 상태를 알려주세요."
   - 선택지: A) 준비중 B) 지원완료 C) 서류합격 D) 1차면접 E) 2차면접 F) 최종면접
4. "서류 마감일이 있으면 알려주세요. (예: 2026-04-15, 없으면 '없음')"
5. "메모할 내용이 있으면 적어주세요. (없으면 '없음')"

선택한 한글 라벨은 저장 시 상태 모델 매핑표의 영문 키로 변환합니다(예: 지원완료 → `applied`).

해당 회사의 기업분석 캐시(`$_JS_STATE/company-cache/`)가 있으면 company-research Phase 4가 산출한 '종합 적합도' 점수를 자동으로 연결합니다 — `fit_score`에 점수, `research_ref`에 캐시 파일명을 기록합니다. 캐시가 없거나 공고 본문 미확보로 점수가 없으면 두 필드를 생략(또는 null)합니다. 추정치는 넣지 않습니다.

수집 후 JSONL 형식으로 `$_JS_STATE/tracker/applications.jsonl`에 추가:
```json
{"id":"app-001","company":"삼성전자","position":"SW엔지니어","status":"applied","max_stage":"applied","schema_version":2,"applied_at":"2026-03-29","deadline":"2026-04-15","updated_at":"2026-03-29","last_nudged_at":null,"notes":"자소서 3번 문항 확인 필요","fit_score":null,"research_ref":null}
```

JSONL 필드:

| 필드 | 설명 |
|---|---|
| `status` | 현재 상태 (영문 키, 상태 모델 참조) |
| `max_stage` | 파이프라인 최고 도달 단계. 상태 갱신 시 더 높은 단계면 갱신하고, 종결(rejected/withdrawn) 전환 시에는 직전 진행 단계를 보존합니다 |
| `schema_version` | `2` 고정 |
| `last_nudged_at` | 마지막 정체 넛지 시각(ISO, KST). 없으면 null |
| `fit_score` | company-research 종합 적합도 점수 (선택). 미확보 시 생략/null |
| `research_ref` | company-cache 파일명 (선택) |
| `notes` | 자유 메모. **인사담당자 등 제3자의 연락처·이메일은 저장하지 않습니다(이름·역할까지만).** |

ID는 `app-XXX` 형식으로 자동 생성 (기존 최대 ID + 1).

---

## list: 전체 지원 목록

`applications.jsonl`을 읽어 상태 그룹으로 묶어 표시합니다. 그룹은 상태 모델 기준:
- ✅ **진행중** — 면접 단계 (interview_1·interview_2·final)
- ⏳ **대기중** — 준비중·지원완료·서류합격 (preparing·applied·document_pass)
- ❌ **종료** — 최종합격·불합격·지원취소 (offer·rejected·withdrawn)

각 그룹 내에서는 마감일/`updated_at` 순으로 정렬하고, 그룹 헤더에 건수를 표시합니다. `fit_score`가 있는 항목은 점수를 병기합니다.

```
지원 현황 (총 6건)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 진행중 (2건)
  app-003  카카오    서버개발자   1차면접   D-20   적합도 82
  app-006  당근      백엔드       2차면접   -
⏳ 대기중 (2건)
  app-001  삼성전자  SW엔지니어   지원완료  D-15
  app-004  토스      서버개발     준비중    D-30
❌ 종료 (2건)
  app-002  네이버    백엔드개발   최종합격  -
  app-005  라인      백엔드       불합격    -
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
합격률: 서류 67% → 면접 33%
```

- 항목이 **5건 이하**면 테이블 대신 `▸` 마커 리스트로 출력합니다(모바일 가독성).
- 하단 요약줄의 전환율은 `docs/tracker-states.md`의 퍼널 규칙(`max_stage` 기준, withdrawn은 분모 제외)을 따릅니다.

---

## update: 상태 업데이트

1. 현재 진행중인 지원 목록을 보여줍니다.
2. AskUserQuestion: "어떤 지원 건을 업데이트할까요? (ID 또는 기업명)"
3. AskUserQuestion: "새 상태를 선택해주세요."
   - 선택지: A) 서류합격 B) 1차면접 C) 2차면접 D) 최종면접 E) 최종합격 F) 불합격 G) 지원취소
   - add와 동일한 상태 모델 목록을 사용하며, 종결 상태로 '불합격(rejected)'·'지원취소(withdrawn)'를 포함합니다.
4. JSONL 파일에서 해당 항목의 `status`와 `updated_at`을 갱신합니다.
   - `max_stage`: 새 상태가 파이프라인상 더 높은 단계면 갱신하고, 종결(불합격/지원취소) 전환 시에는 직전 진행 단계를 보존합니다.
   - JSONL은 append-only이므로, 전체 파일을 읽어 수정한 뒤 **임시 파일에 쓰고 `mv`로 원본을 교체**합니다(쓰기 중단 시 원본 보존 — 비원자적 재저장으로 인한 데이터 전손 방지).

### 다음 스킬 추천 (상태 전환 직후, PROACTIVE=true일 때)

상태 갱신 직후 맥락에서만 다음 행동을 제안합니다(PROACTIVE=false면 생략):
- 불합격·지원취소로 업데이트 → "`/retro`로 이번 지원을 복기할까요?"
- 서류합격으로 업데이트 → "`/mock_interview` 준비할까요?"
- 마감 임박(D-7 이내) 항목이 있으면 → "`/cover_letter` 마무리를 도와드릴까요?"

### 탈락 후 권리 체크리스트 (불합격·지원취소 전환 시 선택 안내)

불합격/지원취소로 전환하면 아래를 선택적으로 안내합니다:
1. **채용서류 반환 청구권** — 구인자는 청구일부터 14일 내 반환 의무가 있습니다(청구 가능 기간은 기업이 고지).
2. **자동화 결정에 대한 권리** — AI 서류평가·AI 면접 등 자동화된 채용 결정에 대해 거부·설명 요구를 검토할 수 있습니다.
3. **채용심사비용 전가 금지** — 구직자에게 채용 심사 비용을 부담시킬 수 없습니다.
4. **접수·결과 통지 의무** — 채용 결과 통지 의무가 존재합니다(다만 제재 수준은 제한적).

단서:
- 상시 근로자 30명 미만 사업장은 채용절차법 적용 대상이 아닐 수 있습니다.
- 관련 법 개정 여부(공정채용법 추진 등)는 단정하지 말고, 실행 시 WebSearch로 현행 조문·시행 여부를 출처·기준일과 함께 확인합니다.

---

## calendar: 마감일 캘린더

D-day 계산 전 반드시 `date` 명령으로 KST 오늘 날짜를 확인하고, 출력 상단에 `기준일: YYYY-MM-DD (KST)`를 명시합니다(훈련 데이터 날짜로 계산 금지).

마감일이 있는 지원 건을 날짜순으로 정렬하여 표시합니다. 마감일이 지난 항목은 캘린더에서 제외하지 않고 `⚠️ 마감 경과 — 결과 확인 필요` 그룹으로 분리해 update로 유도합니다.

```
기준일: 2026-04-01 (KST)
다가오는 마감일
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 04-15 (D-14)  삼성전자 SW엔지니어 [지원완료]
📅 04-20 (D-19)  카카오 서버개발자 [1차면접]
📅 04-30 (D-29)  토스 서버개발 [준비중]

⚠️ 마감 경과 — 결과 확인 필요
📅 03-25 (D+7)   네이버 백엔드개발 [지원완료]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

D-day가 7일 이내인 건은 강조 표시합니다.

---

## stats: 지원 통계

상태 분포와 퍼널 전환율을 표시합니다. 전환율은 `docs/tracker-states.md`의 퍼널 규칙(`max_stage` 기준, withdrawn은 분모에서 제외)을 따릅니다.

```
지원 통계
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
총 지원:        6건
진행중:         2건
최종합격:       1건
불합격:         1건
지원취소:       0건

상태별 분포:
  준비중     ■         1건
  지원완료   ■         1건
  서류합격   ■         1건
  1차면접    ■         1건
  2차면접    ■         1건
  불합격     ■         1건

퍼널 전환율:
  서류 통과율   67% (max_stage ≥ 서류합격)
  면접 통과율   33% (offer / max_stage ≥ 1차면접)

평균 진행 기간: 14일
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

- `fit_score`가 있는 항목은 점수를 병기합니다. 점수가 없는 건은 `-`로 표기하고 추정치는 넣지 않습니다.
- **적합도 상위 vs 하위 서류합격률 비교**는 상·하위 각 그룹에 결과가 확정된 건이 **3건 이상일 때만** 출력하고, 미만이면 해당 줄을 생략합니다(소표본 노이즈 방지).

---

## 추적 제안 규칙 (PROACTIVE=true일 때)

프리앰블이 emit한 `PROACTIVE` 값을 소비합니다:
- tracker 진입 시 **직전 대화 맥락에 특정 기업 한 곳의 분석 결과나 그 공고용 첨삭 결과가 있으면** "이 지원 건을 트래커에 추가할까요?"를 제안합니다.
- 여러 회사가 동시에 언급된 맥락에서는 제안하지 않습니다(오등록 방지).
- **PROACTIVE=false면 제안 자체를 생략합니다.**

---

## 보이스

간결하고 정확하게. 추적 데이터를 깔끔한 테이블로 표시합니다. 불필요한 코칭 없이 정보 전달에 집중합니다.

---

## AskUserQuestion 규칙

1. **현재 상황** — 1-2문장 요약
2. **질문** — 명확하고 구체적
3. **추천** — 있으면 포함
4. **선택지** — `A) ... B) ...`

한 번에 하나의 질문만.

---

## 완료 상태

작업 완료 시 `templates/completion-status.md`의 4종 상태 중 하나를 출력합니다:
- **완료 (DONE)** — 요청 작업 수행 완료
- **우려사항 있는 완료 (DONE_WITH_CONCERNS)** — 완료했으나 사용자가 알아야 할 사항 존재
- **차단됨 (BLOCKED)** — 진행 불가. 차단 요인과 시도한 내용 기술
- **추가 정보 필요 (NEEDS_CONTEXT)** — 계속하기 위한 정보 부족
