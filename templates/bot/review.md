## 이관된 원문 (review)

봇 환경에서만 적용되는 옛 지시문(v0.3.0)을 참고용으로 보존한다. 상단 §1~§4 규칙이 우선한다.

> 2. **파일 영속화** — 이 산출물에 한해 **Bash 파일 쓰기를 허용**합니다(allowed-tools에 Write를 추가하지 않고, resume/cover-letter #118b와 동일한 **File output protocol**을 따릅니다). 질문 세트를 소실 없이 남기기 위해:
>    - **런 디렉토리 환경(jobclaw)**: Bash heredoc으로 `runs/$JOBCLAW_RUN_ID/output/source.md`에 작성 후 `[OUTPUT_FILE: ...]` 마커를 출력합니다.
>    - **독립 CLI 환경(런 디렉토리 없음)**: Bash heredoc으로 현재 디렉토리에 `면접예상질문-{기업명}.md`로 저장한 뒤 아래 결과물 뷰어를 안내합니다.
