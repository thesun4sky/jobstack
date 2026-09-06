# STAR-R 도입 계획 — 경험 카드에 '입사 후 적용' 을 잇는다

- **작성일**: 2026-09-06 · **기준 커밋**: `main @ 75ed5a6` (PR #17 v1.0.0 머지 직후) · **대상 버전**: 1.1.0
- **근거 문서**: `templates/experience-methods.md`(경험 전환 6단계), `docs/experience-card-schema.md`(카드 계약), `ETHOS.md` 원칙 1·5·8, `docs/plans/version-upgrade-review-2026-09.md` U-21(`ai_usage` 신설 선례)
- **표기**: `[사실]` 코드·문서로 확인 · `[2차]` 원문 접근 불가, 검색 요약 기준 · **S** 30분 내 · **M** 1~2시간 · **L** 반나절 이상
- **상태**: 계획 확정(오너 결정 4건 반영) → 구현 진행. 실행 로그는 §8 에 구현 후 기록한다.

---

## 0. 결이요 요약

**결(론)** — 저장소에는 STAR-R 이 없다. 경험 정리는 6단계 카드가, STAR 는 문서 서술 구조가 맡고 있으며 둘 사이를 잇는 "이 경험을 그 회사에서 어떻게 쓸 것인가" 가 비어 있다. STAR-R 의 마지막 R 을 **입사 후 적용**으로 정의해 카드에 근거와 함께 저장하고, 자소서 '요'·포부·면접 답변이 같은 문장을 재사용하게 한다.

**이(유)** — `[사실]` ① `STAR-R`·`STARR`·`성찰`·`reflection` 은 저장소 전체에서 0건이고, STAR 는 resume Phase 5·cover-letter 구조 가이드·ncs Phase 5·mock-interview 인성 모드에서 구조로만 쓰인다. ② "많은 것을 배웠습니다" 류 감상은 experience-methods §2, cover-letter 배운 점 규칙, retro 작성 규칙, ETHOS 원칙 1·5 가 모두 금지한다 — 일반 STARR 의 '성찰' 을 그대로 들이면 네 규칙과 충돌한다. ③ 결이요의 '요(청)' 와 cover-letter 구조 가이드의 '요' 불릿("이 기업에서 구체적으로 기여할 비전")은 매번 즉석에서 쓰여 카드에 남지 않고, 기업분석 캐시의 키워드·화두와 연결되지 않는다.

**요(청)** — 방법론 §7 신설, 카드 필드 `apply_plans`(선택) 과 스크립트 `apply` 명령, experience-bank·company-research 가 근거와 함께 저장, 문서·면접 스킬이 소비. 8개 항목(SR-01~SR-08)을 커밋 5개로 구현하고 3관점 리뷰와 헤드리스 스모크로 검증한다.

---

## 1. 현황 `[사실]`

| 항목 | 현재 |
|---|---|
| 경험 정리 방법론 | `templates/experience-methods.md` §1 경험 전환 6단계(이름·문제·역할·바꾼 행동·검증 가능한 변화·직무 연결), §2 4분리, §3 수치 폴백, §4 추상어 전환, §5 약한 문장, §6 어조 전환. 8개 스킬 `references/` 에 동일 복제(`bin/gen-skill-docs.sh`, 드리프트는 `test/test-skill-refs.sh` 가 차단) |
| 카드 계약 | `docs/experience-card-schema.md`: `id·title·problem·role·action·change`(필수), `numbers`, `job_link_tags`, `ai_usage{tool,task,effect}|null`, `created_at`. `bin/jobstack-exp.mjs add/list/show/update/validate` 가 유일한 쓰기 경로 |
| STAR 사용처 | resume Phase 5(S·T·A·R 정의, `references/star-quantify.md`), cover-letter `structure-guide.md:29`(직무역량 '이'), ncs Phase 5("STAR의 한계" 경고), mock-interview `modes/personality.md`("STAR 기법 활용 여부") |
| 감상 금지 규칙 | experience-methods §2 "많은 것을 배웠습니다 = 결과 없음", cover-letter `review-steps.md` 배운 점 규칙(행동 변화로 전환), retro Phase 4("느꼈다/배웠다 금지, 다음 지원에서 달라질 행동 한 문장"), ETHOS 원칙 1("배우고 싶다" 대신 "기여할 수 있다")·5 |
| 기업분석 산출물 | company-research Phase 5 가 `$_JS_STATE/company-cache/{회사}-{날짜}.md` 를 쓰고 상단에 요약 블록(`정규화키·회사명·직무·핵심 키워드·'이미 팀원처럼' 화두·적합도 종합`)을 둔다. 카드와의 연결은 없다 |
| 카드 소비자 | resume·cover-letter·mock-interview·ncs(스키마 문서 기재) + career-history·scout-profile(직접 Read, 문서 미기재) |

외부 정의 `[2차]`: STARR = Situation·Task·Action·Result·**Reflection**(무엇을 배웠고 다음엔 무엇을 바꿀지 — 인턴 회고·코칭·면접에서 사용), 국내 취업 코칭은 STAR-L(Learn, 배운 점)을 쓴다. 이 저장소의 R 은 오너 결정으로 **입사 후 적용**이며 §7 본문에 그 차이를 명시한다.

---

## 2. 결정 사항 (오너 확정 4건 + 설계 결정 7건)

오너 결정: ① R = "기업분석과 연결지어서 입사 후 어떻게 적용할 것인지" ② 적용 범위 표준(방법론·카드·experience-bank·문서 스킬 4종·mock-interview + 근거 생산자 company-research) ③ 카드 필드는 선택(6단계 게이트 유지) ④ 계획서를 저장소에 남긴다.

| # | 결정 | 근거 |
|---|---|---|
| D1 | 필드 이름 `apply_plans`(object[], 선택). `applications` 는 tracker 의 `applications.jsonl` 과 혼동되므로 피한다 | 의미 충돌 방지 |
| D2 | 항목 `{company, position?, plan, basis, source, created_at}`. 회사당 1건, upsert 는 정규화 회사명(공백·하이픈 제거·소문자) **등치**, `list --company` 는 **부분일치** | `jobstack-defense-map.mjs` 의 회사 느슨 매칭과 같은 규칙, 캐시 요약 블록 `정규화키` 와 호환 |
| D3 | `add` 는 `apply_plans` 를 쓰지 않는다(부재 == `[]`). 새 명령 `apply` 만 쓰고 `--basis`·`--source` 가 비면 거부 | 기존 카드 호환, "근거 없는 R 은 저장되지 않는다" 를 코드로 보장 |
| D4 | `list` 표 열 순서 `수치 AI 적용 직무 태그`, 푸터는 `카드 N장 · 수치 보강 필요 M장 · 입사 후 적용 K장` 으로 뒤에 덧붙임 | 기존 테스트 단언(`X +O` 정규식·부분 문자열) 유지 |
| D5 | R 문장은 자소서 '요'·포부·면접 답변용. 이력서 본문에는 쓰지 않고(resume 는 S·T·A·R 까지), career-history 는 일치 카드를 배치 우선순위로만 쓴다 | 문서 역할 분리(three-docs-guide), ETHOS 원칙 8 |
| D6 | `apply_plans` 쓰기 주체는 experience-bank(Phase 3 하위 절)와 company-research(Phase 5.5). 다른 스킬은 읽기만 | 근거가 있는 곳에서만 R 을 만든다 |
| D7 | 항목 삭제(`--remove`)는 범위 밖(§7 후속). 교체 시 `created_at` 은 새 값 | 계약 단순화 |

---

## 3. 항목

### SR-01 · experience-methods §7 "STAR-R 서술 프레임 (R = 입사 후 적용)"  `[P1/S]`
**소비 스킬**: experience-bank, company-research, cover-letter, resume, ncs, career-history, mock-interview

§6 뒤에 §7 을 덧붙인다(§1~§6 번호 유지 — 스킬이 §N 으로 인용). 내용: 적용 시점(자소서 '요'·입사 후 포부·기업 맞춤 서류·면접 "입사하면 어떻게 기여" 답변, 이력서 본문 제외) / 매핑 표(S=`problem`, T=`problem`+`role`, A=`action`, R=`change`+`numbers`, R=`apply_plans[].plan`+`basis`·`source`) / 일반 STARR·STAR-L 과 의도적으로 다르다는 문단(감상은 §2 대로 행동 변화로) / **R 작성 규칙 4가지** — ① 근거 1개 이상: 기업분석 캐시의 키워드 체크리스트·'이미 팀원처럼' 화두·공고 문구를 `basis` 에 원문 인용, 출처 파일명·기준일을 `source` 에, 근거 없으면 쓰지 않고 `/company_research` 안내 ② 형식 한 문장 "[기업의 과제·키워드]에 [카드의 행동·변화]를 적용해 [기대 변화]", §6 희망→실행 어조, 새 수치 창작 금지 ③ 회사명 치환 테스트(humanize-check §1 ①) ④ 감상형 마무리는 먼저 행동 변화로 고친 뒤에만 R 을 잇는다 / 근거 확보 질문 2개(각 1회) / Before→After 2행. 작성 후 `bin/gen-skill-docs.sh` 로 복제본 재생성.

**완료 판정:**
- §7 이 존재하고 매핑 표·규칙 4가지·질문 2개·예시 2행이 있다
- 9개 `references/experience-methods.md`(company-research 신규 포함)가 원본과 동일 — `test/test-skill-refs.sh` 통과
- 금지어 0건(`test/lint-conventions.sh`), 명령 표기 언더스코어(`test/test-command-style.sh`)

### SR-02 · 카드 필드 `apply_plans` + `jobstack-exp apply / list --company / validate`  `[P1/M]`
**소비 스킬**: experience-bank, company-research (쓰기) · 전 소비자 (읽기)

스키마 문서: 필드 표에 `apply_plans`·`.company`·`.position`·`.plan`·`.basis`·`.source`·`.created_at` 행, `## apply_plans 신설 사유 (STAR-R)` 절, 명령 요약표에 `apply`·`list [--company C]`, 소비자 목록에 career-history·scout-profile 추가 + 쓰기 경계 문장. 스크립트: `APPLY_REQUIRED=['company','plan','basis','source']`, `normCompany`, `cmdApply`(Document API 로 카드 맵을 찾아 `apply_plans` 시퀀스에 회사 등치 항목을 교체하거나 추가, `withLock`·원자적 쓰기·주석 보존, 출력 `적용 저장됨: <id> · <회사> (교체|신규)`), `cmdList` 의 `--company` 필터·`적용` 열·푸터 K장·`--json` 의 `apply_plans_count`/`company_filter`/`matched_apply_plan`, `cmdValidate` 의 배열·항목 객체·필수 문자열·`created_at`·회사 중복 검사. `add`·`update` 는 그대로(D3).

**완료 판정:**
- 기존 카드(필드 없음)에 `apply` → 필드가 신설되고 파일 주석이 보존된다; 같은 회사 재-apply 는 교체, 다른 회사는 추가
- `--basis`·`--source` 누락·공백 → exit 1, 파일 미변경
- `validate` 가 `basis` 공백·회사 중복·`created_at` 형식 오류를 `[FAIL]` 로 낸다
- `test/test-exp.sh` 기존 단언 전부 유지 + 신규 단언 통과, `bin/gen-skill-docs.sh --check` 통과

### SR-03 · experience-bank 흐름 — 입사 후 적용 절·`apply` 저장·요약 열  `[P1/S]` · 의존: SR-01, SR-02
Phase 3 의 "AI 활용 근거 수집" 뒤에 `### 입사 후 적용 — STAR-R 의 R (기업분석 캐시가 있을 때만)` 절: 캐시 목록 확인(없으면 절 생략·`/company_research` 안내) → 1회 질문으로 연결 기업 선택 → 최신 캐시의 요약 블록만 읽기 → §7 규칙으로 R 한 문장 초안(basis 는 요약 블록 원문, source 는 캐시 파일명) → 사용자 확인 후 Phase 4 `apply`. Phase 4 에 `apply` 펜스, Phase 0 모드 B·라우팅 문구, Phase 5 열·푸터 설명, `when_to_use`·저장소 구분·다음 추천 갱신, `metadata.version` 0.2.0.

**완료 판정:**
- 절이 존재하고 "근거 없으면 쓰지 않는다·회사명 치환 실패 시 재작성" 가드레일이 있다
- `experiences.yaml` 직접 편집 지시 없음(`test/test-script-layer.sh`), 300줄 이하, bare `docs/` 참조 없음
- 헤드리스 gate 케이스(SR-07)가 `apply` 호출·`references/experience-methods.md` Read 를 통과

### SR-04 · company-research Phase 5.5 "경험 카드 연결"  `[P1/S]` · 의존: SR-01, SR-02
Phase 5 뒤에 선택 절: `EXPERIENCES_EXISTS=true` 일 때 `list --json` 으로 카드 목록을 읽고 키워드 체크리스트 O 항목·'이미 팀원처럼' 화두와 닿는 카드 3장 이하를 골라 §7 규칙으로 R 한 문장씩 초안(basis = 방금 만든 체크리스트·화두 원문, source = 캐시 파일명) → 1회 질문으로 저장 확인 → 카드마다 `apply`. 리포트 §5 에 "경험 카드 적용 문장" 줄. `benefits-from` 에 experience-bank 추가. 봇 마커는 본문에 두지 않는다.

**완료 판정:**
- 절이 존재하고 `${CLAUDE_SKILL_DIR}/references/experience-methods.md` 를 참조한다(복제본 생성)
- `report-template.md` §5 에 카드 적용 문장 항목이 있다
- 헤드리스 스모크에서 카드가 시드된 상태로 Phase 5.5 에 도달하거나, 네트워크 차단 시 미확보 표기로 정상 종료한다

### SR-05 · 문서 스킬 소비 — cover-letter·resume·ncs·career-history  `[P1/S]` · 의존: SR-01, SR-02
cover-letter(SKILL.md 298줄, 줄 수 net-zero): 경험 뱅크 우선 활용 문장에 `list --company <기업명>` 우선 제시, '요' 불릿에 `apply_plans` 우선·§7 폴백·근거 없으면 `/company_research` 안내; `structure-guide.md` '요' 불릿 3곳·L29 STAR→STAR-R·포부 시간축 첫 문장 규칙; `structured-modes.md` 카드 재사용 순서 0번; `review-steps.md` 배운 점 규칙 뒤에 R 잇기 규칙. resume(299줄, net-zero): Phase 5 제목·문장에 "이력서 본문은 S·T·A·R 까지, 두 번째 R 은 카드 `apply_plans` 로 자소서·면접용", 체크 문구 STAR-R, `star-quantify.md` 한 줄. ncs: Phase 5 STAR-R 연결과 기관 분석 근거 조건, 기관명 치환 문장. career-history: 지원 기업이 정해졌으면 `list --company` 카드를 배치 1순위 후보로(R 문장은 옮기지 않음).

**완료 판정:**
- 세 SKILL.md `wc -l` 이 각각 299 이하(resume·cover-letter·mock-interview 포함)
- 린트 8종 통과, `structure-guide.md`·`review-steps.md`·`structured-modes.md`·`star-quantify.md` 에 §7 참조가 있다

### SR-06 · mock-interview 연결  `[P2/S]` · 의존: SR-02
SKILL.md 의 경험 카드 항목을 한 줄 안에서 `list --company`·`apply_plans` 소비로 재작성; `modes/personality.md` 의 STAR 체크를 STAR-R(R 은 기업 근거와 함께, 근거 없는 포부는 감상형으로 지적)로; `interview-flow.md` 꼬리질문 5세트 표 뒤에 "입사하면 이 경험을 어디에 어떻게 쓰겠어요?" 검증 규칙 한 줄(표 자체는 6곳 복제라 건드리지 않음).

**완료 판정:** SKILL.md 299줄 이하, 두 references 에 규칙 존재, 린트 통과

### SR-07 · 테스트·eval  `[P1/S]` · 의존: SR-02, SR-03
`test/test-exp.sh` 에 `apply` 블록(정상 저장·주석 보존·같은 회사 교체·다른 회사 추가·누락 플래그 거부·없는 id·`list` 열/푸터/필터·`--json` 구조) 과 validate 위반 픽스처(basis 공백·회사 중복·created_at 오류). `evals/experience-bank/evals.json` 에 gate 케이스 `expbank-gate-star-r-apply`(setup 으로 캐시 요약 블록 파일과 카드 1장을 만들고, `must_call apply --company --plan --basis --source`, `must_output 적용 저장됨`, `must_read references/experience-methods.md`). `docs/evals.md` 케이스 수 갱신.

**완료 판정:** `bash test/test-exp.sh` 전부 PASS, `bash test/run-evals.sh --dry-run --skill experience-bank` 가 새 케이스를 나열, gate 실측 PASS

### SR-08 · 문서·릴리스 1.1.0  `[P1/S]` · 의존: SR-01~SR-07
`VERSION`·`.claude-plugin/plugin.json`·`bin/package.json` 1.1.0, `CHANGELOG.md` 1.1.0 Added/Changed(리뷰 후 Fixed), `README.md` 스킬 표·결정적 스크립트 계층 문구, 이 계획서 §8 실행 로그, `docs/E2E-TEST-REPORT.md` 스모크 행.

**완료 판정:** `test/test-plugin-manifest.sh`·`test/run-integration-test.sh` 통과, CHANGELOG 항목이 SR-ID 를 가리킨다

---

## 4. 수용 기준 표

| ID | 항목 | 근거 | 공수 | 수용 기준 |
|---|---|---|---|---|
| **SR-01** | 방법론 §7 STAR-R(R=입사 후 적용) | §1 현황 ①②, 오너 결정 ① | S | §7 존재, 복제본 9개 동일, 린트 통과 |
| **SR-02** | `apply_plans` 필드 + `apply`/`list --company`/`validate` | §1 카드 계약, D1~D4 | M | 기존 카드 호환, 누락 근거 거부, test-exp 전부 PASS |
| **SR-03** | experience-bank 입사 후 적용 절 | D6 | S | 절 존재, script-layer·size 린트 통과, gate eval PASS |
| **SR-04** | company-research Phase 5.5 | D6, §1 기업분석 산출물 | S | 절 존재·참조 복제본 생성, 스모크 도달 |
| **SR-05** | 문서 스킬 4종 소비 규칙 | D5 | S | 세 SKILL.md 299줄 이하, references 에 §7 참조 |
| **SR-06** | mock-interview 연결 | D5 | S | SKILL.md 299줄 이하, references 규칙 존재 |
| **SR-07** | 테스트·eval | SR-02·SR-03 | S | test-exp 신규 단언 PASS, gate 케이스 등록·실측 PASS |
| **SR-08** | 문서·릴리스 1.1.0 | 릴리스 관례 | S | manifest·통합 테스트 통과 |

---

## 5. 실행 순서·검증

| 단계 | 내용 | 검증 |
|---|---|---|
| 0 | 브랜치를 `origin/main` 에서 재시작 | — |
| C1 | 이 계획서 | `bash test/lint-conventions.sh` |
| C2 | SR-02 + test-exp | `node --check bin/jobstack-exp.mjs && bash test/test-exp.sh && bin/gen-skill-docs.sh --check` |
| C3 | SR-01·SR-03·SR-04·SR-07(eval) | `bin/gen-skill-docs.sh` 후 린트 8종 + `bash test/run-evals.sh --dry-run --skill experience-bank` |
| C4 | SR-05·SR-06 | 린트 8종 + `wc -l resume/SKILL.md cover-letter/SKILL.md mock-interview/SKILL.md` |
| C5 | SR-08 | `bash test/test-plugin-manifest.sh && bash test/run-integration-test.sh` |
| 리뷰 | 3관점 병렬 리뷰(컨벤션·§7 적대적 검증·스크립트 코드리뷰) → 수정 커밋 | 전체 린트 재실행 |
| 스모크 | 격리 HOME 에서 gate eval + `/company_research`·`/cover_letter` 헤드리스 실측 | §8 실행 로그·E2E 리포트 기록 |
| PR | 새 PR(결정·수용 기준·검증 범위·실측 표) | CI lint-and-test·macos-smoke |

---

## 6. 리스크와 완화

- **R 이 일반론으로 흐를 위험** — 스크립트는 `basis`·`source` 공백만 막고 진위는 보지 못한다. §7 규칙 ①③, experience-bank 의 "요약 블록 원문만 basis", company-research 가 자기 산출물에서만 basis 를 뽑는 구조, 적대적 리뷰("캐시 없이 훈련 데이터로 basis 를 채우게 유도되는가")로 방어한다.
- **감상형 R 회귀** — 일반 STARR 지식이 모델을 '배운 점' 으로 끌 수 있다. §7 의 "의도적으로 다르다" 문단과 규칙 ④, personality.md·review-steps 의 진단 항목화로 막는다.
- **삭제 경로 부재** — upsert 가 덮어쓰므로 실사용 문제는 적다. `--remove` 는 후속.
- **eval 비용·CLI 의존** — gate 케이스는 로컬·야간 실행(기존 정책), CI 는 `--dry-run` 만.

## 7. 후속 후보 (범위 밖)

`apply <id> --company C --remove` · strategy GAP 분석에서 R 제안 · defense-map `answer_hint` 가 카드 R 인용 · retro 회고의 '다음 행동' → 카드 갱신 · `bin/jobstack-preamble` 에 company-cache 개수 노출.

---

## 8. 실행 로그

구현 후 기록: 커밋 해시 · 테스트 결과 · 리뷰 표(`| # | 관점 | 대상 | 지적 | 판정 | 조치 |`) · 스모크 표.
