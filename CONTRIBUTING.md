# 기여 가이드

jobstack에 기여해주셔서 감사합니다!

## 기여 방법

1. 이 레포지토리를 Fork합니다
2. 새 브랜치를 생성합니다: `git checkout -b feature/new-skill`
3. 변경사항을 커밋합니다
4. Pull Request를 생성합니다 (CI가 린트 9종을 실행합니다)

## 스킬 작성 규칙

### 필수 요소
- **YAML 프론트매터**: `name`, `description`, `allowed-tools` + jobstack 메타 `preamble-tier`, `version`, `benefits-from`
- **상단 주입 라인**: 프리앰블 `!`bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" <skill> "${CLAUDE_SESSION_ID}"`` 과 가드레일 주입. 봇 노출 스킬은 bot-protocol 주입 라인 추가 (기존 스킬 상단을 그대로 복사)
- **생성 파일**: `bin/gen-skill-docs.sh` 로 `scripts/preamble.sh`·`references/` 동기화 (직접 편집 금지)
- **참조 경로**: `${CLAUDE_SKILL_DIR}/references/…` 만 사용. `../templates`, `../docs`, `../bin` 금지 (심링크 설치에서 Read 실패)
- **Bash 스니펫**: 첫 줄 `. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"`
- **보이스 섹션**: 한국어 코칭 페르소나
- **AskUserQuestion 규칙**: 현재상황 → 질문 → 추천 → 선택지
- **완료 상태 프로토콜**: DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT
- **봇 전용 출력**(IMAGE_PROMPT·CHOICES·OUTPUT_FILE)은 본문에 쓰지 않고 `templates/bot/<skill>.md` 에 둡니다

### 철학 준수
- ETHOS.md의 8대 원칙 준수
- "결이요" 프레임워크 적용
- before→after 수치화 권장
- AI 만능 표현 금지

### 언어
- 프롬프트: 한국어
- YAML 키: 영어
- 기술 용어: 영어 혼용 허용

## 검사

PR 전에 `test/run-integration-test.sh` 를 실행합니다. 개별 린트:
`test/lint-conventions.sh`, `test/test-preambles.sh`, `test/test-skill-refs.sh`, `test/test-command-style.sh`, `test/test-no-home-paths.sh`, `test/run-golden.sh`, `node test/test-*.mjs`

## 이슈 제보

- 버그: GitHub Issues에서 버그 리포트
- 기능 제안: GitHub Issues에서 Feature Request
- 질문: GitHub Discussions

## 코드 스타일

- bash 스크립트: `set -euo pipefail`
- YAML: 2칸 들여쓰기
- Markdown: 한 줄 비우기로 문단 구분
