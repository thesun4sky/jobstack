# 원티드 채용공고 수집

job-search 스킬 SKILL.md Phase 2 에서 Read 한다.

#### 1단계: 원티드 — fetch-jobs.mjs (detail 전수 검증 내장)

**1차 경로는 스크립트 실행입니다.** 수집된 전 건을 `api/v4/jobs/{id}`로 전수 검증(fail-closed)하고 deadline을 실값(`YYYY-MM-DD 마감` / `상시채용`)으로 채워 반환하므로, 별도 마감 확인이 필요 없습니다:

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
node "$_JS_BROWSER_SCRIPT" wanted "{키워드}" 20 [entry|experienced]
```

- stderr의 `[fetch-jobs:diag] wanted verified=N excluded_closed=M`으로 검증 결과를 확인할 수 있습니다.
- `verify_outage`(검증 실패율이 과반) 시 빈 배열이 반환됩니다 — 원티드 섹션을 생략하고 타 플랫폼 결과로 진행합니다(미검증 공고를 내보내지 않습니다).

**보조 경로 (스크립트 실행 불가 시에만): JSON 목록 API 직접 조회**

직무 카테고리에 맞는 API URL 사용:

```
# 직무 카테고리 ID
# 518 = 백엔드  872 = 프론트엔드  669 = 풀스택
# 655 = DevOps/인프라  660 = 데이터 엔지니어  1 = 전체

# 기본 URL
https://www.wanted.co.kr/api/v4/jobs?tag_type_ids={CATEGORY_ID}&country=kr&job_sort=job.latest_order&limit=20&offset=0

# ⚠️ 지역 필터: 원티드는 지역 필터를 적용하지 않는다(전 지역 반환, 수율 우선).
#    카드에 근무지가 안정적으로 노출되지 않아 후필터 시 결과 0건으로 과도하게 좁아짐(prod 검증).
#    지역 조건은 사람인·잡코리아 결과로 안내하고, 원티드 결과는 전 지역임을 출력에 표시한다.

# 연봉 필터: API에 파라미터 없음 → 응답의 annual_from/annual_to 필드로 수집 후 필터
# annual_from: 최소 연봉(만원), annual_to: 최대 연봉(만원), null이면 미기재
```

**JSON 파싱 규칙:**
- `due_time`: null이면 상시채용 후보, 날짜 문자열이면 마감일
- **due_time이 오늘 이전이면 반드시 제외**
- `status`: `active`가 아니면 제외
- `position.name` = 직무명, `company.name` = 회사명
- `annual_from` / `annual_to`: 연봉 범위 (만원 단위, null이면 미기재)

**⚠️ 훈련 데이터 사용 금지 — ID 범위 검증 필수:**
API 응답에서 얻은 job ID 목록만 사용하세요. API 목록의 최소 ID와 최대 ID를 기록해두고,
포함하려는 모든 공고 ID가 반드시 이 목록 안에 있어야 합니다.
ID가 목록에 없으면 훈련 데이터에서 기억한 것이므로 **즉시 제외**.
(예: 현재 API 목록이 360,092~360,429 범위라면, ID 66113은 목록에 없으므로 절대 포함 금지)

**보조 경로로 얻은 공고는 출력 전 전 건 verify 필수 (상한 없음):**
목록 API의 status는 조회 시점 값일 뿐이므로, 보조 경로로 수집한 공고는 출력 전에
`node "$_JS_BROWSER_SCRIPT" verify "<id>" ["<id>"...]`로 전수 판정하고 `active`만 포함합니다.
(위 "마감 공고 필터링 규칙"의 원티드 생사 판정 규칙과 동일 — HTML WebFetch 판정 금지.)

