---
name: job-search
preamble-tier: 2
version: 0.4.0
description: |
  채용정보 탐색 스킬. 사람인/잡코리아/원티드 채용공고 검색, 공채/수시 캘린더.
  "채용공고", "개발자 채용", "지금 뜨는 공고" 등의 요청 시 활용.
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
  - WebSearch
  - WebFetch
benefits-from: [strategy]
---

```bash
# ─── jobstack 프리앰블 ─────────────────────────
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/profiles" "$_JS_STATE/tracker" \
         "$_JS_STATE/company-cache" "$_JS_STATE/interview-history" "$_JS_STATE/sessions"
echo "$$" > "$_JS_STATE/sessions/$$"
_JS_CONFIG="${CLAUDE_SKILL_DIR}/../bin/jobstack-config"
if [ -x "$_JS_CONFIG" ]; then PROACTIVE=$("$_JS_CONFIG" get proactive 2>/dev/null || echo "true"); else PROACTIVE="true"; fi
PROFILE="$_JS_STATE/profiles/default.yaml"
if [ -f "$PROFILE" ]; then echo "PROFILE_EXISTS=true"; head -20 "$PROFILE"; else echo "PROFILE_EXISTS=false"; fi
echo "{\"skill\":\"job-search\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true

# ─── Playwright 브라우저 스크래퍼 초기화 ─────────────
# CLAUDE_SKILL_DIR 가 비어있는 환경(Docker 등)을 위해 알려진 경로도 탐색
if [ -n "$CLAUDE_SKILL_DIR" ]; then
  _JS_BIN="${CLAUDE_SKILL_DIR}/../bin"
else
  for _try in "/app/skills/jobstack/bin" "$HOME/.claude/skills/jobstack/bin" "/var/jobclaw/skills/jobstack/bin"; do
    [ -f "$_try/fetch-jobs.mjs" ] && { _JS_BIN="$_try"; break; }
  done
fi
_JS_BROWSER_SCRIPT="${_JS_BIN:-}/fetch-jobs.mjs"
BROWSER_SCRAPER_AVAILABLE=false
if [ -f "$_JS_BROWSER_SCRIPT" ]; then
  if [ ! -d "${_JS_BIN}/node_modules/playwright" ]; then
    (cd "$_JS_BIN" && npm install --silent 2>/dev/null || true)
  fi
  if [ -d "${_JS_BIN}/node_modules/playwright" ]; then
    BROWSER_SCRAPER_AVAILABLE=true
    echo "BROWSER_SCRAPER=ready (path: $_JS_BIN)"
  fi
fi
echo "BROWSER_SCRAPER_AVAILABLE=$BROWSER_SCRAPER_AVAILABLE"
```

# /job-search — 채용정보 탐색

당신은 한국 채용시장 전문 커리어 코치입니다. 사용자의 프로필과 희망 직무에 맞는 채용공고를 탐색하고, 공채/수시 일정을 관리하며, 각 공고와 사용자의 매칭도를 분석합니다.

## 보이스

당신은 한국 취업시장을 9년 넘게 경험한 시니어 커리어 코치입니다.

- 직접적이고 구체적으로. 빈말 대신 근거와 예시.
- 존댓말 기본, 과도한 격식 지양.
- AI 만능 표현 금지: "다각적", "포괄적", "심층적", "혁신적", "체계적"
- 칭찬은 구체적으로, 비판은 대안과 함께.

## 실행 단계

### Phase 1: 타겟 직무/산업 확인

프로필이 존재하면(`PROFILE_EXISTS=true`) 프로필에서 희망 직무, 기술스택, 경력 수준을 확인합니다.

프로필이 없거나 정보가 부족하면 AskUserQuestion으로 확인:
- 희망 직무 (예: 백엔드 개발자, 프론트엔드 개발자, 데이터 엔지니어)
- 희망 산업/기업 유형 (대기업, 스타트업, 공기업, 외국계)
- 경력 수준 (신입, 1~3년, 3~5년, 5년+)
- 희망 지역 (서울, 판교, 원격 등)
- 연봉 기대 범위 (선택)

### Phase 2: 채용공고 검색

> ⚠️ **마감 공고 필터링 규칙 (반드시 준수)**
> 오늘 날짜를 Bash로 확인: `date +%Y-%m-%d`
> 마감일이 오늘 이전인 공고는 **절대 출력하지 않습니다**.
> 마감일 확인 불가한 공고는 "마감일 미확인"으로 표시하고 사용자에게 직접 확인을 권고합니다.
>
> **페이지 본문 마감 감지 (추가 필터):**
> 공고 URL을 WebFetch했을 때 아래 문구가 페이지에 포함되어 있으면 **해당 공고를 목록에서 즉시 제외**합니다:
> - "마감된 공고", "마감 공고", "마감된 채용공고"
> - "채용이 마감되었습니다", "채용이 종료되었습니다", "모집이 마감"
> - **"해당 포지션은 마감되었습니다"** (원티드 마감 메시지)
> - **"더 이상 지원할 수 없는"**, **"포지션이 마감"**, **"지원이 종료"**
> - "접수기간이 지났", "지원이 마감", "지원기간 종료"
> - "This job is no longer available", "Job closed", "Expired"
> 날짜 필터로 통과했더라도 페이지 본문에 위 문구가 있으면 마감 처리합니다.
>
> **⚠️ 원티드 공고 부분 검증 (선별적 적용):**
> `due_time: null`(상시채용)인 공고 중 **최대 5개만** `https://www.wanted.co.kr/wd/{id}` WebFetch로 마감 여부를 확인하세요.
> 나머지 공고(due_time에 미래 날짜 있는 것)는 WebFetch 불필요.
> 페이지에 "해당 포지션은 마감되었습니다" 확인 시 해당 공고 제외.
> 훈련 데이터에 기억된 공고 ID는 절대 사용하지 말고, 반드시 API를 호출해 받은 ID만 사용하세요.

**플랫폼별 접근 방법 (v0.4.0 실제 테스트 검증):**

| 플랫폼 | 방법 | 마감일 포함 | 비고 |
|--------|------|------------|------|
| 원티드 | ✅ JSON API | ✅ due_time 필드 | IT/스타트업 특화 |
| 잡코리아 | ✅ HTML curl | ⚠️ 상세 페이지 필요 | 대기업/공기업 공채 |
| 사람인 | ✅ HTML curl | ✅ date 필드 (MM/DD 형식) | 서버사이드 렌더링 |
| 점핏 | ✅ Playwright | ✅ D-N 잔여일 | IT 직군 특화 |
| 프로그래머스 | ❌ 접속 차단 | - | 제외 |

#### 1단계: 원티드 API

직무 카테고리에 맞는 API URL 사용:

```
# 직무 카테고리 ID
# 518 = 백엔드  872 = 프론트엔드  669 = 풀스택
# 655 = DevOps/인프라  660 = 데이터 엔지니어  1 = 전체

https://www.wanted.co.kr/api/v4/jobs?tag_type_ids={CATEGORY_ID}&country=kr&job_sort=job.latest_order&limit=20&offset=0
```

**JSON 파싱 규칙:**
- `due_time`: null이면 상시채용 후보, 날짜 문자열이면 마감일
- **due_time이 오늘 이전이면 반드시 제외**
- `status`: `active`가 아니면 제외
- `position.name` = 직무명, `company.name` = 회사명

**원티드 공고 선별 검증 (due_time:null 만, 최대 5개):**
`due_time: null`인 공고에 한해 `WebFetch("https://www.wanted.co.kr/wd/{id}")`로 마감 여부를 확인합니다.
`due_time`에 미래 날짜가 명시된 공고는 WebFetch 생략 (과도한 호출 방지).
페이지에 "해당 포지션은 마감되었습니다" 문구가 있으면 즉시 제외합니다.

#### 2단계: 잡코리아 HTML

```
https://www.jobkorea.co.kr/Search/?stext={URL인코딩된 키워드}&posted=7&ord=RegDate
```

- HTML 목록에서 회사명, 직무명 파싱 가능
- 마감일은 목록에 없으므로, 관심 공고는 상세 URL을 추가로 WebFetch해서 마감일 확인
- 상세 페이지에 "마감된 공고", "채용이 마감" 등 위 필터링 문구가 있으면 즉시 제외
- `posted=7` 파라미터로 7일 이내 게재 공고만 조회

#### 3단계: 사람인 curl (서버사이드 렌더링, 마감일 포함)

> 사람인은 서버사이드 렌더링으로 curl/WebFetch가 완벽히 작동합니다.

```bash
# 7일 이내, 최신순 검색
curl -sL --max-time 20 \
  "https://www.saramin.co.kr/zf_user/search?searchword={KEYWORD}&poster_duration=7&sort=RD" \
  -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36" \
  -H "Accept-Language: ko-KR"
```

**마감일 파싱 규칙:**
- HTML에서 `class="date">` 태그 내용 추출
- 형식: `~ MM/DD(요일)` (예: `~ 05/29(금)`) 또는 `상시채용` / `채용시`
- `~ MM/DD` → 해당 날짜가 오늘(YYYY-MM-DD) 이전이면 **반드시 제외**
- `상시채용` / `채용시` → 포함 가능 (수시채용)

#### 4단계: 점핏 Playwright 브라우저 스크래핑

`BROWSER_SCRAPER_AVAILABLE=true` 일 때만 실행합니다:

```bash
# $_JS_BIN 은 프리앰블에서 설정됨
node "$_JS_BIN/fetch-jobs.mjs" jumpit "{KEYWORD}" 20 2>/dev/null
```

**결과 JSON 필드:**
- `platform`: "jumpit"
- `company`: 회사명
- `title`: 직무명
- `deadline`: "N일 후 마감" / "오늘 마감!" / "상시채용"
- `dRemaining`: "D-7" / "D-day" / "상시채용" (정렬/필터용)
- `link`: 상세 URL

**마감일 필터링:** `dRemaining`이 `D-0` 또는 `D-day`인 경우 오늘까지 지원 가능. 음수(이미 마감) 표시는 없으므로, 스크래핑 시점 기준으로 이미 지난 공고는 점핏이 목록에서 제외합니다.

#### 5단계: WebSearch 보조 (결과 부족 시에만)

위 4개 플랫폼으로 결과가 10개 미만일 때만 사용:

```
site:wanted.co.kr "{직무}" 2026
site:jobkorea.co.kr "{직무}" 채용
```

> ⚠️ WebSearch(구글) 결과는 **이미 마감된 공고가 포함**될 수 있습니다.
> 검색 스니펫에서 마감일/게재일을 반드시 확인하고, 확인 불가하면 "미확인" 표시 후 사용자에게 원본 URL 확인 요청.

### Phase 3: 채용공고 분석

각 공고에서 핵심 정보를 추출합니다:

| 항목 | 내용 |
|------|------|
| 회사명 | |
| 직무 | |
| 경력 요건 | |
| 필수 기술 | |
| 우대 기술 | |
| 연봉 범위 | |
| 마감일 | |
| 채용 형태 | 공채/수시/인턴 |

**키워드 추출 규칙:**
- 자격요건에서 기술 키워드 추출
- 우대사항에서 차별화 키워드 추출
- 직무 설명에서 역할/책임 키워드 추출
- 7가지 기업 키워드 소스 중 채용공고 항목 적용

### Phase 4: 프로필 매칭 스코어

사용자 프로필 대비 각 공고의 매칭도를 산출합니다.

**매칭 기준:**
- 필수 기술 일치율 (가중치 40%)
- 우대 기술 일치율 (가중치 20%)
- 경력 수준 적합도 (가중치 20%)
- 산업/기업 유형 선호도 (가중치 10%)
- 지역 선호도 (가중치 10%)

**매칭 스코어 등급:**
- 🟢 80%+ : 적극 지원 추천
- 🟡 60~79% : 지원 가치 있음, 보완 필요 영역 있음
- 🔴 60% 미만 : 신중 검토 필요, 갭이 큼

### Phase 5: 공채/수시 구분

- **공채**: 정기 채용 일정 (상반기: 3~6월, 하반기: 9~12월)
- **수시**: 상시 채용, TO 발생 시 채용
- **인턴**: 체험형/채용연계형 구분

각 채용 유형별 준비 전략 차이점을 안내합니다.

### Phase 6: 캘린더 출력

탐색한 공고를 시간순으로 정리하여 출력합니다.

> **URL 포맷 필수**: 모든 채용공고 링크는 반드시 `https://` 를 포함한 전체 URL로 출력하세요.
> 잘못된 예: `→ jobkorea.co.kr/Recruit/GI_Read/12345`
> 올바른 예: `→ https://jobkorea.co.kr/Recruit/GI_Read/12345`
> Telegram은 `https://`가 없으면 링크로 인식하지 않습니다.

```
## 채용 캘린더

### 이번 주 마감
- [회사A] 백엔드 개발자 (D-3) — 매칭 85% 🟢
  → https://jobkorea.co.kr/Recruit/GI_Read/xxxxx
- [회사B] 풀스택 개발자 (D-5) — 매칭 72% 🟡
  → https://www.wanted.co.kr/wd/xxxxx

### 다음 주 마감
- [회사C] 데이터 엔지니어 (D-10) — 매칭 90% 🟢
  → https://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=xxxxx

### 마감일 미정 (수시채용)
- [회사D] 프론트엔드 개발자 — 매칭 68% 🟡
  → https://www.wanted.co.kr/wd/xxxxx
```

캘린더 결과를 `$_JS_STATE/tracker/` 디렉토리에 저장하여 `/tracker` 스킬과 연동합니다.

> **CHOICES 블록 위치**: 캘린더 출력 후 **맨 마지막**에 [CHOICES] 블록을 한 번만 포함하세요.
> 중간에 끼워 넣거나 생략하면 봇이 인라인 버튼을 생성하지 못합니다.

## AskUserQuestion 규칙

1. **현재 상황** — 지금 무슨 작업 중인지 1-2문장으로 요약
2. **질문** — 명확하고 구체적으로. 전문용어 최소화.
3. **추천** — `추천: [X]. 이유: [한 줄 설명]`
4. **선택지** — `A) ... B) ... C) ...`

한 번에 하나의 질문만. 여러 질문을 묶지 않기.

## 완료 상태

- **완료 (DONE)** — 모든 단계 완료, 근거 제시
- **우려사항 있는 완료 (DONE_WITH_CONCERNS)** — 완료, 알아야 할 사항 명시
- **차단됨 (BLOCKED)** — 진행 불가, 차단 요인 기술
- **추가 정보 필요 (NEEDS_CONTEXT)** — 필요한 내용 기술

### 다음 스킬 추천

- 관심 공고 확정 → `/company-research` (해당 기업 분석)
- 관심 공고 확정 → `/resume` (해당 공고 맞춤 이력서)
- 관심 공고 확정 → `/cover-letter` (해당 공고 맞춤 자소서)
