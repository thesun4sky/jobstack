# Changelog

## [1.0.0] - 2026-09-03

검토 보고서 P2 항목(U-14~U-16, U-18~U-20, U-22, U-23) — 기능 확장. 실행 기록은
`docs/plans/v1.0-execution-log.md`.

### Added
- **반복 실행 경로 (U-14)** — `bin/jobstack-cron run|install|uninstall|status`: 플랫폼별
  `fetch-jobs.mjs` 수집 결과를 이전 스냅샷과 비교해 새 공고·마감 D-7·`jobstack-tracker nudge`
  정체 건을 `job-cache/daily-YYYY-MM-DD.md`로 남기고 cron(리눅스)/launchd(macOS)에 등록한다.
  모델 호출은 하지 않는다(비용·무인 권한). 클라우드 Routines 가이드 `docs/routines.md`.
- **Claude in Chrome 경로 (U-15)** — `templates/chrome-path.md`: scout-profile(프로필 탭 읽기)·
  company-research(로그인 리뷰 상세 익명 집계)·job-search(로그인 필터 결과)가 확장이 있을 때만
  쓰는 선택 경로. 읽기·초안 반영까지만, 자동 지원·제출은 비목표. 확장이 없으면 붙여넣기 경로.
- **스킬 eval 체계 (U-16)** — `evals/<skill>/evals.json`(5개 스킬 × 3케이스 + 트리거 질의)과
  `test/run-evals.sh`: `claude -p` 헤드리스 실행 스트림에서 산출물·Bash 호출·Read 경로를 뽑아
  must_contain/must_call/must_read를 결정적으로 판정하고, `periodic` 케이스는 Haiku 채점을 한 번
  더 거친다. gate/periodic/e2e 3계층. API 비용 때문에 CI가 아니라 로컬·야간 실행(`docs/evals.md`).
- **claude.ai/Cowork 패키징 (U-18)** — `bin/package-skill.sh <skill|all>`: SKILL.md·references·
  scripts/preamble.sh만 담은 zip을 만들고 참조 무결성을 검사한다. bin이 없는 환경의 축소 모드는
  `docs/cowork.md`(실제 Cowork 세션 실측은 미완 — 확인 항목 명시).
- **운영 학습 로그 (U-20)** — `bin/jobstack-learn add|top|list|validate`: 수집 셀렉터 깨짐·차단·
  반복 자료 요청 같은 메타만 `analytics/learnings.jsonl`에 남기고(개인정보 휴리스틱 거부),
  `/auto` 대시보드가 상위 3건을 보여준다. 어휘는 `docs/telemetry-events.md`에 정식 등록.
- **AI 협업 평가 대비 (U-22)** — mock-interview 기술면접에 "AI 도구 활용 과제" 서브모드(문제
  접근→프롬프트 설계→출력 검증 근거→수정 이력), company-research 전형 확인 항목 ⑥(코딩테스트·
  과제의 AI 사용 허용 여부 — 미확인 시 "사용 안 함이 안전").
- **제도·지원금 체크리스트 (U-23)** — `templates/policy-checklist.md`: 탈락 후 권리(tracker)와
  지원 시 정책 인센티브(salary·strategy) 항목. 수치·시행 여부는 적지 않고 실행 시 WebSearch로
  출처·기준일을 병기한다.

### Changed
- **모델·effort 라우팅 (U-19)** — tracker `model: sonnet`·`effort: low`, 문서 첨삭·면접·기업분석·
  전략 스킬 `effort: high`를 프론트매터로 선언. 비교 실측은 `docs/plans/v1.0-execution-log.md`.
- auto 대시보드의 지원 현황·정체 넛지가 `jobstack-tracker stats|nudge` 출력을 쓰도록 통일.
- CI·통합 테스트에 cron·learn·package-skill 테스트 추가. README·CLAUDE.md·CONTRIBUTING 현행화.

### Fixed — 다각도 리뷰 반영 (실행 기록 `docs/plans/v1.0-execution-log.md`)
- 스크립트: `package-skill.sh`·`run-evals.sh` 옵션 값 누락 시 무한 루프와 mktemp 실패 미확인(루트 쓰기)
  차단, `run-evals.sh` bash 3.2 호환(`mapfile` 제거)·`claude -p` 타임아웃(`EVAL_TIMEOUT_S`)·채점 모델
  오버라이드(`--judge-model`), `jobstack-cron` crontab `%`·plist 이스케이프·python3 사전 확인·
  `JOBSTACK_CRON_OS_NAME` 테스트 훅, `jobstack-learn` dup 판정 flock.
- v0.5.0 스크립트: `hwpx2md.py` zip 엔트리 크기 상한·중첩 표·RecursionError 처리, `is-fetch.py`
  Retry-After 파싱 크래시, 사람인 파서 cheerio 지연 로드·script/style 제거, `jobstack-tracker` 손상
  파일 exit 2 통일, `jobstack-exp.mjs update` ai_usage 부분 지정 거부, `jobstack-fetch-diag` 리댁션
  fail-closed, `md2docx.mjs` 원자적 쓰기.
- 스킬 배선: resume 지원 유형 확인·경험 카드 소비, mock-interview 경험 카드 로드, company-research
  종합 적합도(정수) → tracker `--fit-score`, researcher `partial` 처리, cover-letter 구조화 전형 완료
  게이트 역참조·defense-map 필드 명세, job-search `--platform` 단일 수집, auto 예시 PII 확인 가드·
  Glob 대체 경로, allowed-tools 에 `Task` 병기(+ `test-skill-size --frontmatter` 도구명 검사).
- 문서 정정: Routines 과금(구독 사용량 소모)·최소 간격 기준일, Cowork 전제 `[2차]` 표기·`/resume`
  충돌 확인 항목, telemetry-events 초안 잔재 제거, NOTES.md 막다른 참조 제거, tracker 탈락 후
  체크리스트 수치 제거, policy-checklist 의 cron 분기 알림 문구 완화, 0.5.0 바이트 감소율 정정.
- PR #17 리뷰 반영: `md2docx.mjs` CLI 진입 판정을 realpath 비교로 바꿔 심링크 경로(macOS `/tmp`)에서도
  변환하고, `jobstack-export` 는 산출물 존재·zip 유효성을 확인한 뒤에만 성공을 보고. `run-integration-test.sh`
  는 기본으로 격리 HOME 에서 실행(`--real-home` 일 때만 실제 설치 검증). `.hwp` 변환의 `npx kordoc` 자동
  실행은 기본 꺼짐(`JOBSTACK_ALLOW_NPX=1` 명시 허용, `kordoc@4.12.3` 고정). `jobstack-cron` 은 node 부재
  시 exit 1, 전 플랫폼 수집 실패 시 exit 2, cron/launchd 등록 항목에 PATH 를 넣음. tracker·exp·defense-map
  의 읽기-수정-쓰기를 파일 잠금으로 감싸 동시 add 유실 방지. `fetch-jobs.mjs`·cron 의 limit 을 1~100 정수로
  검증. 테스트를 실경로·launchd 기대값으로 분리하고 CI 에 macOS smoke job 추가. 후속 리뷰로 README 플러그인
  예시 명령을 `/jobstack:job-search` 로 정정(플러그인 네임스페이스는 하이픈, 로컬 alias·봇은 언더스코어).
- 머지 전 스킬 스모크(2026-09-06, `docs/E2E-TEST-REPORT.md`): company-research·salary·strategy 의 병렬 리서치 문구에
  Agent 호출을 한 응답에 함께 발행하고 결과를 기다리도록 명시 — 헤드리스에서 백그라운드 서브에이전트가 결과 수신 전에
  턴을 끝내는 것을 관찰.

## [0.5.0] - 2026-09-03

검토 보고서 P1 항목(U-07~U-13, U-17, U-21) — 실행 기반 현대화와 시장 정합. 실행 기록은
`docs/plans/v1.0-execution-log.md`.

### Added
- **플러그인 패키징 (U-07)** — `.claude-plugin/plugin.json`(스킬 16개·`researcher` 에이전트)과
  `.claude-plugin/marketplace.json`으로 저장소 자체가 마켓플레이스가 된다(`/plugin marketplace add
  thesun4sky/jobstack` → `/plugin install jobstack@jobstack`). 플러그인 설치에서는 Node 의존성을
  `${CLAUDE_PLUGIN_DATA}/node`에 두고 `bin/node_modules`를 심링크한다. `test/test-plugin-manifest.sh`.
- **결정적 스크립트 계층 (U-09)** — `bin/jobstack-tracker`(add/update/list/calendar/stats/nudge/
  migrate/validate, `docs/tracker-states.md` 구현), `bin/jobstack-exp.mjs`(경험 카드 add/list/show/
  update/validate), `bin/jobstack-defense-map.mjs`(add/list/show/set-status/stats/validate),
  `bin/jobstack-ats-match`(키워드 매칭률·등급), `bin/jobstack-retro-stats`(회고 프론트매터 집계).
  스킬은 호출·해석만 하고 상태 파일을 손으로 쓰지 않는다 — `test/test-script-layer.sh`가 강제.
  `docs/experience-card-schema.md` 신설.
- **병렬 리서치 서브에이전트 (U-10)** — `agents/researcher.md`(WebSearch·WebFetch·Bash·Read, JSON
  반환 계약: 출처 URL·기준일 필수, 원티드 마감은 `deadline_verified: false`). company-research·
  salary·strategy가 Agent 도구로 소스별 fan-out 후 합성.
- **한글 문서 인제스트 (U-11)** — `bin/hwpx2md.py`: HWPX(OWPML)를 표준 라이브러리만으로
  마크다운으로, HWP 5.x는 kordoc/rhwp가 있을 때 변환하고 없으면 HWPX 저장 안내. auto Phase 1에
  감지→변환 단계 추가.
- **수집 계층 정비 (U-12)** — `bin/is-fetch.py`: 경계 매칭 마커·`block_class`(waf_challenge/captcha/
  access_denied/rate_limited/login_wall)·Retry-After 1회 재시도·`--profiles`; `bin/jobstack-fetch-diag`
  (진단 로그 집계·연속 차단 경고); 사람인은 `bin/parsers/saramin.mjs`(cheerio)로 브라우저 없이
  파싱하고 `bin/sources/saramin-api.mjs`(사람인 오픈API, `jobstack-config set saramin_api_key`)를
  `--source api|scrape|auto`로 우선 사용; `fetch-jobs.mjs`는 브라우저를 필요한 플랫폼에서만 lazy 기동.
  의존성 고정: playwright `~1.62.1`, cheerio, docx, yaml, `engines.node >= 22`, curl_cffi `>=0.16,<0.17`.
- **docx 내보내기 이중화 (U-13)** — `bin/md2docx.mjs`(Node `docx`, 표·이미지 없는 단일 컬럼)를
  `jobstack-export`의 폴백으로 연결. pandoc 3.6 미만은 폴백으로 전환, exit 2는 "pandoc·Node 폴백
  모두 불가"로 재정의.
- **NCS 개편 참조 (U-17)** — `docs/ncs-competencies.md`(구 직업기초능력 10영역·34하위 확정 /
  신 직업공통능력 7영역·21하위 `[2차]`, 체계 판정 규칙, 구→신 매핑 원칙). ncs·cover-letter·
  mock-interview 본문의 고정 영역 목록을 제거하고 실행 시 공고에서 체계를 확인한다.
- **구조화 전형 대응 (U-21)** — `templates/structured-modes.md`: 경험기술서 모드(문제·역할·행동·
  결과 4분리, 문항별 글자수 게이트, AI·도구 활용 문항 지침)와 문답형 상세지원서 모드(일괄 초안,
  답변 간 사실 일관성 검사). cover-letter Phase 0 선택지 D. 경험 카드 `ai_usage` 필드.

### Changed
- **진행적 공개 (U-08)** — 거대 스킬 6개를 SKILL.md(흐름·게이트) + `references/`(모드별·플랫폼별·
  트랙별 자료, 스킬 소유)로 분할: auto 338→275, cover-letter 505→294, resume 487→296,
  mock-interview 461→292, job-search 443→264, company-research 419→260(바이트 기준 초기 로드 8~39%
  감소, 평균 약 29% — auto 8%는 hwpx 변환·라우팅 행 추가분 포함. 검토 보고서 목표 50%에는 못 미침: 게이트·판단 규칙을 SKILL.md에 남기는 쪽을 택했다). 16개 스킬 전부 300줄 이하,
  프론트매터에 `argument-hint`·`when_to_use` 추가, jobstack 메타는 `metadata:` 아래로. 원본 줄
  보존은 결정적 검증기로 확인(유실 0). `test/test-skill-size.sh`, `bin/gen-skill-docs.sh`가 스킬
  소유 참조·하위 디렉토리를 지원.
- tracker·retro·experience-bank·ncs 본문이 스크립트 호출 흐름으로 바뀜(JSONL/YAML 직접 편집 지시 0건).
- CI: Node 의존성 설치, 스크립트 테스트 12종, 크기·프론트매터·스크립트 계층·매니페스트 린트 추가.
- README·CLAUDE.md·CONTRIBUTING·templates/preamble.md 현행화.

## [0.4.0] - 2026-09-03

검토 보고서(`docs/plans/version-upgrade-review-2026-09.md`) P0 항목 U-01~U-06. 실측으로 확인한
결함 3건을 고치고 실행 기반을 정리했다. 실행 기록은 `docs/plans/v1.0-execution-log.md`.

### Fixed
- **공유 템플릿이 CLI 설치에서 로드되지 않던 결함 (D-1, U-01)** — 심링크 설치에서
  `${CLAUDE_SKILL_DIR}`이 심링크 경로로 치환되고 Read 도구가 `../templates/…`를 열지 못해
  16개 스킬의 가드레일·방법론 참조 113곳이 실패했다. 참조를 스킬 안쪽 `references/`
  복제본으로 바꾸고(`bin/gen-skill-docs.sh`가 동기화), 가드레일은 로드 시점 동적 주입으로
  인라인한다. `test/test-skill-refs.sh`가 재발을 막는다.
- **봇 전용 프로토콜의 CLI 누수 (D-2, U-02)** — `[IMAGE_PROMPT:]`(5개 스킬)·`[CHOICES]`·
  `[OUTPUT_FILE:]`·`render-docx.sh` 지시를 SKILL.md 본문에서 빼고 `templates/bot-protocol.md`
  + `templates/bot/<skill>.md`로 옮겼다. 프리앰블이 `JOBCLAW_RUN_ID`로 `JOBSTACK_RUNTIME=bot`을
  판정할 때만 주입된다. ncs(CLI 전용)의 봇 마커는 제거.
- **결과물 뷰어 (D-3, U-03)** — `</script>` 치환이 무효였던 버그(마크다운을 `<textarea>`에
  HTML 이스케이프해 삽입), marked 18.0.11을 `bin/vendor/`에 인라인(오프라인 렌더), 렌더러
  부재 시 원문 표시 폴백, 죽은 이스케이프 코드 제거.
- **교차 모순 (U-06)** — retro `allowed-tools`에 WebSearch 추가·defense-map 방어 준비율 소비,
  auto에 experience-bank·career-history·scout-profile·retro·salary·portfolio 라우팅 표,
  `EXPERIENCES_EXIST`→`EXPERIENCES_EXISTS` 통일, ncs가 경험 카드를 입력으로 사용,
  scout-profile `allowed-tools`를 실제 사용 도구로 축소, `fetch-jobs.mjs`의 미지원
  programmers 분기 삭제.

### Changed
- **프리앰블 스크립트화 (U-04)** — 16개 스킬에 복사돼 드리프트하던 인라인 bash 프리앰블
  (39~72줄)을 `bin/jobstack-preamble` 하나로 대체. SKILL.md 상단은 동적 주입 한 줄
  (`!`bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" <skill> "${CLAUDE_SESSION_ID}"``)이며
  실행 컨텍스트·`env.sh`(`_JS_STATE`·`_JS_BIN`·`TODAY`)·텔레메트리 entry(`session` 필드 추가)를
  낸다. Cowork·정책 차단 환경 폴백 안내 포함. SKILL.md 총 5,837줄 → 5,120줄.
- **설치 위치** — `install.sh`가 Claude Code 표준 위치 `~/.claude/skills/`에 심링크하고
  이 저장소가 만든 옛 `~/.claude/commands/` 심링크를 정리한다. `--with-insane-search`는
  curl_cffi 0.16 계열로 상향.
- **릴리스 위생 (U-05)** — GitHub Actions CI(린트 9종 + 격리 HOME 통합 테스트), README의
  의존성·설치 설명 현행화, CLAUDE.md·CONTRIBUTING.md에 새 구조 반영, 7월 미기록 변경
  소급 기재(아래).

### 2026-07 미기록 변경 (0.3.0 이후 main 20커밋, PR #12·#13·#14·#16)
- job-search v0.5.0 — 크롤러 0건 수집 시 실패 원인 진단 로깅(`bin/fetch-diag.mjs`,
  `fetch-diag.log`), 원티드 마감 검증 코드 강제(`bin/wanted-verify.mjs`, `verify` 서브커맨드,
  detail API 전수검증·fail-closed·429 Retry-After 재시도)
- insane-search 흡수 Phase 1·2 — `bin/is-fetch.py`(curl_cffi TLS 임퍼소네이션, SSRF 가드,
  리다이렉트 상한·응답 크기 가드) + `bin/is-fetch-adapter.mjs`, 사람인 수집을 어댑터 경유로,
  company-research·salary의 WebFetch 실패 시 is-fetch 재시도, `install.sh --with-insane-search`
- 테스트 4종 추가(`test-fetch-diag.mjs`, `test-wanted-verify.mjs`, `test-is-fetch-adapter.mjs`,
  `test-is-fetch-ssrf.mjs`), 통합 검토·실행계획 문서(`claudedocs/`, `docs/plans/`)

## [0.3.0] - 2026-07-04

tea-agent(헤르메스) 지식 자산 + 2026 채용시장 트렌드 분석 기반 전면 업그레이드.
멀티에이전트 분석 4라운드 → 계획서(`docs/plans/skill-upgrade-plan-2026-07.md`) →
M1 인프라 → M2~M5 스킬 업그레이드 순으로 진행. Council #1(4자 에이전트 투표)로
오너 결정 7건 확정.

### Added
- **신규 스킬 3개**
  - `experience-bank` (tier 2) — 경험 소재 발굴·카드화. `experiences.yaml`에 append,
    resume/cover-letter/mock-interview의 입력 자산
  - `career-history` (tier 3) — 경력기술서 작성/첨삭, 이력서-경력기술서-자소서 역할 구분
  - `scout-profile` (tier 3) — 링크드인/원티드/리멤버 프로필 첨삭
- **공유 인프라 (M1)**
  - `templates/guardrails.md` — 사실 날조·PII 금지, 한계 노출→자료 요청 전환,
    시장 수치 하드코딩 금지, KST 날짜, 금지 표현 (13개 스킬이 프리앰블 직후 Read)
  - `templates/experience-methods.md` — 경험 전환 6단계·수치 폴백 5기준·전환표 등
  - `templates/humanize-check.md` — 치환 테스트 2종·AI풍 신호 진단
  - `templates/three-docs-guide.md` — 3문서 역할 구분 공유 블록
  - `docs/tracker-states.md` — canonical 9상태 모델 (저장=영문 키, 표시=한글 라벨,
    `max_stage` 퍼널 필드, v1 하위호환 정규화)
  - `docs/defense-map-schema.md` + `templates/defense-map-example.yaml` — 문장↔꼬리질문 맵 계약
  - `docs/telemetry-events.md` — 스킬 사용 이벤트 규격 (로컬 파일 한정)
  - `bin/jobstack-export` — pandoc md→docx 변환 (ATS-safe, Noto Sans KR)
  - `test/lint-conventions.sh` — AI 만능 표현·금지 표현·시장 수치 하드코딩 린트

### Changed
- **13개 스킬 P0~P2 업그레이드** (auto v0.2, strategy v0.2, tracker v0.2,
  company-research v0.3, portfolio v0.2, job-search v0.5, ncs v0.2, salary v0.2,
  resume v0.2, cover-letter v0.2, mock-interview v0.2, retro v0.2, review v0.2)
  - 공채 중심 전제 → 수시 중심으로 교정, 중고신입·경력전환 트랙 추가
  - 시장 수치를 본문 하드코딩 대신 WebSearch 동적 확인 규칙으로 전환
  - 사실 날조·PII 가드레일 연결, 공고 미확보 시 점수 산출 게이트
  - 방법론을 templates/ 공유 참조로 단일화 (중복 제거)
- CLAUDE.md tier 표 16개 스킬로 갱신, install.sh·통합 테스트 스킬 목록 확장

## [0.2.0] - 2026-07-03

### Fixed
- 봇↔스킬 경계 드리프트 정리 (딥다이브 C1~C4)
  - `/mock-interview` — AskUserQuestion 자기모순 제거: 면접 답변은 자유서술로 받는다는
    정책과 상충하던 "AskUserQuestion으로 답변을 받습니다" 잔재 지시 3곳 정정
  - 하드코딩 `~/.jobstack` 경로 16곳을 `$_JS_STATE` 표기로 치환
    (auto, company-research, mock-interview, retro, strategy, tracker —
    봇 러너의 `JOBSTACK_STATE_DIR` 강제·`Write(~/*)` deny 정책과 상충 해소)
  - 사용자 노출 추천 명령을 Telegram 언더스코어 표기로 정정
    (`/cover-letter` → `/cover_letter` 등 — 하이픈 표기는 봇에서 탭 불가)
- PR #10 외부 리뷰 반영
  - mock-interview Step 2 잔존 하이픈 표기 정정 (`/company_research`로 통일)
  - README 명령 표기 정합 — 사용자 노출 명령은 언더스코어 표기, 지원 현황은
    봇 네이티브 `/track`·`/myapps`, NCS는 `/cover_letter`의 공기업 NCS 보강으로
    안내. CLI 전용 스킬은 디렉토리 표기(`tracker/`, `ncs/`)로 분리 서술
  - job-search·ncs 스킬 본문 제목 표기 정리 (`# /job_search`, `# ncs`)

### Changed
- 유령 스킬 추천 제거 (운영자 확정 정책)
  - `/tracker` 추천·연동 안내 제거 — 봇 네이티브 `/track`·`/myapps`로 일원화
    (tracker 스킬 자체는 CLI 용도로 잔존)
  - `/ncs` 추천 제거 — `/cover-letter`에 "공기업·공공기관 지원 시 NCS 직업기초능력
    관점 보강" 소절로 흡수

### Added
- `templates/BOT-COMMAND-STYLE.md` — 사용자 노출 추천 명령 표기 규칙 문서화
- `test/test-no-home-paths.sh` — `~/.jobstack` 하드코딩 재발 방지 린트
  (프리앰블의 `${JOBSTACK_STATE_DIR:-$HOME/.jobstack}` 폴백은 예외)
- `test/test-command-style.sh` — 하이픈 명령 표기·봇 미노출 스킬 추천 재발 방지 린트
  (예외: 리포트 버전 스탬프 `jobstack /<skill> v<N>`, 디렉토리/경로 표기,
  표기 규칙 문서 `templates/BOT-COMMAND-STYLE.md` 자체. docs/는 과거 산출물이라 미검사)

## [0.1.1] - 2026-04-07

### Fixed
- `/portfolio` - `allowed-tools`에 `Glob` 누락 수정 (Phase 1 파일 스캔에 필요)

### Changed
- `/retro` - 누적 패턴 분석 기능 추가
  - 이전 회고 3건 이상이면 C) 패턴 분석 옵션 강력 추천
  - `Grep` 기반 교차 분석으로 반복 약점 자동 집계
  - 개선 추세 시각화 추가

## [0.1.0] - 2026-03-29

### Added
- 13개 스킬 초기 릴리스
  - `/auto` - 자동 감지 + 단계별 가이드
  - `/strategy` - 취업전략 수립
  - `/company-research` - 기업분석 (7가지 키워드 소스)
  - `/resume` - 이력서 작성/첨삭
  - `/cover-letter` - 자소서 작성/첨삭 ("결이요" + 5단계 첨삭)
  - `/portfolio` - 포트폴리오 최적화
  - `/mock-interview` - 모의면접 (5가지 모드)
  - `/job-search` - 채용정보 탐색
  - `/ncs` - NCS 역량 매핑
  - `/salary` - 연봉 분석/협상
  - `/tracker` - 지원 현황 관리
  - `/review` - 통합 서류 리뷰
  - `/retro` - 회고/개선
- `install.sh` 원라인 설치
- `bin/jobstack-config` 설정 관리
- `ETHOS.md` 코칭 철학 (4년간 60건+ 첨삭 인사이트)
