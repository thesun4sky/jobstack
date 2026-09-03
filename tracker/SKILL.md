---
name: tracker
description: |
  지원 현황 관리 스킬. 지원 기업/직무 추적, 진행 상태, 일정 관리.
  "지원 현황", "어디 지원했지", "일정", "트래커" 등의 요청 시 활용.
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
argument-hint: "[add|list|update|calendar|stats] [회사명] [상태]"
when_to_use: |
  지원한 기업의 진행 상태, 면접 일정, 서류 마감일을 한 곳에서 추적하고 관리할 때 사용한다.
  지원 통계로 진행 흐름을 분석하거나, 정체된 항목을 감지해 다음 액션을 결정할 때 도움이 된다.
  tracker 스킬은 진행 현황 기록에만 집중하고, 면접 회고·분석은 retro 스킬 담당이다.
metadata:
  preamble-tier: 1
  version: 0.2.0
---

!`bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" tracker "${CLAUDE_SESSION_ID}" "${CLAUDE_PLUGIN_DATA:-}"`

> 위 실행 컨텍스트가 비어 있거나 `KEY=VALUE` 목록 대신 `!` 명령·정책 차단 문구가 그대로 보이면(`!` 주입이 꺼진 환경), 첫 Bash 명령으로 `bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" tracker`를 실행해 같은 컨텍스트를 확보하고 `${CLAUDE_SKILL_DIR}/references/guardrails.md`를 Read 하세요. 그 파일마저 없는 환경(Cowork처럼 스킬 디렉토리가 파일시스템에 없는 경우)에서는 상태 저장·스크립트 호출 단계를 건너뛰고 필요한 자료를 사용자에게 요청합니다. `STATE_WRITE_FAILED=true`가 보이면 `JOBSTACK_STATE_DIR` 경로를 사용자에게 확인합니다. 이 스킬의 Bash 스니펫은 첫 줄에 `. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"`를 두어 `$_JS_STATE`·`$_JS_BIN`·`$TODAY`를 불러옵니다.

### 공통 가드레일 (references/guardrails.md)

!`sed '1{/^# /d;}' "${CLAUDE_SKILL_DIR}/references/guardrails.md"`

# 지원 현황 관리

사용자의 취업 지원 현황을 추적하고 관리합니다. 저장·계산은 `"$_JS_BIN/jobstack-tracker"`가 담당합니다 — 스킬은 하위 명령을 호출하고 그 출력을 해석해 사용자에게 보여주는 데 집중합니다.

---

## 상태 모델

`jobstack-tracker`가 `${CLAUDE_SKILL_DIR}/references/tracker-states.md`의 canonical 9상태 계약(저장은 영문 키, 표시는 한글 라벨)과 v1 정규화·마이그레이션 절차를 구현합니다.

| 한글 라벨 (표시) | 구분 |
|---|---|
| 준비중 · 지원완료 · 서류합격 | 대기중 |
| 1차면접 · 2차면접 · 최종면접 | 진행중 |
| 최종합격 · 불합격 · 지원취소 | 종료 |

사용자에게는 항상 이 한글 라벨만 노출합니다(저장용 영문 키는 노출 금지). 구버전(v1 한글 저장) 항목은 `list`·`stats` 출력에서 스크립트가 자동으로 정규화해 보여주고, 매핑표에 없는 값은 `(구버전 상태)`로 표시됩니다 — 원본 파일은 건드리지 않습니다.

**정리가 필요하면**: 사용자 승인 없이는 재작성하지 않습니다. 먼저 미리보기를 보여주고, 승인 후에만 `--yes`로 재작성을 실행합니다.

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" migrate          # 미리보기만 — 파일 변경 없음
"$_JS_BIN/jobstack-tracker" migrate --yes    # 사용자 승인 후에만 — 원본은 자동 백업됨
```

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

키워드가 없으면 프리앰블이 emit한 `ENTRY_COUNT`·최근 5건 미리보기로 현재 지원 현황 요약을 보여주고(더 자세히 봐야 하면 `jobstack-tracker list`를 대신 호출), AskUserQuestion으로 작업을 선택합니다.

하위 명령 감지가 끝나면 `$_JS_STATE/analytics/skill-usage.jsonl`에 후속 이벤트 1건을 append합니다(`${CLAUDE_SKILL_DIR}/references/telemetry-events.md` 규격) — `event=detected`, `phase`에 감지된 하위 명령명(add/list/update/calendar/stats), no-arg 진입이면 `no_arg=true`:

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
echo '{"skill":"tracker","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'","pid":'$$',"event":"detected","phase":"list","no_arg":false}' \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

진입 이벤트(프리앰블 자동 기록)와 구분되는 `detected` 이벤트가 쌓이면, 트래커를 열고도 아무 명령을 쓰지 않는 이탈 지점을 측정할 수 있습니다.

---

## 정체 감지 (진입 시)

스킬 진입 시(모든 하위 명령 공통, PROACTIVE=true일 때만) 하위 명령 처리 전에 먼저 정체 항목을 확인합니다:

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" nudge --mark
```

- 진행 상태(준비중~최종면접)에서 `updated_at` 기준 7일 이상 정체된 항목만 골라 `📋 [회사명] ... N일째 변화 없음, 결과 업데이트할까요?` 형식으로 출력합니다. 종결 상태(최종합격·불합격·지원취소)는 자동 제외됩니다.
- `--mark`는 방금 출력한 항목의 정체 타이머를 리셋해, 같은 항목이 7일 안에 다시 출력되지 않게 합니다 — **사용자에게 실제로 보여줄 때만** 호출합니다.
- **PROACTIVE=false면 이 호출 자체를 생략합니다**(프리앰블이 emit한 PROACTIVE 값 참조) — 보여주지 않을 항목까지 `--mark`로 갱신하면 이후 정체 감지가 조용히 사라집니다.
- 사용자가 "나중에"를 선택하면 같은 세션 안에서는 다시 호출하지 않습니다.
- `정체 항목 없음`이 출력되면 조용히 다음 하위 명령으로 진행합니다.

---

## add: 새 지원 항목 추가

AskUserQuestion으로 하나씩 정보를 수집합니다:

1. "지원한 기업명을 알려주세요."
2. "지원 직무를 알려주세요. (예: 백엔드 개발자)"
3. "현재 진행 상태를 알려주세요."
   - 선택지: A) 준비중 B) 지원완료 C) 서류합격 D) 1차면접 E) 2차면접 F) 최종면접
4. "서류 마감일이 있으면 알려주세요. (예: 2026-04-15, 없으면 '없음')"
5. "메모할 내용이 있으면 적어주세요. (없으면 '없음')" — **인사담당자 등 제3자의 연락처·이메일은 받지 않습니다(이름·역할까지만).**

해당 회사의 기업분석 캐시(`$_JS_STATE/company-cache/`)가 있으면 company-research Phase 4가 산출한 '종합 적합도' 점수를 `--fit-score`·`--research-ref`로 함께 넘깁니다. 캐시가 없거나 공고 본문 미확보로 점수가 없으면 두 옵션을 생략합니다(추정치 금지).

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" add --company "삼성전자" --position "SW엔지니어" \
  --status 준비중 --deadline 2026-04-15 --notes "자소서 3번 문항 확인 필요"
```

`추가됨: app-001  삼성전자  SW엔지니어  [준비중]`처럼 나오는 확인 메시지를 그대로 보여줍니다. id 채번·저장 형식은 스크립트가 처리합니다.

---

## list: 전체 지원 목록

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" list
```

출력을 그대로 보여줍니다. 진행중·대기중·종료 세 그룹으로 묶고 그룹 안에서는 마감일/업데이트 순으로 정렬하며, 총 5건 이하면 `▸` 축약 표기로 자동 전환됩니다(모바일 가독성). 하단 `통과율:` 줄은 `${CLAUDE_SKILL_DIR}/references/tracker-states.md`의 퍼널 규칙(`max_stage` 기준, withdrawn 분모 제외)을 반영하며, 구버전·폴백 건이 섞여 있으면 정확도 제한 안내가 함께 붙습니다.

```
지원 현황 (총 6건) · 기준일: 2026-04-01 (KST)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✅ 진행중 (2건)
  app-003  카카오      서버개발자   1차면접   D-20
  app-006  당근        백엔드       2차면접   -
⏳ 대기중 (2건)
  app-001  삼성전자    SW엔지니어   지원완료  D-15   적합도 82
  app-004  토스        서버개발     준비중    D-30
❌ 종료 (2건)
  app-002  네이버      백엔드개발   최종합격  -
  app-005  라인        백엔드       불합격    -
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
통과율: 서류 67% → 면접 33%
```

---

## update: 상태 업데이트

1. `jobstack-tracker list`로 현재 진행중인 지원 목록을 보여줍니다.
2. AskUserQuestion: "어떤 지원 건을 업데이트할까요? (ID 또는 기업명)"
3. AskUserQuestion: "새 상태를 선택해주세요."
   - 선택지: A) 지원완료 B) 서류합격 C) 1차면접 D) 2차면접 E) 최종면접 F) 최종합격 G) 불합격 H) 지원취소

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" update "카카오" --status 서류합격
```

`갱신됨: app-003  카카오  1차면접 → 서류합격  (max_stage=interview_1)`처럼 나오는 결과를 그대로 보여줍니다. `max_stage` 갱신 규칙(더 높은 단계면 갱신, 종결 전환 시 직전 진행 단계 보존)과 `updated_at` 기록은 스크립트가 처리합니다.

**모호한 회사명**: 대상이 2건 이상과 부분일치하면 스크립트가 `[오류] "..." 와 부분일치하는 항목이 N건입니다 — id 로 지정하세요: app-001(삼성전자), app-007(삼성SDS)` 형태로 종료 코드 1을 반환합니다 — 이때 AskUserQuestion으로 id를 다시 물어봅니다.

**다음 안내 (PROACTIVE=true일 때)**: 불합격·지원취소·서류합격으로 전환하면 스크립트가 갱신 결과 줄 아래에 `다음 추천: ...` 한 줄(불합격·지원취소 → `/retro`, 서류합격 → `/mock_interview`)을 자체 출력합니다 — 그대로 사용자에게 전달합니다. 방금 본 `list`/`calendar` 출력에 마감 임박(D-7 이내) 항목이 있었다면 "`/cover_letter` 마무리를 도와드릴까요?"를 추가로 제안합니다. **PROACTIVE=false면 스크립트가 낸 추천 줄도 보여주지 않습니다.**

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

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" calendar
```

출력을 그대로 보여줍니다. KST 기준일 계산과 상단 `기준일: YYYY-MM-DD (KST)` 표기, D-day 산출, 마감이 지난 항목을 `⚠️ 마감 경과 — 결과 확인 필요` 그룹으로 분리해 update로 유도하는 것까지 스크립트가 처리합니다. D-7 이내 항목은 출력에서 `⚠️`로 강조됩니다.

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

---

## stats: 지원 통계

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
"$_JS_BIN/jobstack-tracker" stats
```

출력을 그대로 보여줍니다. 상태별 분포, 퍼널 전환율(`${CLAUDE_SKILL_DIR}/references/tracker-states.md`의 `max_stage` 기준·withdrawn 분모 제외 규칙), 평균 진행 기간을 스크립트가 계산합니다. `fit_score` 상·하위 서류합격률 비교는 상·하위 각 그룹에 결과가 확정된 건이 3건 이상일 때만 스크립트가 마지막 줄에 자동으로 덧붙입니다(미만이면 생략 — 소표본 노이즈 방지).

```
지원 통계
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
총 지원:        6건
진행중:         2건
대기중:         2건
최종합격:       1건
불합격:         1건
지원취소:       0건

상태별 분포:
  준비중     ■         1건
  지원완료   ■         1건
  1차면접    ■         1건
  2차면접    ■         1건
  최종합격   ■         1건
  불합격     ■         1건

퍼널 전환율:
  서류 통과율   67% (max_stage ≥ 서류합격)
  면접 통과율   33% (offer / max_stage ≥ 1차면접)

평균 진행 기간: 14일
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

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

작업 완료 시 `${CLAUDE_SKILL_DIR}/references/completion-status.md`의 4종 상태 중 하나를 출력합니다:
- **완료 (DONE)** — 요청 작업 수행 완료
- **우려사항 있는 완료 (DONE_WITH_CONCERNS)** — 완료했으나 사용자가 알아야 할 사항 존재
- **차단됨 (BLOCKED)** — 진행 불가. 차단 요인과 시도한 내용 기술
- **추가 정보 필요 (NEEDS_CONTEXT)** — 계속하기 위한 정보 부족
