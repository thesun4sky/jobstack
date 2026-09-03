# 사람인 채용공고 수집

job-search 스킬 SKILL.md Phase 2 에서 Read 한다.

#### 3단계: 사람인 수집 — 오픈API 우선, 브라우저 없는 스크래핑 폴백

> 사람인은 Chromium을 쓰지 않습니다(`BROWSER_SCRAPER_AVAILABLE`와 무관하게 항상 실행 가능). `--source=auto`(기본)는
> `jobstack-config get saramin_api_key`에 키가 있으면 사람인 오픈API를 먼저 쓰고, 없거나 0건이면 is-fetch 어댑터 → 전역 fetch 로
> HTML을 받아 cheerio 로 파싱합니다. 키 등록: `"$_JS_BIN/jobstack-config" set saramin_api_key <키>` (일 500회 한도, 승인제).
> 오픈API 필드 계약은 공식 문서로 미검증이므로 `--source=api` 단독 사용은 권하지 않고 `auto`를 유지합니다.

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
# career 인수: entry(신입) | experienced(경력) | 생략(전체)
# location 인수: seoul|gyeonggi|busan|... | 생략(전체)
node "$_JS_BIN/fetch-jobs.mjs" saramin "{KEYWORD}" 20 {CAREER} {LOCATION} 2>/dev/null
# 예: node "$_JS_BIN/fetch-jobs.mjs" saramin "백엔드" 20 entry seoul 2>/dev/null
# 소스 강제: --source=api | --source=scrape (기본 auto). stderr 의 [fetch-jobs:diag] saramin fetch_via=api|is-fetch|fetch 로 경로 확인
```

결과 JSON: `platform:"saramin"`, `company`, `title`, `deadline`(YYYY-MM-DD 또는 "상시채용"/"채용시마감"), `link`

> **사람인 단축 URL 처리 (#118d)**: 사용자가 `saram.in/s/<코드>` 같은 **단축 URL**을 붙여넣으면, 수동 복붙을 요구하기 전에 WebFetch 로 리다이렉트를 따라가 원 공고(`saramin.co.kr/.../view?rec_idx=...`)의 본문(직무·자격·마감일)을 확보하세요. WebFetch 가 막히면 원 URL 로 한 번 더 시도하고, 그래도 실패할 때만 사용자에게 공고 본문 복붙을 요청합니다.

**마감일 필터링:** `deadline` 필드가 YYYY-MM-DD 형식이면 오늘 이전인 경우 제외.
- `상시채용` / `채용시마감` → 포함 가능 (수시채용)
- 스크래핑 실패(봇 감지·차단) 시 빈 배열 반환 → 점핏으로 대체 수집. 차단 원인은 `"$_JS_BIN/jobstack-fetch-diag" summary` 로 확인

