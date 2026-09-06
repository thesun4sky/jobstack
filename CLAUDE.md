# jobstack 개발 가이드

## 구조

- 각 스킬은 `{skill-name}/SKILL.md` 로 정의하고, 같은 디렉토리에 생성 파일을 둔다
  - `scripts/preamble.sh` — 프리앰블 로케이터(생성, 원본 `templates/skill-preamble.sh`)
  - `references/*.md` — 스킬이 읽는 공유 문서의 복제본(생성, 원본 `templates/*.md`·`docs/*.md`) **또는** 그 스킬만의 참조 자료(스킬 소유, 원본 없음 — 모드별·플랫폼별·트랙별 정적 자료, 하위 디렉토리 허용)
  - 생성 파일은 `bin/gen-skill-docs.sh` 로 동기화하고 `test/test-skill-refs.sh` 가 드리프트를 잡는다
- SKILL.md 상단은 동적 주입 라인 두 줄이다 — 프리앰블(`bin/jobstack-preamble`)과 가드레일. 봇 노출 스킬은 `references/bot-protocol.md` 주입 라인이 하나 더 있다(`templates/preamble.md` 참조)
- YAML 프론트매터: `name`, `description`, `allowed-tools`, `argument-hint`, `when_to_use`, `model`, `effort` (Claude Code 표준) + `metadata:` 아래 `preamble-tier`, `version`, `benefits-from` (jobstack 메타). SKILL.md 는 300줄 이하(`test/test-skill-size.sh`) — 흐름·게이트·판단 규칙만 두고 정적 자료는 `references/` 로 옮겨 필요한 시점에 Read 한다(진행적 공개)
- `allowed-tools` 의 서브에이전트 도구는 `Agent` 와 `Task` 를 함께 적는다(공식 문서 표기는 `Agent`, 2.1.259 헤드리스 init 이벤트는 `Task` 로 노출). 도구명 오타는 `test/test-skill-size.sh --frontmatter` 가 잡는다
- 참조 규칙: `${CLAUDE_SKILL_DIR}` 뒤에는 스킬 디렉토리 안쪽 경로만 온다(`references/…`, `scripts/…`). `..` 은 심링크 설치에서 Read 가 실패하므로 금지. bin 스크립트는 `$_JS_BIN` 으로 부른다
- Bash 스니펫은 첫 줄에 `. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"` 를 두어 `$_JS_STATE`·`$_JS_BIN`·`$TODAY` 를 불러온다
- 봇(jobclaw) 전용 출력 규칙(`[IMAGE_PROMPT:]`, `[CHOICES]`, `[OUTPUT_FILE:]`)은 SKILL.md 본문이 아니라 `templates/bot-protocol.md` + `templates/bot/{skill}.md` 에 둔다
- 공유 템플릿: `templates/` (guardrails, voice, ask-user-question, completion-status, experience-methods, humanize-check, three-docs-guide, bot-protocol)
- 상태 관리: `~/.jobstack/` (YAML/JSONL/Markdown) — 경로는 항상 `$_JS_STATE` 또는 `JOBSTACK_STATE_DIR` 로
- 설정 관리: `bin/jobstack-config` (get/set/list)
- 결정적 스크립트 계층(`bin/`): 상태 파일은 스킬이 손으로 쓰지 않고 스크립트가 쓴다 — `jobstack-tracker`(지원 현황), `jobstack-exp.mjs`(경험 카드), `jobstack-defense-map.mjs`(방어맵), `jobstack-ats-match`(키워드 매칭률), `jobstack-retro-stats`(회고 집계), `jobstack-fetch-diag`(수집 진단 집계), `hwpx2md.py`(한글 문서 변환), `md2docx.mjs`(pandoc 없는 docx 폴백), `jobstack-cron`(공고 모니터링 반복 실행·cron/launchd 등록), `jobstack-learn`(운영 학습 로그 — 메타만), `package-skill.sh`(claude.ai/Cowork 업로드 zip). `test/test-script-layer.sh` 가 직접 편집 지시를 잡는다
- 서브에이전트: `agents/researcher.md` — company-research·salary·strategy 가 Agent 도구로 소스별 병렬 리서치를 맡긴다(JSON 반환 계약, 출처·기준일 필수)
- 플러그인: `.claude-plugin/plugin.json`(스킬 16개·에이전트) + `.claude-plugin/marketplace.json`. `test/test-plugin-manifest.sh` 가 VERSION·스킬 목록 정합을 검사한다. `install.sh` 심링크 설치와 병행 지원

## preamble-tier

| Tier | 용도 | 스킬 |
|------|------|------|
| 1 | 진입점, 항상 사용 가능 | auto, strategy, tracker |
| 2 | 분석/조사 | company-research, portfolio, job-search, ncs, salary, retro, experience-bank |
| 3 | 문서 작성 | resume, cover-letter, career-history, scout-profile |
| 4 | 복합 대화형 | mock-interview, review |

## 스킬 추가 방법

1. `{skill-name}/` 디렉토리 생성, `SKILL.md` 작성 (YAML 프론트매터 + 상단 주입 라인 — 기존 스킬 상단을 복사)
2. `bin/gen-skill-docs.sh` 실행 → `scripts/preamble.sh`·`references/` 생성
3. `install.sh` 의 `SKILL_DIRS`, `test/test-preambles.sh` 의 `SKILLS`, `.claude-plugin/plugin.json` 의 `skills` 에 추가
4. `test/run-integration-test.sh` 로 린트 전체 통과 확인(SKILL.md 300줄 이하·프론트매터 필수 키 포함)

## 테스트

- `test/run-integration-test.sh` — 린트 전체 + 설치·뷰어·상태 파일 검사 (CI 는 격리된 HOME 에서 실행)
- `test/test-preambles.sh` — 프리앰블 격리 실행(심링크 경로 주입) · `test/test-skill-refs.sh` — 참조 경로·생성 파일 드리프트·봇 마커
- `test/lint-conventions.sh` — AI 만능 표현·금지 표현·시장 수치 · `test/test-command-style.sh` · `test/test-no-home-paths.sh` · `test/run-golden.sh`
- `test/test-skill-size.sh --frontmatter` — 300줄 상한·description 예산·필수 키 · `test/test-script-layer.sh` — 상태 파일 직접 편집 지시 금지 · `test/test-plugin-manifest.sh`
- 스크립트 테스트: `test/test-tracker.sh` · `test-exp.sh` · `test-defense-map.sh` · `test-ats-match.sh` · `test-retro-stats.sh` · `test-hwpx.sh` · `test-export.sh` · `test-is-fetch-classify.sh` · `test-fetch-diag-summary.sh` · `test-fetch-jobs-saramin.sh` · `test-cron.sh` · `test-learn.sh` · `test-package-skill.sh` · `node test/test-*.mjs`
- 스킬 eval(`evals/<skill>/evals.json`, `test/run-evals.sh`): `claude -p` 헤드리스 실행으로 must_contain·must_call·must_read 를 판정한다. API 비용이 들어 CI 에 넣지 않고 로컬·야간에 돌린다(`docs/evals.md`)

## 핵심 철학 (ETHOS.md 참조)

- "결이요" 프레임워크 (결론→이유→요청)
- 5초 규칙
- before→after 수치화
- 7가지 기업 키워드 소스
- "메뉴판" + "미끼" + "이미 팀원처럼"

## 컨벤션

- 모든 프롬프트는 한국어 (YAML 키는 영어)
- 기술 용어는 영어 혼용 (ATS, NCS, STAR 등)
- AI 만능 표현 금지: "다각적", "포괄적", "심층적", "혁신적", "체계적"
- 사용자 노출 명령은 언더스코어 표기 (`templates/BOT-COMMAND-STYLE.md`)
