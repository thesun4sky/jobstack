# JobStack CLI → 웹 SaaS 아키텍처 초안

**문서 목적**: Claude Code용 Markdown 스킬(13개) 기반 JobStack을 **Next.js/React 웹앱 + API** SaaS로 옮기기 위한 **아키텍처 초안**을 한 파일에서 요약한다.  
**대상 독자**: [JobStack리더](/TSK/agents/jobstack-2) 검토 → [CEO](/TSK/agents/ceo) 제안.  
**상세·보조**: 기술 통합본은 [WEB_SAAS_ARCHITECTURE.md](./WEB_SAAS_ARCHITECTURE.md), API·ERD 스켈레톤은 [saas-phase2-erd-openapi.md](./saas-phase2-erd-openapi.md), 빠른 기술 요약은 [saas-architecture.md](./saas-architecture.md).

**관련 인프라 이슈**: [TSK-708](/TSK/issues/TSK-708) · 자식 [TSK-866](/TSK/issues/TSK-866) (Vercel 계정 액션 대기 시 배포 게이트).

---

## 1. 현재 상태 (CLI)

| 구분 | 내용 |
|------|------|
| **스킬** | 저장소 루트에 13개 디렉터리, 각 `{skill-name}/SKILL.md` — YAML frontmatter(`name`, `description`, `allowed-tools` 등) + 한국어 본문 |
| **스킬 키** | `auto`, `strategy`, `company-research`, `job-search`, `ncs`, `salary`, `portfolio`, `tracker`, `resume`, `cover-letter`, `review`, `mock-interview`, `retro` |
| **로컬 상태** | `~/.jobstack/` — `profiles/`, `tracker/applications.jsonl`, `company-cache/`, `interview-history/`, `analytics/`, `sessions/`, `config.yaml` 등 파일·디렉터리 기반 |
| **뷰어** | `bin/jobstack-view` — 로컬 `.md`를 HTML로 변환해 브라우저 표시(marked CDN), 인쇄/PDF 용도. 웹 SaaS에서는 **문서 목록·미리보기 UI**로 대체 |

CLI는 단일 사용자·단일 머신 전제이며, 스킬 실행은 에이전트(Claude Code)와 셸 도구에 가깝게 묶여 있다.

---

## 2. 목표 (웹 SaaS)

| 영역 | 방향 |
|------|------|
| **사용자별 상태** | `~/.jobstack/` 내용을 **PostgreSQL**로 이전 — 프로필·지원·연구 아티팩트·면접·사용량을 테넌트(사용자) 단위로 격리. 상세 매핑은 [saas-architecture.md](./saas-architecture.md) §5 및 [saas-phase2-erd-openapi.md](./saas-phase2-erd-openapi.md) |
| **인증** | OAuth(예: Google) + 이메일(매직 링크 등) — NextAuth Route Handler(`app/api/auth/[...nextauth]/`), 세션은 httpOnly 쿠키 + 서버 저장소 |
| **구독·결제** | **Stripe 또는 PortOne** — 클라이언트에서 결제 UI, **웹훅으로만** 구독 상태 확정. **현재 Phase 1에 PortOne 웹훅(`app/api/webhooks/portone/`)·`subscriptions` 테이블·플랜 헬퍼가 이미 구현되어 있다.** Phase 3에서 `usage_events`·쿼터 기반 API·스킬 실행 게이팅을 완성 |

---

## 3. 스킬 실행 엔진 (개념)

Markdown 프롬프트를 **서버 권위의 실행 템플릿**으로 둔다.

1. **레지스트리**: `skill_key` → 버전된 `SKILL.md` 본문.
2. **컨텍스트 조립**: DB의 프로필·문서·지원 정보를 CLI의 파일 경로 대신 **주입 변수**로 연결.
3. **HTTP 경계**: 동기로 끝나지 않는 작업은 `202 Accepted` + `jobId`, 진행은 `job` / `job_event` 스트림(이미 `GET/POST /api/v1/jobs` 패턴 존재).
4. **도구 정책**: YAML `allowed-tools`와 서버 허용 목록 교차 검증 — 웹에서는 셸 대신 **제한된 API**만 노출.

즉, “스킬 = Markdown 가이드”이면서 “스킬 = 서버 오케스트레이션 단위”인 이중 역할을 유지하되, **버전과 감사 로그는 서버**가 관리한다.

---

## 4. Phase 로드맵 (제품 메모 기준 매핑)

아래 Phase 번호는 리더 플랜([TSK-822](/TSK/issues/TSK-822) 등)과 같은 축을 쓴다. 기술 산출물 상세 표는 [saas-architecture.md](./saas-architecture.md) §1·[WEB_SAAS_ARCHITECTURE.md](./WEB_SAAS_ARCHITECTURE.md) §0을 본다.

| Phase | 초점 | 기술적으로의 의미 |
|-------|------|-------------------|
| **1** | 웹 뼈대, 인증, 스킬 1~2개 **수직 슬라이스** | `apps/web`(Next.js), BFF Route Handlers, Job API 형태 구현 (실행은 in-process MVP — 내구성 보장 없음) |
| **2** | 나머지 스킬 포팅, 상태 DB화, `jobstack-view` 웹 대체 | 13 스킬 레지스트리·워커, 문서/트래커 UI, ERD·REST 정식화 |
| **3** | 플랜 게이팅·쿼터 완성 | usage_events, 쿼터 검증, API 실행 제한 (PortOne MVP는 Phase 1에 이미 존재) |
| **4** | SEO·커뮤니티·레퍼럴 등 | 제품 확정 후 범위 |

**배포 전제**: Vercel Root `apps/web`, 모노레포 Turbo 빌드 — [vercel-monorepo.md](./vercel-monorepo.md). 계정/환경 변수 미비 시 스테이징 공개가 막힐 수 있음([TSK-866](/TSK/issues/TSK-866)).

---

## 5. 산출물·다음 액션

- 본 파일은 **의사결정·전달용 초안**이다. DDL·OpenAPI 전문은 Phase 2 문서·코드에서 확정한다.
- 구현 저장소의 웹·API·DB 패키지 레이아웃은 [WEB_SAAS_ARCHITECTURE.md](./WEB_SAAS_ARCHITECTURE.md) §1.1을 따른다.

*Paperclip: [TSK-977](/TSK/issues/TSK-977) 산출물 — `docs/web-saas-architecture.md`.*
