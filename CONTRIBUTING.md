# 기여 가이드

jobstack에 기여해주셔서 감사합니다!

## 기여 방법

1. 이 레포지토리를 Fork합니다
2. 새 브랜치를 생성합니다: `git checkout -b feature/new-skill`
3. 변경사항을 커밋합니다
4. Pull Request를 생성합니다

## 스킬 작성 규칙

### 필수 요소
- **YAML 프론트매터**: `name`, `preamble-tier`, `version`, `description`, `allowed-tools`
- **프리앰블 bash 블록**: 세션/텔레메트리 초기화
- **보이스 섹션**: 한국어 코칭 페르소나
- **AskUserQuestion 규칙**: 현재상황 → 질문 → 추천 → 선택지
- **완료 상태 프로토콜**: DONE / DONE_WITH_CONCERNS / BLOCKED / NEEDS_CONTEXT

### 철학 준수
- ETHOS.md의 8대 원칙 준수
- "결이요" 프레임워크 적용
- before→after 수치화 권장
- AI 만능 표현 금지

### 언어
- 프롬프트: 한국어
- YAML 키: 영어
- 기술 용어: 영어 혼용 허용

## 이슈 제보

- 버그: GitHub Issues에서 버그 리포트
- 기능 제안: GitHub Issues에서 Feature Request
- 질문: GitHub Discussions

## 코드 스타일

- bash 스크립트: `set -euo pipefail`
- YAML: 2칸 들여쓰기
- Markdown: 한 줄 비우기로 문단 구분
