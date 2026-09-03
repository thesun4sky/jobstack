# jobstack

**한국 취업 통합 엑셀러레이터** — Claude Code 스킬 시스템

4년간 60건+ 자소서 첨삭에서 검증된 방법론을 AI 코칭으로 제공합니다.
기업분석부터 이력서, 자소서, 모의면접까지 취업 준비 전 과정을 통합 지원합니다.

---

## 핵심 철학

> **자소서는 일기장이 아니라 메뉴판이다.** 하소연이 아니라, 면접관이 맛보고 싶어하는 것을 차려놓아야 한다.

- **"결이요" 프레임워크** — 결론(5초) → 이유(수치) → 요청(비전)
- **미끼 전략** — 면접관이 물어보고 싶어할 포인트를 자소서에 배치하고 답변 준비
- **"이미 팀원처럼"** — 지원 팀의 제품/리뷰/업데이트를 분석하여 팀원처럼 대화
- **"바로 써보고 싶은 사람"** — 학생이 아닌, 당장 투입 가능한 실무자로 포지셔닝

---

## 전체 워크플로우

```mermaid
flowchart TB
    Start(["/auto 실행"]):::start --> Scan["파일 스캔<br/>이력서/자소서/채용공고/포트폴리오"]:::scan

    Scan --> |"파일 없음"| Strategy["/strategy<br/>취업전략 수립"]:::tier1
    Scan --> |"이력서 감지"| Resume["/resume<br/>이력서 첨삭"]:::tier3
    Scan --> |"자소서 감지"| CoverLetter["/cover_letter<br/>자소서 첨삭"]:::tier3
    Scan --> |"채용공고 감지"| CompanyResearch["/company_research<br/>기업분석"]:::tier2
    Scan --> |"포트폴리오 감지"| Portfolio["/portfolio<br/>포트폴리오 리뷰"]:::tier2

    Strategy --> |"프로필 생성"| Profile[(프로필)]
    Profile --> CompanyResearch
    Profile --> JobSearch["/job_search<br/>채용정보 탐색"]:::tier2
    Profile --> NCS["NCS 역량 매핑<br/>(공기업: /cover_letter 보강)"]:::tier2

    CompanyResearch --> Resume
    CompanyResearch --> CoverLetter
    CompanyResearch --> Salary["/salary<br/>연봉 분석"]:::tier2

    NCS --> CoverLetter
    Resume --> Review["/review<br/>통합 서류 리뷰"]:::tier4
    CoverLetter --> Review
    Portfolio --> Review

    Review --> |"서류 통과"| MockInterview["/mock_interview<br/>모의면접"]:::tier4
    Review --> Tracker["/track · /myapps<br/>지원 현황 관리"]:::tier1

    MockInterview --> |"인성면접"| MI1["인성면접<br/>시뮬레이션"]
    MockInterview --> |"PT면접"| MI2["PT면접<br/>연습"]
    MockInterview --> |"토론면접"| MI3["토론면접<br/>시뮬레이션"]
    MockInterview --> |"기술면접"| MI4["기술면접"]
    MockInterview --> |"AI면접"| MI5["AI면접<br/>대비"]

    MI1 & MI2 & MI3 & MI4 & MI5 --> Retro["/retro<br/>회고/개선"]:::retro
    Retro -.-> |"피드백 반영"| Strategy

    classDef start fill:#4CAF50,color:#fff,stroke:#388E3C
    classDef scan fill:#2196F3,color:#fff,stroke:#1976D2
    classDef tier1 fill:#E8F5E9,stroke:#4CAF50
    classDef tier2 fill:#E3F2FD,stroke:#2196F3
    classDef tier3 fill:#FFF3E0,stroke:#FF9800
    classDef tier4 fill:#F3E5F5,stroke:#9C27B0
    classDef retro fill:#FBE9E7,stroke:#F44336
```

## 단계별 가이드

```mermaid
graph LR
    A["1단계<br/>전략 수립<br/>/strategy"]:::s1 --> B["2단계<br/>기업분석<br/>/company_research"]:::s2
    B --> C["3단계<br/>서류 작성<br/>/resume<br/>/cover_letter"]:::s3
    C --> D["4단계<br/>통합 리뷰<br/>/review"]:::s4
    D --> E["5단계<br/>면접 준비<br/>/mock_interview"]:::s5
    E --> F["6단계<br/>지원/추적<br/>/track · /myapps"]:::s6
    F --> G["7단계<br/>회고/개선<br/>/retro"]:::s7
    G -.-> |"피드백 루프"| A

    classDef s1 fill:#E8F5E9,stroke:#4CAF50
    classDef s2 fill:#E3F2FD,stroke:#2196F3
    classDef s3 fill:#FFF3E0,stroke:#FF9800
    classDef s4 fill:#FCE4EC,stroke:#E91E63
    classDef s5 fill:#F3E5F5,stroke:#9C27B0
    classDef s6 fill:#E0F7FA,stroke:#00BCD4
    classDef s7 fill:#FBE9E7,stroke:#F44336
```

---

## 설치

```bash
git clone https://github.com/thesun4sky/jobstack.git
cd jobstack
./install.sh
```

설치 후 Claude Code에서 `/auto`를 입력하면 자동으로 시작됩니다.

플러그인으로 설치하려면(Claude Code 2.1 이상, 저장소가 곧 마켓플레이스):

```
/plugin marketplace add thesun4sky/jobstack
/plugin install jobstack@jobstack
```

플러그인 설치에서는 스킬을 `/jobstack:auto`처럼 네임스페이스로 호출하고, `claude plugin update jobstack`으로 갱신합니다. Node 의존성은 첫 `/jobstack:job_search` 실행 시 플러그인 데이터 디렉토리(`${CLAUDE_PLUGIN_DATA}`)에 설치돼 플러그인 갱신 후에도 유지됩니다.

- 스킬은 Claude Code 표준 위치 `~/.claude/skills/`에 심링크됩니다 (v0.3까지 쓰던 `~/.claude/commands/` 심링크는 설치 시 자동 정리). 저장소를 `git pull`하면 바로 반영됩니다.
- 옵션: `./install.sh --with-insane-search` (차단 사이트 수집 어댑터, Python 3.10+), `./install.sh --prefix` (스킬명에 `jobstack-` 접두어)
- 매일 자동으로 새 공고·마감 임박·정체 지원 건을 확인하려면 `bin/jobstack-cron install`(로컬 cron/launchd, `~/.jobstack/job-cache/daily-YYYY-MM-DD.md` 생성). 컴퓨터를 꺼두는 시간이 길면 클라우드 Routines 가이드 [docs/routines.md](docs/routines.md).
- claude.ai / Cowork 에서 쓰려면 `bin/package-skill.sh all` 로 스킬별 zip 을 만들어 업로드합니다 — 상태 저장·수집 스크립트가 없는 축소 모드로 동작합니다([docs/cowork.md](docs/cowork.md)).

---

## 결과물 뷰어

모든 스킬의 결과물은 Markdown으로 저장됩니다. 내장 뷰어로 브라우저에서 보기 좋게 확인할 수 있습니다:

```bash
jobstack-view 자소서-첨삭결과.md    # 브라우저에서 열기
jobstack-view 기업분석-삼성전자.md  # 스타일링된 HTML로 변환
```

- Noto Sans KR 한국어 최적화 타이포그래피
- 다크모드 자동 지원
- 테이블, 코드블록, 인용문 등 완벽 렌더링
- **"PDF 저장" 버튼**으로 즉시 PDF 변환 (브라우저 인쇄 기능)
- 모바일 반응형 지원

---

## 스킬 목록

| 스킬 | 설명 | Tier |
|------|------|------|
| `/auto` | 파일 자동 감지 + 단계별 가이드 (진입점) | 1 |
| `/strategy` | 역량 진단 + 취업전략 + 로드맵 생성 | 1 |
| `tracker/` (CLI 전용) | 지원 현황 추적 + 일정 관리 — 봇에서는 네이티브 `/track`·`/myapps` | 1 |
| `/company_research` | 7가지 키워드 소스 기업분석 + 적합도 스코어링 | 2 |
| `/job_search` | 사람인/잡코리아/원티드 채용공고 탐색 | 2 |
| `ncs/` (CLI 전용) | NCS 역량 매핑 + 경험→역량 변환 — 봇에서는 `/cover_letter`의 공기업 NCS 보강 | 2 |
| `/salary` | 연봉 벤치마크 + 협상 전략 | 2 |
| `/portfolio` | 포트폴리오 최적화 + 임팩트 표현 (GitHub 레포·README) | 2 |
| `/retro` | 면접 회고 + 탈락 원인 분석 + 개선 | 2 |
| `/experience_bank` | 경험 소재 발굴·카드화 (자소서·이력서 소재 은행) | 2 |
| `/resume` | 이력서 작성/첨삭 + ATS 최적화 | 3 |
| `/cover_letter` | 자소서 작성/첨삭 ("결이요" + 5단계 첨삭) | 3 |
| `/career_history` | 경력기술서 작성/첨삭 (경력직·중고신입) | 3 |
| `/scout_profile` | 링크드인/원티드/리멤버 프로필 첨삭 | 3 |
| `/mock_interview` | 모의면접 7가지 모드 (인성/PT/토론/AI역량검사/기술/임원/컬처핏) | 4 |
| `/review` | 이력서↔자소서↔포트폴리오↔프로필 통합 점검 | 4 |

> 명령 표기는 Telegram 봇 노출 기준(언더스코어)입니다. 스킬 디렉토리명은 하이픈을
> 유지합니다 (예: `company-research/`, `cover-letter/`, `mock-interview/`, `job-search/`).

---

## 사용 예시

### 초보자: `/auto`로 시작

이력서 파일이 있는 폴더에서 `/auto`를 실행하면:

```
╔══════════════════════════════════════════╗
║  jobstack 취업 준비 현황                   ║
╠══════════════════════════════════════════╣
║  [x] 프로필 — 이력서에서 자동 생성         ║
║  [x] 이력서 — resume.pdf 감지             ║
║  [ ] 이력서 첨삭 ← 추천 다음 단계          ║
║  [ ] 자기소개서                            ║
║  [ ] 모의면접                              ║
╚══════════════════════════════════════════╝
```

### 자소서 첨삭: 5단계 진단

```
자소서 진단 결과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
① 희망·의지형 종결어미    발견 [5건]  ⚠️
② 감정·감상 과다          발견 [3건]  ⚠️
③ 추상적 성과             발견 [4건]  ⚠️
④ 시간순 나열             발견       ⚠️
⑤ 기업 연구 부족          발견       ⚠️
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
진단 점수: 40/100
```

### 기업 키워드 체크리스트

```
기업 키워드 체크리스트: 삼성전자 - SW엔지니어
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
소스          키워드              반영
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
채용공고      Python              O
채용공고      AWS                 X
CEO 신년사    AI 전환              O
인재상        도전정신             O
최신기사      반도체 투자확대       O
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
반영률: 15/20 (75%) → 목표: 85%+
```

---

## 60건+ 첨삭 인사이트

jobstack은 4년간 60건 이상의 자소서 첨삭에서 추출된 실전 인사이트를 기반으로 합니다.

### 8대 원칙

1. **"바로 써보고 싶은 사람"** — 학습자가 아닌 즉시 투입 가능한 실무자
2. **"과장 없이, 그러나 강하게"** — 거짓 없이 임팩트 있게
3. **"5초 규칙"** — 첫 문장이 승부
4. **"수치가 없으면 성과가 아니다"** — before→after 필수
5. **"자소서는 설득 문서"** — 감정보다 논리
6. **"약점은 인정하되 역량을 보여줘라"**
7. **"기업 연구는 체계적으로"** — 7가지 소스 키워드 체크리스트
8. **"면접까지 일관된 스토리"** — 자소서 미끼 → 면접 답변

### 3가지 어조 전환 공식

| Before | After |
|--------|-------|
| "~하고 싶습니다" | "~하고 있습니다" |
| "흥미를 느꼈습니다" | 구체적 프로젝트/성과 서술 |
| "밤새 공부했습니다" | "XX% 성능 개선 달성" |

자세한 내용은 [ETHOS.md](ETHOS.md)를 참고하세요.

---

## E2E 통합 테스트

현재 동작의 근거는 헤드리스 스킬 eval 실측입니다 — `test/run-evals.sh` 로 15케이스(gate·periodic·e2e)를 돌린 결과와 모델 비교표는 [docs/E2E-TEST-REPORT.md](docs/E2E-TEST-REPORT.md) 상단에 있습니다(gate 5/5). 아래는 v0.3 시점에 샘플 데이터(이력서 + 자소서 + 채용공고)로 전체 8단계 플로우를 돌린 서사 기록입니다.

> **페르소나**: 김민수 (신입 백엔드 개발자, 서울과기대 컴공, 인턴 6개월)
> **목표**: 네이버 서버 플랫폼 개발자

### 전체 플로우 요약

```mermaid
flowchart LR
    subgraph 입력["입력 3건"]
        IN1["이력서_김민수.md"]
        IN2["채용공고_네이버.md"]
        IN3["자소서_네이버.md"]
    end

    S1["/auto<br/>3건 감지<br/>프로필 생성"]
    S2["/strategy<br/>GAP 분석<br/>12주 로드맵"]
    S3["/company_research<br/>키워드 14%<br/>적합도 58점"]
    S4["/resume<br/>ATS 53%<br/>수치화 6건"]
    S5["/cover_letter<br/>38점→결이요<br/>미끼 5개"]
    S6["/review<br/>체크 12/20<br/>질문 32개"]
    S7["/mock_interview<br/>인성 5문<br/>66/100점"]
    S8["/retro<br/>회고+액션플랜"]

    입력 --> S1 --> S2 --> S3 --> S4 --> S5 --> S6 --> S7 --> S8
    S8 -.-> |"피드백 루프"| S2

    style S5 fill:#FCE4EC,stroke:#E91E63
    style S7 fill:#F3E5F5,stroke:#9C27B0
```

### 단계별 핵심 입출력

| Step | 스킬 | 입력 | 핵심 출력 | 크기 |
|------|------|------|----------|------|
| 1 | `/auto` | 폴더 파일 3건 | [대시보드](docs/e2e-output/step1-auto-대시보드.md) — 감지 결과 + 체크리스트 | 2.6KB |
| 2 | `/strategy` | 이력서 → 프로필 추출 | [프로필](docs/e2e-output/step2-strategy-프로필.yaml) + [로드맵](docs/e2e-output/step2-strategy-로드맵.md) | 8.5KB |
| 3 | `/company_research` | 채용공고 + WebSearch | [네이버 기업분석](docs/e2e-output/step3-company-research-네이버.md) — 키워드 반영률 14% | 9.8KB |
| 4 | `/resume` | 이력서 + 채용공고 | [이력서 첨삭](docs/e2e-output/step4-resume-첨삭결과.md) — 수치화 before/after 6건 | 13KB |
| 5 | `/cover_letter` | 자소서 + 기업분석 | [자소서 5단계 첨삭](docs/e2e-output/step5-cover-letter-첨삭결과.md) — 진단 38점, 미끼 5개 | **25.6KB** |
| 6 | `/review` | 이력서+자소서+채용공고 | [통합 점검](docs/e2e-output/step6-review-통합점검.md) — 면접 질문 32개 | 13.4KB |
| 7 | `/mock_interview` | 자소서 미끼 + 프로필 | [인성면접 5문](docs/e2e-output/step7-mock-interview-인성면접.md) — 66/100점 | 18.5KB |
| 8 | `tracker/` + `/retro` | 면접 결과 | [현황](docs/e2e-output/step8-tracker-현황.md) + [회고](docs/e2e-output/step8-retro-회고.md) | 11.5KB |
| | | | **총 출력** | **103KB** |

### 자소서 변환 추적 (Before → After)

**지원동기 원문**:
> "네이버는 대한민국을 대표하는 IT 기업이며...서버 개발에 **흥미를 느꼈고**...네이버에서 더 **성장하고 싶습니다**"

**결이요 적용 후**:
> "플러스테크 인턴 기간에 Redis 캐싱을 적용해 주요 API 응답시간을 **350ms에서 15ms로 단축**한 경험이 있습니다...네이버 **Search Platform이 일 수억 건의 검색 요청을 MSA 기반으로 처리**한다는...네이버 검색 백엔드의 응답 속도와 안정성 개선에 **즉시 기여하겠습니다**"

**전체 상세 리포트**: [docs/E2E-TEST-REPORT.md](docs/E2E-TEST-REPORT.md)

> 각 단계의 실제 출력물 전문은 [docs/e2e-output/](docs/e2e-output/) 디렉토리에서 확인할 수 있습니다.

---

## 아키텍처

[gstack](https://github.com/garrytan/gstack)의 아키텍처를 차용했습니다.

- **Markdown 스킬 + 얇은 스크립트** — 코칭 로직은 프롬프트(SKILL.md), 수집·변환·판정처럼 결정적인 일은 `bin/`의 bash·Node·Python 스크립트가 맡습니다
- **YAML 프론트매터** — 스킬 메타데이터 정의
- **동적 주입 프리앰블** — 스킬 로드 시점에 `bin/jobstack-preamble`가 실행 컨텍스트(프로필·기준일·런타임)와 공유 가드레일을 프롬프트에 넣습니다 ([templates/preamble.md](templates/preamble.md))
- **파일 기반 상태관리** — `~/.jobstack/`에 YAML/JSONL
- **로컬 사용 기록** — 스킬 사용 이벤트가 `~/.jobstack/analytics/`에 로컬 파일로만 기록됩니다 (네트워크 전송 없음, 문서 내용·개인정보 미포함 — [규격](docs/telemetry-events.md))
- **결정적 스크립트 계층** — 지원 현황(`jobstack-tracker`)·경험 카드(`jobstack-exp.mjs`)·방어맵(`jobstack-defense-map.mjs`)·키워드 매칭률(`jobstack-ats-match`)·회고 집계(`jobstack-retro-stats`)는 스크립트가 저장·계산하고 스킬은 해석·코칭만 합니다 (같은 입력 → 같은 결과)
- **진행적 공개** — SKILL.md 는 300줄 이하의 흐름·게이트만 담고, 모드별·플랫폼별·트랙별 자료는 `references/`에서 필요한 시점에만 읽습니다
- **병렬 리서치 서브에이전트** — `agents/researcher.md`가 기업분석·연봉·전략의 웹 조사를 소스별로 나눠 맡고 출처 URL·기준일이 붙은 JSON만 돌려줍니다
- **스킬 eval** — `evals/<skill>/evals.json` 케이스를 `test/run-evals.sh`가 `claude -p` 헤드리스로 실행해 산출물·스크립트 호출·참조 읽기를 판정합니다(결정적 gate / LLM 채점 periodic / e2e 3계층, [docs/evals.md](docs/evals.md))
- **운영 학습 로그** — 수집 셀렉터 깨짐·차단·반복 자료 요청 같은 운영 메타만 `~/.jobstack/analytics/learnings.jsonl`에 남기고 `/auto` 대시보드가 상위 3건을 보여줍니다(문서 내용·개인정보 미기록)
- **모델·effort 라우팅** — 명령 감지 위주인 tracker 는 `model: sonnet`·`effort: low`, 문서 첨삭·면접·기업분석 스킬은 `effort: high` 를 프론트매터로 선언합니다
- **의존성** — 기본 기능은 bash + python3. 선택: `job_search` 수집은 Node 22+ (`cd bin && npm install` — Playwright·cheerio·docx·yaml, 첫 실행 시 자동), 사람인은 브라우저 없이 동작하고 사람인 오픈API 키(`jobstack-config set saramin_api_key …`)가 있으면 API 를 먼저 씁니다. 차단 사이트 수집은 `--with-insane-search`(Python 3.10+, curl_cffi). .docx 내보내기는 pandoc 3.6+ 또는 Node `docx` 폴백. 한글 `.hwpx`는 추가 설치 없이, `.hwp`는 kordoc/rhwp 가 있을 때 변환
- **스킬 체이닝** — `benefits-from`으로 스킬 간 의존성 정의

```
jobstack/
├── auto/SKILL.md           # 자동 감지 (진입점)
├── strategy/SKILL.md       # 전략 수립
├── company-research/       # 기업분석
├── resume/                 # 이력서
├── cover-letter/           # 자소서
├── mock-interview/         # 모의면접
├── ...
├── <skill>/references/     # 스킬별 참조 자료 (생성 복제본 + 스킬 소유)
├── agents/researcher.md    # 리서치 서브에이전트
├── bin/                    # 결정적 스크립트 (tracker·exp·defense-map·ats-match·fetch-jobs·export·cron·learn …)
├── evals/                  # 스킬 eval 케이스 (test/run-evals.sh)
├── .claude-plugin/         # 플러그인·마켓플레이스 매니페스트
├── templates/, docs/       # 공유 템플릿·계약 문서 (references/ 의 원본)
└── install.sh              # 심링크 설치 스크립트
```

---

## 기여하기

기여를 환영합니다! [CONTRIBUTING.md](CONTRIBUTING.md)를 참고하세요.

## 라이선스

[MIT](LICENSE)
