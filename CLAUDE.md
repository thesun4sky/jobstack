# jobstack 개발 가이드

## 구조

- 각 스킬은 `{skill-name}/SKILL.md` 파일로 정의
- YAML 프론트매터: `name`, `preamble-tier`, `version`, `description`, `allowed-tools`, `benefits-from`
- 공유 템플릿: `templates/` 디렉토리 (preamble, voice, ask-user-question, completion-status)
- 상태 관리: `~/.jobstack/` (YAML/JSONL/Markdown)
- 설정 관리: `bin/jobstack-config` (get/set/list)

## preamble-tier

| Tier | 용도 | 스킬 |
|------|------|------|
| 1 | 진입점, 항상 사용 가능 | auto, strategy, tracker |
| 2 | 분석/조사 | company-research, portfolio, job-search, ncs, salary, retro |
| 3 | 문서 작성 | resume, cover-letter |
| 4 | 복합 대화형 | mock-interview, review |

## 스킬 추가 방법

1. `{skill-name}/` 디렉토리 생성
2. `SKILL.md` 작성 (YAML 프론트매터 포함)
3. `install.sh` 실행하여 심링크 생성

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
