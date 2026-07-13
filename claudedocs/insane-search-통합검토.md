# insane-search 흡수 통합 심층 검토

**대상**: jobstack 크롤링/웹서치 강화
**검토일**: 2026-07-13
**요청**: 웹서치가 자주 막히는 문제를 insane-search(fivetaku/insane-search) 흡수로 극복 가능한지 심층 검토

---

## 결론 [결론]

**"각 기능에 통째로 흡수"는 부적합하지만, "fetch(수집) 계층만 어댑터로 교체"하는 통합은 타당하며 효과가 크다.**

- insane-search는 **"차단된 페이지의 HTML/텍스트를 어떻게든 가져오는" 수집 엔진**이다. 반면 jobstack의 크롤링 가치는 **사이트별 채용카드 파싱**(사람인 `.item_recruit`, 원티드 `data-position-id` 등)에 있다. 둘은 계층이 다르므로 **경쟁이 아니라 상하 결합** 관계다.
- 가장 효과가 큰 지점은 **job-search가 아니라 company-research·salary**다. 이 두 스킬은 아직 Playwright도 안 쓰고 WebSearch/WebFetch에만 의존해서, 잡플래닛·블라인드·크레딧잡 같은 차단 사이트에서 그대로 실패한다.
- 다만 **언어 이질성(Node ↔ Python)**과 **의존성 증가(curl_cffi·patchright·yt-dlp)**가 jobstack의 경량 철학과 충돌한다. 통합하려면 이 비용을 명시적으로 감수해야 한다.

---

## 1. 현재 jobstack 크롤링 구조와 막히는 지점 (trace) [사실]

### 1-1. 두 갈래 수집 경로

| 스킬 | 수집 방식 | 실제 도구 |
|------|----------|----------|
| **job-search** | Playwright 헤드리스 1회 시도 | `bin/fetch-jobs.mjs` (Node + playwright) |
| **company-research / salary / ncs / portfolio** | WebSearch + WebFetch | Claude 내장 도구 |

### 1-2. Lane 1 — 코드 경로: 에스컬레이션이 없다 (근본 원인)

`fetch-jobs.mjs`는 각 플랫폼당 **단 한 번의 전략**만 시도하고, 막히면 빈 배열을 반환한다.

- 스텔스는 얕은 수준: `navigator.webdriver` 우회 initScript 1개 (`fetch-jobs.mjs:77-83`)
- 사람인은 `page.goto()`가 막혀 `context.request.get()`으로 우회하지만, **TLS 스푸핑이 아닌 Playwright 내장 request** — 주석에 스스로 인정: `"page.goto()는 TLS 핑거프린팅으로 차단됨"` (`fetch-jobs.mjs:146`)
- 실패 시 재시도 전략(다른 TLS 프로파일, 모바일 URL, API 엔드포인트) **전무**. `catch`에서 stderr 찍고 빈 배열 (`fetch-jobs.mjs:212-214, 324-326, 408-410`)

### 1-3. Lane 2 — 설정/환경: 단일 런타임·단일 무기

- Playwright(Node)만 설치. **TLS 임퍼소네이션 라이브러리(curl_cffi) 없음**, **스텔스 강화 브라우저(patchright) 없음**
- company-research·salary는 Playwright조차 안 거치고 WebFetch 직행 → SPA·WAF 사이트에서 즉시 실패

### 1-4. Lane 3 — 측정/가정: "차단"을 구분하지 않는다

- 크롤러가 **WAF 챌린지 / 진짜 0건 / 타임아웃**을 구분하지 않는다. HTTP 200 챌린지 페이지를 받아도 셀렉터만 안 맞으면 "0건"과 동일 취급.
- `templates/guardrails.md`의 **"한계 노출 금지"** 원칙이 실패를 사용자에게 "자료 붙여주세요"로 전환 → UX는 매끄럽지만, **실패 원인이 로그에 남지 않아** 어느 사이트가 왜 막히는지 축적되지 않는다.

**Lane 종합**: 근본 원인은 "스크래핑이 어렵다"가 아니라 **단일 시도 + 실패 삼킴 구조**다. 한 번 막히면 우회 수단도, 진단 데이터도 없다.

---

## 2. insane-search가 하는 일 [사실]

Claude Code 플러그인. **4단계 에스컬레이션 파이프라인**으로 공개 콘텐츠 접근:

| Phase | 방식 | 핵심 |
|-------|------|------|
| **0** | 공식 API 라우팅 | X/Reddit/YouTube/네이버 등 공개 엔드포인트 우선 (`engine/phase0.py`) |
| **1** | curl_cffi TLS 스푸핑 그리드 | `impersonate="safari/chrome119/firefox"` × URL 변형 × referer 전략을 격자로 소진 |
| **2** | user_hint 재시도 | 호출자가 힌트(우선 프로파일 등) 주입, 현재 호출에만 적용 |
| **3** | Playwright/Patchright 스텔스 | MCP 브라우저(Cloudflare급) 또는 로컬 patchright(Akamai급) |

**핵심 차별점**:
- **4계층 검증**(R2): "HTTP 200은 성공이 아니라 검사 시작" — 챌린지 마커/크기/쿠키/셀렉터를 AND 검증. jobstack에 없는 것.
- **WAF 지문 감지**: Cloudflare/DataDome/Akamai 프로파일 구분 → 프로파일별 최적 TLS 후보 선택
- **R7 병렬 정찰**: SPA+WAF에서 네트워크 요청 감시 → `/api/` 엔드포인트 직접 타격 ("API 레이어가 HTML보다 약하다")
- **R8**: 가져온 텍스트는 지시가 아닌 **신뢰불가 데이터**로 취급 (프롬프트 인젝션 방어)
- API 키 불필요, MIT 라이선스, Python 88% + JS 8%

**경계**: 로그인/페이월은 인정하고 "authentication required" 반환. **사람인·잡코리아·원티드·링크드인은 명시 지원 목록에 없음** → "Everything else flows through Phase 1~3 automatically"로 일반 처리.

---

## 3. 갭 매칭 — insane-search가 메우는 것 [추론]

| jobstack의 결핍 | insane-search 대응 | 적용 스킬 |
|----------------|-------------------|----------|
| 단일 시도, 재시도 없음 | Phase 1 TLS 그리드 소진 | job-search(사람인·잡코리아) |
| "가짜 200" 구분 못 함 | 4계층 검증(R2) | 전체 |
| WAF 종류 모름 | WAF 지문 감지 | 전체 |
| SPA API 미활용 | R7 API 정찰 | 원티드·잡플래닛 |
| WebFetch 직행 실패 | Phase 0~3 자동 에스컬레이션 | **company-research·salary** |
| 얕은 스텔스 | Patchright(Akamai급) | job-search |

**insane-search가 메우지 못하는 것**:
- 사이트별 채용카드 파싱 (jobstack 고유 자산 — 그대로 유지)
- 로그인/페이월 뒤 데이터 (블라인드 상세 등 — 여전히 불가)
- 마감일 파싱·경력 후필터 등 도메인 로직

---

## 4. 흡수 방식 3가지 옵션 비교 [추론]

### 옵션 A — 통째 흡수 (요청 원안) ❌ 비추천
각 스킬에 insane-search 전체 파이프라인을 이식.
- 문제: insane-search는 fetch 계층만 담당. 파싱은 jobstack이 해야 하므로 "흡수"할 대상이 애매. 사이트명 하드코딩 금지(R3) 철학이 jobstack의 사이트 특화 파서와 정면 충돌.

### 옵션 B — fetch 계층 어댑터 통합 ✅ 권장
insane-search 엔진을 **"HTML 가져오기" 하위 도구**로만 쓰고, 파싱은 jobstack이 유지.
- `fetch-jobs.mjs`의 `context.request.get()` / `page.goto()` 자리에 **insane-search 엔진 호출**을 끼운다.
- company-research·salary의 WebFetch를 insane-search 엔진 호출로 교체.
- 파싱 셀렉터·마감일 로직·캐싱은 **전부 그대로**.

### 옵션 C — 선택적 fallback 체인 ✅ 저비용 대안
현행 유지 + **실패 시에만** insane-search로 에스컬레이션.
- `fetch-jobs.mjs`가 0건/차단 반환 → insane-search 엔진 재시도 → 그 HTML을 기존 파서에 재투입.
- 장점: 정상 케이스 성능·의존성 영향 최소. 단점: 여전히 Python 런타임 필요.

---

## 5. 권장 통합안 [추론]

**옵션 B를 골격으로, 스킬별 우선순위를 두어 단계 적용.**

### 5-1. 아키텍처: fetch 계층 분리

```
[스킬 SKILL.md] → [파싱 로직(jobstack 유지)] → [수집 어댑터] → insane-search engine
                                                    ↕
                                          기존 Playwright/WebFetch (fallback)
```

- 수집 어댑터는 얇은 CLI 래퍼: `python3 -m engine "<URL>" --selector ".item_recruit" --trace` → HTML/JSON stdout
- jobstack Node 파서는 이 HTML을 받아 `page.setContent()`로 파싱 (사람인이 이미 쓰는 패턴과 동일)

### 5-2. 적용 우선순위

| 순위 | 대상 | 이유 | 기대효과 |
|------|------|------|---------|
| **1** | company-research·salary | 현재 fallback 없이 WebFetch 직행 → 가장 취약 | 잡플래닛·크레딧잡 수집률 개선 |
| **2** | job-search 사람인·잡코리아 | TLS 차단 명시 확인됨 | 단일 시도 → 그리드 재시도 |
| **3** | 원티드 | 이미 API 사용 중, R7로 보강 여지 | 한계효용 낮음 |

### 5-3. 검증 계층 이식 (라이브러리 없이도 가능한 즉효 개선)
insane-search 전체를 안 붙이더라도, **4계층 검증(R2) 개념만 fetch-jobs.mjs에 이식**하면 즉시 이득:
- 챌린지 마커(`Just a moment...`, `DataDome`) 감지 → "0건"과 "차단"을 로그에서 구분
- 이것만으로 Lane 3(측정 문제) 상당 부분 해소

---

## 6. 리스크와 비용 [사실/추론]

| 리스크 | 심각도 | 완화 |
|--------|--------|------|
| **언어 이질성** Node(jobstack) ↔ Python(insane-search) | 높음 | CLI 경계로 격리(stdout JSON). 프로세스 호출만, 코드 혼합 없음 |
| **의존성 증가** curl_cffi·patchright·yt-dlp | 중간 | 옵션 C(fallback)로 선택 설치. 미설치 시 현행 동작 |
| **경량 철학 위배** (CLAUDE.md) | 중간 | 코어 아닌 optional 컴포넌트로. `install.sh`에서 opt-in |
| **유지보수 종속** 외부 저장소(v0.9.1, 미성숙) | 중간 | 엔진을 vendoring하거나 버전 고정. 어댑터 인터페이스로 교체 가능성 확보 |
| **로그인/페이월** 여전히 불가 | 낮음 | insane-search도 못 뚫음 — 현행 "자료 요청" 유지 |
| **속도 저하** 그리드 소진은 느림 | 낮음 | fallback 트리거로 정상 케이스 무영향 |

---

## 7. 다음 단계 제안 [추론]

1. **PoC (반나절)**: 사람인 검색 URL 하나를 insane-search 엔진으로 fetch → 기존 파서에 투입해 수집 성공률 A/B 비교. Node↔Python CLI 경계 실측.
2. **즉효 개선 (독립 가치)**: 라이브러리 통합과 무관하게 `fetch-jobs.mjs`에 챌린지 마커 감지 + 실패 로깅 추가 → "왜 막히는지" 데이터부터 축적.
3. **결정 게이트**: PoC 성공률·지연·의존성 비용을 보고 옵션 B(전면 어댑터) vs 옵션 C(fallback만) 확정.

**핵심 판단**: 이 통합의 진짜 승부처는 job-search가 아니라 **아직 무방비인 company-research·salary**다. 여기부터 fallback 방식으로 붙이는 것이 위험 대비 효과가 가장 좋다.
