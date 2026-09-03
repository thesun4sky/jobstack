# 점핏 채용공고 수집

job-search 스킬 SKILL.md Phase 2 에서 Read 한다.

#### 4단계: 점핏 Playwright 브라우저 스크래핑

`BROWSER_SCRAPER_AVAILABLE=true` 일 때만 실행합니다:

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
# career 인수: entry|experienced|생략(전체)
# location 인수: seoul|gyeonggi|... | 생략(전체)
node "$_JS_BIN/fetch-jobs.mjs" jumpit "{KEYWORD}" 20 {CAREER} {LOCATION} 2>/dev/null
# 예: node "$_JS_BIN/fetch-jobs.mjs" jumpit "백엔드" 20 "" seoul 2>/dev/null
```

**결과 JSON 필드:**
- `platform`: "jumpit"
- `company`: 회사명
- `title`: 직무명
- `deadline`: "N일 후 마감" / "오늘 마감!" / "상시채용"
- `dRemaining`: "D-7" / "D-day" / "상시채용" (정렬/필터용)
- `link`: 상세 URL

**마감일 필터링:** `dRemaining`이 `D-0` 또는 `D-day`인 경우 오늘까지 지원 가능. 음수(이미 마감) 표시는 없으므로, 스크래핑 시점 기준으로 이미 지난 공고는 점핏이 목록에서 제외합니다.

