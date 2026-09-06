# 봇(jobclaw) 출력 프로토콜 — JOBSTACK_RUNTIME=bot 일 때만 주입

이 블록은 실행 컨텍스트의 `JOBSTACK_RUNTIME`이 `bot`일 때(텔레그램 봇 jobclaw 러너, `JOBCLAW_RUN_ID` 존재)만 스킬 프롬프트에 주입된다. CLI(Claude Code)에서는 주입되지 않으며, CLI 사용자에게는 아래 마커·블록을 출력하지 않는다.

## 1. 링크 표기

- 모든 URL은 `https://`를 포함한 전체 URL로 출력한다. Telegram은 스킴이 없으면 링크로 인식하지 않는다.
  - 잘못된 예: `→ jobkorea.co.kr/Recruit/GI_Read/12345`
  - 올바른 예: `→ https://jobkorea.co.kr/Recruit/GI_Read/12345`

## 2. [CHOICES] 블록

- 선택지를 제시하는 응답은 **맨 마지막**에 `[CHOICES]` 블록을 한 번만 포함한다. 중간에 끼워 넣거나 생략하면 봇이 인라인 버튼을 만들지 못한다.
- AskUserQuestion 구조(현재 상황 → 질문 → 추천 → 선택지)는 그대로 지키되, 선택지는 `[CHOICES]` 블록으로 다시 나열한다.

## 3. 파일 출력 (File output protocol)

- 문서 스킬(resume·cover-letter·career-history·review)이 최종본을 산출하면, 워크스페이스 CLAUDE.md의 File output protocol에 따라 `runs/$JOBCLAW_RUN_ID/output/source.md`에 Bash heredoc으로 쓰고 `[OUTPUT_FILE: runs/$JOBCLAW_RUN_ID/output/source.md]` 마커를 출력한다. `render-docx.sh`가 .docx로 변환한다.
- 사용자가 "파일로 줘"라고 말하지 않아도 완료(DONE) 시점에 자동으로 산출한다. 채팅 가독성이 낮은 긴 결과물은 파일이 기본이다.
- 산출 직전 placeholder 스캔(`[… 입력 필요]`, `[… 확인 필요]`, `[추정]`)에서 잔존 항목이 있으면 파일을 내지 않고 완료 상태를 DONE_WITH_CONCERNS로 강등한 뒤 항목을 사용자에게 고지한다(CLI의 `jobstack-export` exit 4와 같은 규칙).
- 봇 환경에서는 `jobstack-view`·`jobstack-export` 실행 안내를 출력하지 않는다(사용자가 실행할 수 없는 CLI 명령이다).

## 4. 시각화 이미지 마커

- 아래에 "시각화 이미지 생성" 규칙이 붙어 있는 스킬은 조건을 충족하는 응답의 **맨 끝 줄**에 `[IMAGE_PROMPT: <영어 프롬프트>]`를 한 번 출력한다. 규칙이 없는 스킬은 출력하지 않는다.

---

## 이관된 원문 (review)

봇 환경에서만 적용되는 옛 지시문(v0.3.0)을 참고용으로 보존한다. 상단 §1~§4 규칙이 우선한다.

> 2. **파일 영속화** — 이 산출물에 한해 **Bash 파일 쓰기를 허용**합니다(allowed-tools에 Write를 추가하지 않고, resume/cover-letter #118b와 동일한 **File output protocol**을 따릅니다). 질문 세트를 소실 없이 남기기 위해:
>    - **런 디렉토리 환경(jobclaw)**: Bash heredoc으로 `runs/$JOBCLAW_RUN_ID/output/source.md`에 작성 후 `[OUTPUT_FILE: ...]` 마커를 출력합니다.
>    - **독립 CLI 환경(런 디렉토리 없음)**: Bash heredoc으로 현재 디렉토리에 `면접예상질문-{기업명}.md`로 저장한 뒤 아래 결과물 뷰어를 안내합니다.
