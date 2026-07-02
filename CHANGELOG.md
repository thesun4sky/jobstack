# Changelog

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
