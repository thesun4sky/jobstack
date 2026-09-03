# 채용공고 수집 실행·폴백 흐름

job-search 스킬 SKILL.md Phase 2 에서 Read 한다.

**플랫폼별 접근 방법 (v0.5.0 — 사람인은 브라우저 없이 동작):**

| 플랫폼 | 방법 | 마감일 포함 | 비고 |
|--------|------|------------|------|
| 원티드 | ✅ fetch-jobs.mjs (detail 전수 검증 내장) | ✅ due_time 실값 | IT/스타트업 특화 |
| 잡코리아 | ✅ Playwright (Tailwind 개편 대응) | ✅ MM/DD 마감일 | 대기업/공기업 공채 |
| 사람인 | ✅ 오픈API 우선 + cheerio 스크래핑 폴백 (Chromium 불필요) | ✅ 날짜 파싱 | is-fetch 어댑터·전역 fetch 경유, `--source=api\|scrape\|auto` |
| 점핏 | ✅ Playwright | ✅ D-N 잔여일 | IT 직군 특화 |

> **진단 로그**: 아래 호출은 `2>/dev/null`로 stderr를 버려도 됩니다. 0건 수집 시
> `fetch-jobs.mjs`가 원인(challenge/empty_result 등)을 preamble에서 export한
> `$JOBSTACK_FETCH_DIAG_LOG`(`$_JS_STATE/analytics/fetch-diag.log`)에 append하므로,
> 어느 사이트가 왜 막히는지는 이 파일에 보존됩니다. 실시간으로 원인을 보려면 `2>/dev/null`을 떼세요.
>
> 플랫폼별 집계·연속 차단 경고는 `"$_JS_BIN/jobstack-fetch-diag" summary --since 7d` (env.sh 소싱 후)로 확인합니다. is-fetch 결과 JSON의 `block_class`(waf_challenge/captcha/access_denied/rate_limited/login_wall)는 차단 원인 설명에 쓰되, 채택 여부는 여전히 `verdict`로 판정합니다.

#### 5단계: WebSearch 보조 (결과 부족 시에만)

위 4개 플랫폼으로 결과가 10개 미만일 때만 사용:

```
site:wanted.co.kr "{직무}" 2026
site:jobkorea.co.kr "{직무}" 채용
```

> ⚠️ WebSearch(구글) 결과는 **이미 마감된 공고가 포함**될 수 있습니다 — 구글 인덱스는 수주~수개월 전
> 스냅샷이라, 2026-07-19 prod 사고에서 이 경로로 유입된 원티드 공고 3건이 전부 마감 상태였습니다.
>
> **하드게이트 (예외 없음):**
> 1. **원티드 링크(`wanted.co.kr/wd/{id}`)**: 출력 전 반드시 `node "$_JS_BROWSER_SCRIPT" verify "<url>"...`로
>    전수 판정 — `active`만 포함, `closed`/`unknown`은 목록에서 제외합니다. 스니펫의 날짜·"상시채용" 문구로
>    판정하지 않습니다.
> 2. **잡코리아·사람인·점핏 링크**: 스니펫에서 마감일/게재일을 확인하고, 본문 마감 문구 필터(위 규칙)를 적용합니다.
> 3. **뉴스 기사·회사 채용페이지 등 비플랫폼 소스**: 마감 판정이 불가하므로 공고로 단정하지 말고
>    "⚠️ 모집 여부 원문 직접 확인 필요" 라벨을 반드시 붙입니다.
> 확인 불가하면 "미확인" 표시 후 사용자에게 원본 URL 확인을 요청합니다.
