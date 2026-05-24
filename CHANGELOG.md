# Changelog

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
