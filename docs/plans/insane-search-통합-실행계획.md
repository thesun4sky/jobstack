# insane-search 통합 실행 계획 (spec)

**작성일**: 2026-07-13
**상태**: PoC 검증 완료 · (b) 즉효 패치 적용 완료 · 통합 단계 착수 대기
**근거 문서**: `claudedocs/insane-search-통합검토.md` (초기 검토), 본 문서(실측 반영 확정본)

---

## 0. 한 줄 요약

fetch(수집) 계층만 insane-search 엔진으로 교체하는 **어댑터 통합**이 PoC로 실증됐다. 기존 파서는 0줄 수정으로 재사용된다. company-research·salary부터 fallback 방식으로 붙이는 것을 권장한다.

---

## 1. PoC로 검증된 사실 [사실]

> 실측 환경: Node 25.1.0, Python 3.14.4(venv), curl_cffi 0.15.0. 상세 로그는 검토 리포트 및 scratchpad `AB_results.md`.

### 1-1. 사람인 A/B (백엔드 신입 서울)
| 항목 | 현행(Playwright) | insane-search(curl_cffi)+기존 파서 |
|------|-----------------|-----------------------------------|
| 브라우저 바이너리 | **필수**(미설치 시 실행 실패·0건) | fetch에는 불필요 |
| fetch | context.request.get | curl_cffi safari, 200, 2.44MB, strong_ok, **1회** |
| 파싱 | 10건 | **10건 (파서 코드 0줄 수정)** |
| 마감일 파싱 | 정상 | 정상 |

→ **기존 사람인 파서가 insane-search HTML과 100% 호환.** fetch 계층만 교체하면 됨.

### 1-2. company-research·salary 대상 사이트 (curl-only)
| 사이트 | 결과 |
|--------|------|
| 잡플래닛 검색 | ✅ 194KB, 1회 성공 |
| 원티드 급여 | ✅ 148KB, 1회 성공 |
| 크레딧잡 | ❌ SSL 인증서 오류(curl 60) — 현행 WebFetch도 동일 실패. 브라우저 fallback 영역 |

→ curl_cffi가 다수 사이트를 브라우저 없이 뚫음. 단 **만능은 아님** — 인증서/강한 WAF는 브라우저 에스컬레이션 필요. insane-search는 실패 시 `untried_routes`·`must_invoke_playwright_mcp`로 다음 경로를 명시(R6).

### 1-3. 의존성 실측
- curl_cffi 0.15.0은 Python 3.14 바이너리 휠 존재 → 설치 정상.
- 시스템 pip는 PEP 668(externally-managed)로 차단 → **venv 필수**.

---

## 2. 통합 아키텍처 [추론]

```
[스킬 SKILL.md]
   → [파싱 로직 (jobstack 유지, 변경 없음)]
      → [수집 어댑터]  ──primary──▶ insane-search engine (venv, python -m engine)
                       ──fallback─▶ 기존 Playwright / WebFetch
```

- **경계는 CLI/프로세스 호출** (stdout JSON/HTML). Node ↔ Python 코드 혼합 없음.
- 어댑터 계약: `입력(URL, success_selectors[]) → 출력(raw HTML + verdict + untried_routes)`.
- 파싱·마감일·캐싱·guardrails는 **전부 현행 유지**.

### 어댑터 배치
- `bin/is-fetch.py` (신규, 얇은 래퍼): `python -m engine` 호출 → HTML/진단 JSON stdout.
- venv 경로: `bin/.is-venv/` (install.sh에서 opt-in 생성). 미설치 시 어댑터는 no-op → 현행 경로로 폴백.

---

## 3. 단계별 실행 계획 [추론]

### ✅ Phase 0 — 즉효 패치 (완료)
`bin/fetch-jobs.mjs`에 챌린지 감지·실패 로깅 추가(36줄). 라이브러리 통합과 독립.
- 0건 원인을 `challenge / too_small / empty_result / no_html`로 분류해 `[fetch-jobs:diag]` stderr 로깅.
- 검증: 정상 회귀 없음, 분류 로직 6/6 통과, wanted 0건 e2e에서 `empty_result` 정확 분류.
- **효과**: 어느 사이트가 왜 막히는지 데이터 축적 시작(통합 우선순위의 근거가 됨).

### Phase 1 — company-research·salary fallback 통합 (권장 최우선)
- 대상: 현재 WebFetch 직행 → fallback 없는 가장 취약 지점.
- 작업:
  1. `bin/is-fetch.py` 어댑터 + `install.sh` venv opt-in.
  2. 두 스킬 SKILL.md의 수집 단계에 "WebFetch 실패/차단 시 is-fetch 재시도" 지시 추가.
  3. guardrails "자료 요청" 폴백은 **최종 단계로 유지**(에스컬레이션 후에도 실패할 때).
- 수용 기준: 잡플래닛·원티드급여 등에서 WebFetch 실패 케이스가 is-fetch로 회수되는지 실측.

### Phase 2 — job-search 사람인·잡코리아 fetch 교체
- 작업: `fetch-jobs.mjs`의 사람인 `context.request.get` → 어댑터 경유(실패 시 현행 유지).
- 근거: 사람인 A/B 실증됨. `fetch-jobs.mjs:146` 주석의 TLS 차단 문제를 curl_cffi로 해소.
- 수용 기준: 사람인 수집 건수 ≥ 현행, 파서 출력 스키마 불변.

### Phase 3 — 검증 계층·R7 정찰 (선택)
- Phase 0의 challenge 감지를 원티드 등 SPA에서 R7 API 정찰과 연계(네트워크 요청 → 내부 API 직격).
- 브라우저 fallback이 필요한 사이트(크레딧잡류)는 Playwright MCP 경로 문서화.

---

## 4. 리스크와 완화 [사실/추론]

| 리스크 | 완화 |
|--------|------|
| 언어 이질성(Node↔Python) | CLI 경계로 격리. 코드 혼합 없음 |
| venv·curl_cffi 의존성 | install.sh opt-in. 미설치 시 현행 동작(폴백) |
| 경량 철학 위배(CLAUDE.md) | 코어 아닌 optional 컴포넌트로 |
| 외부 저장소 종속(v0.9.1) | 엔진 vendoring + 버전 고정. 어댑터 인터페이스로 교체 가능 |
| curl 계층 공통 한계(인증서/강WAF) | 브라우저 fallback 유지. insane-search의 untried_routes로 경로 명시 |
| 파싱에 여전히 브라우저 필요 | Phase 2 이후 파서를 cheerio 포팅 시 브라우저 완전 제거 가능(별도 과제) |

---

## 5. 즉시 커밋 가능한 산출물

- **Phase 0 패치** (`bin/fetch-jobs.mjs`, 적용됨·검증됨): 독립적으로 가치 있으므로 우선 커밋 권장.
- 나머지 Phase는 어댑터 PoC → 스킬별 순차 적용.

---

## 6. 비-목표 (YAGNI)

- insane-search 전체(13개 플랫폼 API 라우팅 등) 흡수 ✗
- 사이트별 파서를 insane-search로 이전 ✗ (파서는 jobstack 자산)
- 로그인/페이월 뒤 데이터 수집 ✗ (insane-search도 불가)
