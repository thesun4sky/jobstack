# jobstack 개발 가이드

## 구조

- 각 스킬은 `{skill-name}/SKILL.md` 로 정의하고, 같은 디렉토리에 생성 파일을 둔다
  - `scripts/preamble.sh` — 프리앰블 로케이터(생성, 원본 `templates/skill-preamble.sh`)
  - `references/*.md` — 스킬이 읽는 공유 문서의 복제본(생성, 원본 `templates/*.md`·`docs/*.md`)
  - 생성 파일은 `bin/gen-skill-docs.sh` 로 동기화하고 `test/test-skill-refs.sh` 가 드리프트를 잡는다
- SKILL.md 상단은 동적 주입 라인 두 줄이다 — 프리앰블(`bin/jobstack-preamble`)과 가드레일. 봇 노출 스킬은 `references/bot-protocol.md` 주입 라인이 하나 더 있다(`templates/preamble.md` 참조)
- YAML 프론트매터: `name`, `description`, `allowed-tools` (Claude Code 표준) + `preamble-tier`, `version`, `benefits-from` (jobstack 메타)
- 참조 규칙: `${CLAUDE_SKILL_DIR}` 뒤에는 스킬 디렉토리 안쪽 경로만 온다(`references/…`, `scripts/…`). `..` 은 심링크 설치에서 Read 가 실패하므로 금지. bin 스크립트는 `$_JS_BIN` 으로 부른다
- Bash 스니펫은 첫 줄에 `. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"` 를 두어 `$_JS_STATE`·`$_JS_BIN`·`$TODAY` 를 불러온다
- 봇(jobclaw) 전용 출력 규칙(`[IMAGE_PROMPT:]`, `[CHOICES]`, `[OUTPUT_FILE:]`)은 SKILL.md 본문이 아니라 `templates/bot-protocol.md` + `templates/bot/{skill}.md` 에 둔다
- 공유 템플릿: `templates/` (guardrails, voice, ask-user-question, completion-status, experience-methods, humanize-check, three-docs-guide, bot-protocol)
- 상태 관리: `~/.jobstack/` (YAML/JSONL/Markdown) — 경로는 항상 `$_JS_STATE` 또는 `JOBSTACK_STATE_DIR` 로
- 설정 관리: `bin/jobstack-config` (get/set/list)

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
3. `install.sh` 의 `SKILL_DIRS` 와 `test/test-preambles.sh` 의 `SKILLS` 에 추가
4. `test/run-integration-test.sh` 로 린트 9종 통과 확인

## 테스트

- `test/run-integration-test.sh` — 린트 전체 + 설치·뷰어·상태 파일 검사 (CI 는 격리된 HOME 에서 실행)
- `test/test-preambles.sh` — 프리앰블 격리 실행(심링크 경로 주입) · `test/test-skill-refs.sh` — 참조 경로·생성 파일 드리프트·봇 마커
- `test/lint-conventions.sh` — AI 만능 표현·금지 표현·시장 수치 · `test/test-command-style.sh` · `test/test-no-home-paths.sh` · `test/run-golden.sh`

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
