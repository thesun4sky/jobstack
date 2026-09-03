# 잡코리아 채용공고 수집

job-search 스킬 SKILL.md Phase 2 에서 Read 한다.

#### 2단계: 잡코리아 Playwright 브라우저 스크래핑

> 잡코리아는 Tailwind CSS 기반으로 전면 개편되어 단순 curl/WebFetch로는 목록 추출 불가.
> `BROWSER_SCRAPER_AVAILABLE=true`일 때 Playwright를 사용하세요.

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
# career 인수: entry(신입) | experienced(경력) | 생략(전체)
# location 인수: seoul|gyeonggi|busan|incheon|daejeon|daegu|gwangju|remote | 생략(전체)
node "$_JS_BIN/fetch-jobs.mjs" jobkorea "{KEYWORD}" 20 {CAREER} {LOCATION} 2>/dev/null
# 예: node "$_JS_BIN/fetch-jobs.mjs" jobkorea "백엔드" 20 entry seoul 2>/dev/null
# 지역 생략: node "$_JS_BIN/fetch-jobs.mjs" jobkorea "백엔드" 20 entry 2>/dev/null
```

**결과 JSON 필드:**
- `platform`: "jobkorea"
- `company`: 회사명
- `title`: 직무명
- `deadline`: "MM/DD(요일) 마감" / "상시채용" / "채용시마감" / "마감일 미확인"
- `link`: `https://www.jobkorea.co.kr/Recruit/GI_Read/{id}` (쿼리스트링 제거됨)

**마감일 필터링:** deadline에서 날짜("MM/DD") 추출 후 오늘 이전이면 제외. "상시채용"·"채용시마감"은 포함 가능.

`BROWSER_SCRAPER_AVAILABLE=false`일 때는 WebFetch로 대체:
```
https://www.jobkorea.co.kr/Search/?stext={URL인코딩된 키워드}&posted=7&ord=RegDate
```
