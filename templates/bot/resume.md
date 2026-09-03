## 이관된 원문 (resume)

봇 환경에서만 적용되는 옛 지시문(v0.3.0)을 참고용으로 보존한다. 상단 §1~§4 규칙이 우선한다.

> > **완결 시 .docx 자동 산출 (#118b)**: 이력서 작성/첨삭이 **완료(DONE)** 되면, 사용자가 "파일로 줘"라고 말하지 않아도 최종본을 워크스페이스 CLAUDE.md 의 **File output protocol**(`runs/$JOBCLAW_RUN_ID/output/source.md` 작성 → `[OUTPUT_FILE: ...]` 마커 + `render-docx.sh`)로 **.docx 자동 emit** 하세요. 채팅 가독성이 낮은 긴 결과물은 파일이 기본입니다.
> > **독립 CLI 실행 폴백**: `render-docx.sh`가 없는(jobclaw 워크스페이스 밖) 환경에서는 `${CLAUDE_SKILL_DIR}/../bin/jobstack-export`로 md→docx 변환을 시도합니다. jobstack-export는 placeholder 잔존을 먼저 검사하므로, **exit 4(미확인 placeholder)면 마크다운 폴백을 주지 말고** 출력된 항목을 사용자에게 채우도록 요청한 뒤 재시도합니다. pandoc 미설치(exit 2)일 때만 마크다운/HTML로 산출하고 변환 방법을 안내합니다.
