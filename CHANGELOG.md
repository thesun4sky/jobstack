# Changelog

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
