---
name: tracker
preamble-tier: 1
version: 0.1.0
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
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/profiles" "$_JS_STATE/tracker" \
         "$_JS_STATE/company-cache" "$_JS_STATE/interview-history" "$_JS_STATE/sessions"
echo "$$" > "$_JS_STATE/sessions/$$"
TRACKER_FILE="$_JS_STATE/tracker/applications.jsonl"
[ -f "$TRACKER_FILE" ] || touch "$TRACKER_FILE"
echo "TRACKER_FILE=$TRACKER_FILE"
ENTRY_COUNT=$(wc -l < "$TRACKER_FILE" | tr -d ' ')
echo "ENTRY_COUNT=$ENTRY_COUNT"
if [ "$ENTRY_COUNT" -gt 0 ]; then
  echo "--- 최근 지원 ---"
  tail -5 "$TRACKER_FILE"
fi
echo "{\"skill\":\"tracker\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

# 지원 현황 관리

사용자의 취업 지원 현황을 추적하고 관리합니다.

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

---

## add: 새 지원 항목 추가

AskUserQuestion으로 하나씩 정보를 수집합니다:

1. "지원한 기업명을 알려주세요."
2. "지원 직무를 알려주세요. (예: 백엔드 개발자)"
3. "현재 진행 상태를 알려주세요."
   - 선택지: A) 준비중 B) 서류전형 C) 서류합격 D) 1차면접 E) 2차면접 F) 최종합격
4. "서류 마감일이 있으면 알려주세요. (예: 2026-04-15, 없으면 '없음')"
5. "메모할 내용이 있으면 적어주세요. (없으면 '없음')"

수집 후 JSONL 형식으로 `~/.jobstack/tracker/applications.jsonl`에 추가:
```json
{"id":"app-001","company":"삼성전자","position":"SW엔지니어","status":"서류전형","applied_at":"2026-03-29","deadline":"2026-04-15","updated_at":"2026-03-29","notes":"자소서 3번 문항 확인 필요"}
```

ID는 `app-XXX` 형식으로 자동 생성 (기존 최대 ID + 1).

---

## list: 전체 지원 목록

`applications.jsonl`을 읽어 테이블로 표시합니다:

```
지원 현황 (총 5건)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ID       기업           직무            상태        마감일
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
app-001  삼성전자       SW엔지니어      서류전형    04-15
app-002  네이버         백엔드개발      서류합격    -
app-003  카카오         서버개발자      1차면접     04-20
app-004  토스           서버개발        준비중      04-30
app-005  라인           백엔드          불합격      -
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

진행중: 3건 | 합격: 0건 | 불합격: 1건 | 준비중: 1건
```

---

## update: 상태 업데이트

1. 현재 진행중인 지원 목록을 보여줍니다.
2. AskUserQuestion: "어떤 지원 건을 업데이트할까요? (ID 또는 기업명)"
3. AskUserQuestion: "새 상태를 선택해주세요."
   - A) 서류합격 B) 1차면접 C) 2차면접 D) 최종합격 E) 불합격
4. JSONL 파일에서 해당 항목의 status와 updated_at을 업데이트합니다.
   - JSONL은 append-only이므로, 전체 파일을 읽어 수정 후 다시 저장합니다.

---

## calendar: 마감일 캘린더

마감일이 있는 지원 건을 날짜순으로 정렬하여 표시합니다:

```
다가오는 마감일
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📅 04-15 (D-17)  삼성전자 SW엔지니어 [서류전형]
📅 04-20 (D-22)  카카오 서버개발자 [1차면접]
📅 04-30 (D-32)  토스 서버개발 [준비중]
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

D-day가 7일 이내인 건은 강조 표시합니다.

---

## stats: 지원 통계

```
지원 통계
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
총 지원:        5건
진행중:         3건 (60%)
최종합격:       0건 (0%)
불합격:         1건 (20%)
준비중:         1건 (20%)

상태별 분포:
  준비중    ■         1건
  서류전형  ■         1건
  서류합격  ■         1건
  1차면접   ■         1건
  불합격    ■         1건

평균 진행 기간: 14일
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

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

- **완료 (DONE)** — 요청한 작업 수행 완료
- **추가 정보 필요 (NEEDS_CONTEXT)** — 필요한 정보 부족
