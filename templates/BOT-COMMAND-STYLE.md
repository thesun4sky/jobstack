# 봇 명령 표기 규칙 (BOT COMMAND STYLE)

jobstack 스킬은 Telegram 봇(jobclaw)에서 헤드리스로 실행됩니다. Telegram 명령은
하이픈을 지원하지 않으므로(탭 불가), **사용자에게 출력되는 추천 명령은 반드시
Telegram 언더스코어 표기**를 씁니다.

## 규칙

1. **사용자 노출 추천 명령 = 언더스코어 표기**
   - `/cover_letter`, `/mock_interview`, `/company_research`, `/job_search`
   - 하이픈 표기(`/cover-letter`, `/mock-interview`, …)는 봇에서 탭조차 안 되므로
     "다음 추천", 완료 상태, 안내 문구 등 사용자에게 보이는 텍스트에 쓰지 않습니다.
   - 단어 하나짜리 명령(`/resume`, `/review`, `/retro`, `/strategy`, `/salary`,
     `/portfolio`)은 표기가 동일합니다.

2. **봇 미노출 스킬은 추천하지 않는다**
   - `/tracker` — 봇에서는 네이티브 명령 `/track`·`/myapps`로 일원화. 지원 현황
     관리를 안내할 때는 `/track`·`/myapps`를 추천합니다. (tracker 스킬 자체는
     CLI 용도로 잔존)
   - `/ncs` — 봇 미노출. NCS 관점 보강은 cover-letter 스킬의
     "공기업·공공기관 지원인 경우" 소절이 흡수했으므로 `/cover_letter`를 추천합니다.

3. **스킬 내부 참조는 예외**
   - 디렉토리명·파일 경로·프론트매터(`benefits-from`)·리포트 풋터 버전 스탬프
     (`jobstack /mock-interview v0.1.0`) 등 사용자에게 "입력하라고 추천하는 명령"이
     아닌 내부 식별자는 기존 하이픈 표기를 유지합니다.
