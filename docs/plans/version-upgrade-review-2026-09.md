# jobstack 버전업 검토 보고서 (2026-09)

- **작성일**: 2026-09-03 · **기준 커밋**: `main @ a5ef5ed` (PR #16 insane-search Phase 1·2 머지 직후) · **VERSION**: 0.3.0
- **검토 환경**: Claude Code v2.1.259 (이 검토를 수행한 샌드박스에서 nested `claude -p` 실측 가능), Node 22.22, Python 3.11
- **검토 방법**
  1. 로컬 감사 — 16개 SKILL.md·templates·bin·test 전수 열람, 린트/단위 테스트 9종 실행, 프리앰블↔템플릿 diff, 참조 경로 집계
  2. 실측 4건 — 스킬 디스커버리 레이아웃, `${CLAUDE_SKILL_DIR}` 치환값, Read/Bash 경로 해석, 스킬 설명 절단 여부
  3. 웹 조사 4축 — Claude Code 생태계(공식 문서·CHANGELOG), 한국 채용시장·플랫폼, 의존성·참조 프로젝트(gstack·insane-search), Claude 플랫폼·Agent SDK
  4. 에이전트 리뷰 — 2차 스킬 8종(strategy·retro·salary·ncs·portfolio·experience-bank·career-history·scout-profile) 교차 검토 후 grep으로 재확인
- **표기**: `[사실]` 문서·코드로 확인 · `[실측]` 이 환경에서 재현 · `[추론]` 검토자 판단 · `[미확인]` 확인 못 함
- **선행 문서와의 관계**: `docs/plans/skill-upgrade-plan-2026-07.md`(126건 업그레이드, 기각 10건)와 `docs/plans/insane-search-통합-실행계획.md`는 완료·진행 중이므로 재상정하지 않는다. 이 문서는 그 이후 두 달간 바뀐 실행 환경(Claude Code 스킬 표준·플러그인·훅·서브에이전트·Routines)과 시장 변화에 맞춰 **다음 버전(v0.4~v1.0)에서 손볼 것**만 다룬다.

---

## 0. 결이요 요약

**결(론)** — jobstack은 방법론(ETHOS·결이요·가드레일)과 도메인 로직(원티드 마감 검증·is-fetch 어댑터·tracker 상태 모델)이 잘 쌓여 있지만, 실행 기반은 2026년 3월 Claude Code 관례(`~/.claude/commands` 심링크 + bash 프리앰블 + 거대 단일 SKILL.md)에 머물러 있다. 그 사이 Claude Code는 스킬을 1급 개념으로 표준화하고 플러그인·훅·서브에이전트·Routines를 정식 기능으로 올렸다. **가장 급한 것은 신기능 도입이 아니라, 현행 설치 방식에서 공유 가드레일이 실제로는 로드되지 않는 결함(§1-2 D-1)을 고치는 일**이다. 그 다음이 플러그인 패키징과 프롬프트 분할이다.

**이(유)** — 실측으로 확인한 사실 세 가지.
1. 심링크 설치에서 `${CLAUDE_SKILL_DIR}`은 심링크 경로로 치환되고, Claude의 Read 도구는 `../templates/…`를 어휘적으로 정규화해 "file does not exist"를 낸다. 16개 스킬의 템플릿·문서 참조 113곳이 CLI에서 전부 실패한다(Bash 경로는 정상). `[실측]`
2. 6개 스킬이 텔레그램 봇(jobclaw) 전용 마커(`[IMAGE_PROMPT:]`, `[CHOICES]`, `[OUTPUT_FILE:]`)를 CLI 사용자에게도 출력하도록 지시한다. `[사실]`
3. SKILL.md 16개 5,837줄 중 6개가 490줄 이상이고, 자소서 스킬 1회 호출은 약 48KB의 한국어 지시문을 매번 전량 로드한다. Claude Code 공식 가이드는 SKILL.md 500줄 이내와 참조 파일 분리(progressive disclosure)를 권한다. `[사실]`

**요(청)** — 3단계로 진행할 것을 제안한다. (1) **v0.4.0 결함 수정**: 템플릿 로드 경로·봇 마커 분리·뷰어 버그·교차 모순·CHANGELOG/CI (1~2일). (2) **v0.5.0 실행 기반 현대화 + 시장 정합**: 플러그인 패키징+마켓플레이스, 프리앰블 스크립트화(`!` 주입·훅), 6개 거대 스킬 분할, 결정적 스크립트 계층(tracker·experience·defense-map), 공식 API 우선 수집, hwpx 인제스트, NCS 개편·경험기술서형 전형 반영 (2~3주). (3) **v1.0 기능 확장**: 서브에이전트 병렬 리서치, Routines 기반 공고 모니터링, Claude in Chrome 경로, 스킬 eval 체계, 모델·effort 라우팅. 상세는 §3·§4. 시장 관련 근거는 이 샌드박스에서 원문 접근이 막혀 `[2차]`로 표시했으므로, 해당 스킬 본문을 바꾸기 전 원문 확인을 선행한다.

---

## 1. 현재 상태 진단

### 1-1. 규모·버전·테스트 `[사실]`

| 항목 | 값 |
|---|---|
| 스킬 수 / SKILL.md 총 줄수 | 16개 / 5,837줄 |
| 490줄 이상 스킬 | job-search 529, cover-letter 529, resume 523, mock-interview 496, company-research 493 (auto 355) |
| cover-letter 1회 호출 시 로드되는 지시문 | SKILL.md 33.1KB + guardrails 4.1KB + experience-methods 4.8KB + humanize-check 3.6KB + three-docs-guide 2.9KB ≈ 48.5KB |
| VERSION / CHANGELOG 최종 | 0.3.0 / 0.3.0 (2026-07-04) |
| CHANGELOG 이후 미기록 커밋 | 20건 (2026-07-13~07-20: PR #12 크롤러 진단, #13, #14 원티드 마감 검증, #16 is-fetch 어댑터). job-search SKILL은 이미 v0.5.0 |
| git tag | 0개 |
| 테스트 | 9종(프리앰블·표기·홈경로·컨벤션·골든·fetch-diag·wanted-verify·is-fetch 어댑터·SSRF) 로컬 전부 통과 |
| CI | 없음(`.github/` 부재). `run-integration-test.sh`는 실제 `$HOME/.claude/commands`와 상태 디렉토리를 변경하므로 CI에 그대로 올릴 수 없음 |
| GitHub 오픈 이슈/PR | 0 / 0 |
| E2E 리포트 | 2026-03-29 기준(초기 13개 스킬). 이후 추가된 3개 스킬·M1 인프라·is-fetch는 미반영 |
| 외부 의존성 | job-search: Node + Playwright + Chromium · is-fetch: Python≥3.10 venv + curl_cffi · export: pandoc · viewer: CDN(marked, 버전 미고정) + Google Fonts |

README의 "Zero 의존성 — bash만 있으면 설치/실행 가능", "100% Markdown 스킬 — 코드 없이 프롬프트만으로 동작" 문구는 v0.1 시점 설명이며 현재와 맞지 않는다(bin/ 1,668줄의 Node·Python·bash 코드가 핵심 기능을 담당).

### 1-2. 실측으로 확인한 결함 (P0)

#### D-1. 공유 템플릿·문서 참조가 CLI 설치에서 로드되지 않는다 `[실측]`

- **현상**: `install.sh`는 각 스킬 디렉토리를 `~/.claude/commands/<skill>`로 **심링크**한다. 이 상태에서 `${CLAUDE_SKILL_DIR}`은 실경로가 아니라 **심링크 경로**(`/root/.claude/commands/<skill>`)로 치환된다. 스킬 본문의 `${CLAUDE_SKILL_DIR}/../templates/guardrails.md`를 Read 도구로 읽으면 경로가 `~/.claude/commands/templates/guardrails.md`로 정규화되어 **"file does not exist"** 로 실패한다. 같은 경로를 Bash로 실행하면 커널이 심링크를 물리적으로 따라가므로 **성공**한다(프리앰블의 `../bin/jobstack-config` 호출이 동작하는 이유).
- **재현**: 임시 스킬 `zz-read`(심링크 설치)에서 `Read ${CLAUDE_SKILL_DIR}/../templates/probe.md` → `READ=FAILED, file does not exist`, `Bash "${CLAUDE_SKILL_DIR}/../bin/probe.sh"` → `BASH=BIN_OK_67890`. Node `path.resolve`도 같은 방식으로 정규화하고, 정규화 없는 `fs.readFileSync`는 성공한다 → Claude Code Read 도구의 경로 정규화가 원인.
- **영향 범위**: 16개 스킬 전부의 "작업 시작 전 `${CLAUDE_SKILL_DIR}/../templates/guardrails.md`를 Read 도구로 읽고 §1~§6 전 규칙을 준수하세요" 지시와, experience-methods·humanize-check·three-docs-guide·`docs/tracker-states.md`·`docs/defense-map-schema.md`·`docs/telemetry-events.md` 참조 **113곳**. 즉 사실 날조·PII 금지, 수치 폴백 5기준, 치환 테스트, 3문서 역할 구분이 **실제 실행에서는 주입되지 않는다**(각 스킬에 인라인된 요약본만 작동). 모델이 실패를 보고 `cat`으로 우회할 수는 있으나 지시는 "Read 도구"이고 헤드리스 실행에서는 우회를 기대할 수 없다. 프로덕션(jobclaw)은 SKILL.md만 복사해 설치하므로 같은 이유로 실패한다 — job-search·company-research·salary 프리앰블이 `/app/skills/jobstack/bin` 절대경로 탐색을 하드코딩한 것이 그 방증이다.
- **왜 지금까지 안 잡혔나**: `test/test-preambles.sh`는 `CLAUDE_SKILL_DIR`를 **실경로로 주입**하고 bash 블록만 실행한다. Read 도구 경로는 어떤 테스트도 검증하지 않는다.
- **수정 옵션** (`[추론]`, §3 U-01 참조): (a) 템플릿을 각 스킬 디렉토리 안 `references/`로 두고 `${CLAUDE_SKILL_DIR}/references/…`로 참조(Agent Skills 관례, 심링크와 무관) — 단일 원본은 `templates/`에 두고 빌드 스크립트가 복제. (b) 항상 필요한 가드레일은 `` !`cat "${CLAUDE_SKILL_DIR}/../templates/guardrails.md"` `` 동적 주입으로 로드 시점에 인라인(bash 물리 해석이라 심링크에서도 동작, Read 턴 자체가 사라짐). (c) 플러그인 패키징 후 `${CLAUDE_PLUGIN_ROOT}/templates/…` 사용(플러그인은 실디렉토리로 설치됨). (d) `install.sh`가 심링크 대신 복사. 권장 조합은 (b)+(a), 장기적으로 (c).

#### D-2. 봇 전용 프로토콜이 CLI 스킬에 섞여 있다 `[사실]`

| 봇(jobclaw) 전용 요소 | 포함 스킬 |
|---|---|
| `[IMAGE_PROMPT: …]` 응답 말미 마커 (17줄 블록) | company-research, job-search, ncs, portfolio, salary, strategy |
| `[CHOICES]` 블록 위치 지시 | job-search |
| File output protocol `[OUTPUT_FILE:]` + `render-docx.sh` + `runs/$JOBCLAW_RUN_ID` | resume, cover-letter, review |
| `/app/skills/jobstack/bin` 등 프로덕션 절대경로 탐색 | job-search, company-research, salary 프리앰블 |
| "Telegram은 https:// 없으면 링크 인식 안 됨" 규칙 | job-search |

- CLI 사용자는 매 기업분석·공고 검색 응답 끝에 영어 이미지 프롬프트 한 줄을 받는다. `ncs`는 README상 "봇 미노출·CLI 전용"인데도 봇 마커를 갖고 있다. 문서 스킬의 출력 경로도 이원화되어 있다(resume·cover-letter·review는 봇 프로토콜 우선, career-history는 CLI `jobstack-export`).
- 환경 감지 추상화가 없어 "render-docx.sh가 없으면"류의 산문 분기로 처리한다. 프리앰블(또는 훅)이 `JOBSTACK_RUNTIME=cli|bot`를 한 번 판정하고, 봇 전용 블록은 별도 템플릿으로 분리해 봇에서만 주입하는 구조가 필요하다(§3 U-02).

#### D-3. 결과물 뷰어의 `</script>` 방어가 무력하고 오프라인에서 본문이 비어 보인다 `[실측]`

- `bin/jobstack-view`는 마크다운을 `<script type="text/plain">` 안에 넣는데, `md.replace('</script>', '<' + '/script>')`는 **치환 전후가 동일 문자열**이라 아무것도 바꾸지 않는다. 마크다운 본문에 `</script>`가 들어가면 스크립트 블록이 조기 종료돼 페이지가 깨진다(실측: 생성 HTML에 원문 그대로 삽입됨). 상단의 `MD_CONTENT=$(… sed …)` 이스케이프 코드는 이후 어디에서도 쓰이지 않는 죽은 코드다.
- `marked`를 jsDelivr에서 **버전 미고정**으로 로드하고 Google Fonts에 의존한다. 오프라인이거나 CDN이 막힌 환경(회사망·봇 컨테이너)에서는 본문이 렌더되지 않는다. 통합 테스트는 "CDN 참조 문자열이 있는지"만 검사한다.
- 수정: `</script>`를 `<\/script>`로 치환하고 JS에서 복원(또는 HTML 이스케이프 후 `textContent` 사용), marked를 특정 버전으로 고정하고 가능하면 인라인 번들, 폰트는 시스템 폰트 폴백 우선(§3 U-03).

### 1-3. 구조적 부채 `[사실]`

1. **프리앰블 드리프트와 죽은 생성 파이프라인** — `bin/gen-skill-docs.sh`는 `*/SKILL.md.tmpl`을 전개하도록 설계됐지만 `.tmpl` 파일이 하나도 없다. 그 결과 프리앰블(39~72줄 bash)이 16개 스킬에 손으로 복사되어 있고, `templates/preamble.md`와 전부 불일치한다(diff 9~40줄). 변수명도 갈렸다(`EXPERIENCES_EXIST` vs `EXPERIENCES_EXISTS`). 프리앰블이 출력하는 `ACTIVE_SESSIONS`는 어떤 스킬도 소비하지 않고, `PROACTIVE`의 실소비처는 tracker뿐이다.
2. **공유 블록의 인라인 복제** — `templates/voice.md`를 참조하는 스킬은 0개(전부 인라인 복사, 금지어 목록이 스킬마다 다름: cover-letter는 '체계적' 누락, 3개 스킬은 '뛰어난' 추가). AskUserQuestion 규칙·완료 상태·뷰어 안내도 대부분 인라인이다. 방법론 중복: 꼬리질문 5세트(retro·portfolio·mock-interview·review·defense-map-schema), 수치 폴백/대체 4종(experience-methods·ncs·portfolio·resume·cover-letter), 중고신입 정의 "경력 6개월~3년"(6개 스킬).
3. **거대 단일 SKILL.md** — 모드·직군·경력 유형별 분기, 플랫폼별 API 파라미터, README 템플릿, 협상 스크립트 같은 정적 참조 자료가 전부 본문에 있다. mock-interview 7모드, resume 신입/경력/중고신입 전략, job-search 플랫폼별 4단계가 한 번에 로드된다. 공식 가이드는 SKILL.md 500줄 이내·참조 파일 분리를 권한다(§2-1).
4. **LLM 수작업 데이터 편집** — tracker JSONL의 `max_stage` 갱신·tmp+mv 재작성, experiences.yaml append, defense-map YAML 산출, retro 패턴 집계(Grep), 퍼널 전환율 계산을 모두 모델이 손으로 한다. `#122 스코어 결정성` 규칙은 있지만 계산 주체가 LLM이라 재현성이 보장되지 않는다. Anthropic 가이드도 결정적 작업은 번들 스크립트로 처리하라고 권한다.
5. **교차 모순 (grep으로 재확인)**
   - retro 본문이 WebSearch를 2회 지시하지만 `allowed-tools`에 WebSearch가 없다.
   - `docs/defense-map-schema.md`는 retro를 소비자(방어 준비율)로 명시하지만 retro는 `defense-maps/`를 읽지 않는다.
   - auto 진입점이 experience-bank·career-history·scout-profile·retro·salary·ncs로 라우팅하는 문구가 없다(신규 스킬 3개가 진입점에서 보이지 않음).
   - experience-bank는 "ncs가 카드를 이어받는다"고 안내하지만 ncs는 `experiences.yaml`을 읽지 않는다.
   - scout-profile은 WebSearch·WebFetch·Glob·Edit을 허용하지만 본문에서 쓰지 않는다(URL은 붙여넣기로 유도).
   - `fetch-jobs.mjs`의 `programmers` 플랫폼은 SKILL에서 "접속 차단·제외"인데 코드는 남아 있다.
6. **릴리스 위생** — CHANGELOG·VERSION이 두 달간의 20커밋을 반영하지 않고, 태그가 없어 사용자가 어떤 버전을 설치했는지 알 수 없다. 린트 9종이 있지만 PR 게이트(CI)가 없어 "마일스톤마다 lint 통과를 게이트로" 원칙이 수동이다.

### 1-4. 사용자 관점 기능 공백 `[사실]`+`[추론]`

| 공백 | 현황 | 비고 |
|---|---|---|
| 한글 문서(.hwp/.hwpx) 입력 | auto가 `*.hwp`, `*.hwpx`를 스캔 대상에 넣지만 Read로 파싱할 수 없고 변환 스크립트가 없다 | hwpx는 zip+XML이라 표준 라이브러리만으로 텍스트 추출 가능. hwp(바이너리)는 별도 라이브러리 필요 (§2-4) |
| 반복 실행 | 공고 모니터링·마감 D-day 리마인드·정체 넛지가 전부 "스킬을 다시 실행했을 때"만 동작 | Routines(`/schedule`), Desktop scheduled tasks, cron+`claude -p` 후보 |
| 로그인 필요 사이트 | 원티드 프로필·링크드인·잡플래닛 상세는 WebFetch/is-fetch로 접근 불가 → 붙여넣기 요청 | Claude in Chrome 확장으로 사용자의 로그인 세션 활용 가능 |
| 병렬 리서치 | company-research 7소스, salary 7소스, strategy 시장 분석이 단일 컨텍스트에서 순차 WebSearch | 서브에이전트 병렬화 + JSON 반환 계약 |
| 스킬 품질 평가 | 골든 테스트는 tracker 결정 케이스 1개. resume/cover-letter/review/job-search trait 케이스(INFRA-8)는 미구현 | 스킬 eval 체계 부재 |
| 공식 API | job-search가 잡알리오·고용24 등을 "사이트명 안내"만 하고 스크래핑에만 의존 | 공공 API 활용 여지 (§2-4) |

---

## 2. 2026-09 생태계 변화와 jobstack의 위치

### 2-1. Claude Code (공식 문서·CHANGELOG·실측) `[사실]`

출처: `https://code.claude.com/docs/en/skills`, `/plugins-reference`, `/hooks`, `/sub-agents`, `/routines`, `/memory`, `/chrome`, `anthropics/claude-code` CHANGELOG(v2.1.259).

| 영역 | 2026-09 현재 | jobstack 현황 | 시사점 |
|---|---|---|---|
| **스킬 위치·명령 병합** | 커스텀 명령이 스킬로 병합됨. 표준 위치는 `~/.claude/skills/<name>/SKILL.md`, `.claude/skills/`, 플러그인. `commands/`는 "파일명=명령명"인 파일 단위 레거시로만 문서화. 스킬 디렉토리 **심링크는 공식 지원** | `~/.claude/commands/<dir>`(디렉토리 심링크). 실측상 v2.1.259에서 인식되지만(auto, cover_letter 목록 노출) 문서에 없는 동작 | 설치 위치를 `skills/`로 옮기고, 궁극적으로 플러그인으로 전환 |
| **프론트매터** | `name, description, when_to_use, argument-hint, arguments, disable-model-invocation, user-invocable, allowed-tools, disallowed-tools, model, effort, context(fork), agent, background, hooks, paths, shell, metadata, license, compatibility`. 미지 필드는 무시. description+when_to_use 합산 1,536자 상한 | `preamble-tier, version, benefits-from`는 비표준(무시됨). 신필드 미사용 | `metadata:` 아래로 커스텀 필드 이동, `argument-hint`·`when_to_use` 추가, CLI 전용 스킬에 `user-invocable`/`disable-model-invocation` 검토 |
| **동적 주입** | `` !`command` ``와 ```` ```! ```` 블록이 **스킬 로드 전에** 실행되어 출력이 본문에 인라인됨. 치환 변수 `$ARGUMENTS`, `$0`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_EFFORT}`. `disableSkillShellExecution` 정책·claude.ai 동기화 스킬에서는 실행 안 됨 | 프리앰블을 모델이 Bash 도구로 실행(턴 1회·권한 필요) | 프리앰블을 `!` 주입으로 전환하면 결정적·무턴. 단 Cowork/동기화 스킬에서는 폴백 필요 |
| **스킬 목록 예산** | 이름·설명 목록이 컨텍스트에 상시 로드, 예산은 컨텍스트 창의 1%(문자). 초과 시 설명 절단. `/doctor`로 비용 확인, `skillListingBudgetFraction`로 조정 | 16개 설명(195~709자). 실측에서는 절단 없음 | 설명을 1~2문장+`when_to_use`로 정리해 예산 여유 확보 |
| **플러그인** | `.claude-plugin/plugin.json` + `skills/`, `agents/`, `hooks/hooks.json`, `.mcp.json`, `bin/`(PATH 추가), `settings.json`. `${CLAUDE_PLUGIN_ROOT}`(실경로), `${CLAUDE_PLUGIN_DATA}`(업데이트에도 남는 데이터 디렉토리 — node_modules·venv 용도 명시). 마켓플레이스는 GitHub 저장소의 `.claude-plugin/marketplace.json`, `/plugin marketplace add owner/repo`, `claude plugin validate`. 스킬명은 `/plugin:skill`이며 충돌 없으면 `/skill`도 동작 | 없음. git clone + install.sh | 배포·업데이트·버전 관리를 플러그인으로 일원화. Playwright·venv를 `${CLAUDE_PLUGIN_DATA}`에 설치 |
| **훅** | `SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, Stop, SubagentStop, SessionEnd, PreCompact` 등 30여 이벤트. stdin JSON에 `session_id, cwd, transcript_path, permission_mode`. SessionStart는 `additionalContext`로 문맥 주입, `CLAUDE_ENV_FILE`로 env 지속. 선언 위치: settings.json, 플러그인 `hooks/hooks.json`, 스킬·에이전트 프론트매터(`once`) | 세션 추적·텔레메트리를 프리앰블 bash가 매 스킬마다 수행 | 세션 PID 파일 대신 `session_id` 기반 훅으로 텔레메트리·세션 집계 이관 |
| **서브에이전트** | `.claude/agents/<name>.md` (tools, model, permissionMode, skills, memory, isolation, maxTurns, hooks, mcpServers). 스킬 프론트매터 `context: fork` + `agent` + `background`. CHANGELOG 2.1.232: 포크형 서브에이전트가 기본, 프롬프트 캐시 상속 | 사용 없음 | 리서치 계열(company-research·salary·strategy)의 병렬화, mock-interview·review의 컨텍스트 격리 |
| **Routines** | 클라우드에서 스케줄(최소 1시간)·API·GitHub 이벤트로 실행. `/schedule`로 생성, Pro/Max/Team/Enterprise, claude.ai 로그인 필요. 로컬 대안: Desktop scheduled tasks, 세션 내 `/loop` | 없음 | 공고 모니터링·마감 리마인드. 단 클라우드 세션은 `~/.jobstack`(로컬 PII)에 접근 못 함 → 프로필을 저장소나 커넥터로 넘겨야 하며 개인정보 판단 필요 |
| **Claude in Chrome** | 사용자의 로그인 상태 브라우저를 Claude Code가 조작(폼 입력·데이터 추출·스크린샷). Pro/Max/Team/Enterprise | 없음 | 원티드 프로필·링크드인·잡플래닛 상세처럼 로그인 뒤 데이터의 선택적 경로 |
| **Cowork·클라우드 세션** | `~/.claude/skills/`를 읽지 않고 claude.ai 계정에서 활성화한 스킬만 로드. `!` 명령은 실행되지 않음 | 로컬 설치 전제 | claude.ai 스킬 업로드 배포를 원하면 bash 프리앰블 비의존 구조가 선행돼야 함 |
| **메모리·규칙** | `.claude/rules/*.md`(`paths`로 범위 지정), CLAUDE.md 200줄 이내 권고, `@import` | CLAUDE.md 30줄, 규칙 없음 | 저장소 개발 규칙(컨벤션·금지어)을 `.claude/rules/`로 이동 가능 |
| **헤드리스** | `claude -p`, `--output-format json`, `--allowedTools`, `--permission-prompts none`(2.1.259, 무인 호스트용), Agent SDK(Python/TS) | jobclaw가 별도 러너 | §2-2 참조 |

### 2-2. Claude 플랫폼·모델·Agent SDK `[사실]`

출처: `https://platform.claude.com/docs/en/models/overview`(모델 표는 검토자가 직접 확인), 그 외 platform.claude.com·code.claude.com 문서(부록 B).

**모델 라인업 (2026-09-03)**

| 모델 | ID | 입력/출력 ($/MTok) | 컨텍스트 / 최대 출력 | 추론 | 은퇴 하한 |
|---|---|---|---|---|---|
| Claude Fable 5.1 | `claude-fable-5-1` | 10 / 50 (캐시 읽기 2.5%) | 1M / 128K | 적응형(항상 켜짐), 기본 effort `high` | 2027-09-01 |
| Claude Opus 5 | `claude-opus-5` | 5 / 25 | 1M / 128K | 적응형, 기본 `high` | 2027-07-24 |
| Claude Sonnet 5 | `claude-sonnet-5` | 2 / 10 | 1M / 128K | 적응형, 기본 `high` | 2027-06-30 |
| Claude Haiku 4.5 | `claude-haiku-4-5-20251001` | 1 / 5 | 200K / 64K | 확장 추론(effort 미지원) | **2026-10-15** |

- 공식 선택 지침: "대부분의 워크로드는 Claude Opus 5로 시작. Fable 5.1은 고난도 추론·장기 에이전트 작업이거나 Opus 5 평가가 미달일 때". Batch API 50% 할인, 캐시 읽기는 입력가의 10%(Fable 5.1은 2.5%).
- Fable 5·5.1은 "Covered Model"로 API 요청이 30일 보존되고 ZDR(무보존)이 기본 불가 — 이력서·연락처를 다루는 봇 경로에서 고려 사항. Haiku 4.5는 은퇴 하한이 2026-10-15라 새 라우팅 기본값으로 쓰기엔 수명이 짧다.
- Claude Code 스킬 프론트매터 `model:`/`effort:`는 2.1.259 CHANGELOG에 "대화형 세션에서 무시되던 문제 수정"이 실려 있다 → U-19는 2.1.259 이상을 전제로 한다.

**API 기능 중 jobstack 관련 항목**

| 기능 | 요지 | jobstack 관련성 |
|---|---|---|
| 구조화 출력 (`output_config.format`, JSON schema) | 정식 기능. 스키마는 24시간 캐시, 인용(citations)과 동시 사용 불가 | 봇 경로에서 defense-map·경험 카드·tracker 항목을 스키마로 강제 가능(U-09 계약의 API 측 구현) |
| PDF 입력 | 32MB·600페이지, 페이지당 텍스트+이미지 토큰, 페이지 단위 인용 | 이력서·채용공고 PDF는 그대로 투입. `.docx`·`.hwp`는 Files API·document 블록이 받지 않으므로 **로컬 변환 필수**(U-11) |
| 웹 검색·웹 페치 서버 도구 (`web_search_20260209`, `web_fetch_20260209`) | 검색 1,000회당 $10, `allowed_domains`/`blocked_domains`, `user_location`; web_fetch는 대화에 이미 있는 URL만 가져오고 JS 렌더링 없음 | 봇 경로 company-research·salary에 `user_location: KR` + 채용·공시 도메인 allowlist 적용 |
| 프롬프트 캐싱 | 접두사 일치 기반, 5분/1시간 TTL, 최소 캐시 길이 모델별 512~4,096 토큰 | 프리앰블·가드레일·보이스를 **고정 접두사**로 앞에 두고 프로필·날짜 같은 가변 내용을 뒤에 두면 캐시 적중(U-01·U-04 설계 조건) |
| Batch API | 50% 할인, 24시간 내 완료 | eval 야간 회귀(U-16) 비용 절감 |
| 메모리 도구·컨텍스트 편집·서버측 compaction | 장기 세션의 컨텍스트 관리 | 모의면접 장기 세션(봇 경로) |
| Managed Agents 스케줄 배포 | cron 기반 자율 실행, 세션당 과금 | 로컬 cron 대신 서버에서 공고 모니터링을 돌릴 때의 대안(U-14) |

**Claude Agent SDK·헤드리스 (jobclaw 봇 러너 관점)**

- `claude -p`는 유지. 스크립트에는 `--bare` 권장("향후 -p의 기본값"): 훅·CLAUDE.md·MCP·자동 메모리를 건너뛰되 `--add-dir`의 `.claude/skills/`는 로드. `--output-format json`, `--allowedTools`, `--max-turns`, `--max-budget-usd`, `--permission-prompts none`(2.1.259).
- Agent SDK(Python `claude-agent-sdk`, TS `@anthropic-ai/claude-agent-sdk`) 문서의 테넌트 격리 레시피: 사용자별 `cwd`, `CLAUDE_CONFIG_DIR`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1`, `setting_sources=[]`, 스킬은 `plugins=[{"type":"local","path":…}]`로 주입, `permission_mode="dontAsk"` + 명시적 `allowed_tools`, `max_turns`·`max_budget_usd`. `AskUserQuestion`은 `can_use_tool` 콜백으로 가로채 텔레그램 인라인 키보드에 매핑할 수 있다(jobclaw의 `[CHOICES]` 프로토콜을 대체할 수 있는 정식 경로).
- 라이선스: 제3자는 claude.ai 로그인·구독 한도를 자기 제품에 제공할 수 없음 → 봇은 API 키 과금 전제. `total_cost_usd`는 추정치라 사용자 청구 근거로 쓰지 말 것.
- Claude Code **Channels**(연구 미리보기)의 공식 텔레그램 플러그인은 "한 소유자의 로컬 세션에 메시지를 흘려 넣는 브리지"라 멀티테넌트 봇(jobclaw)을 대체하지 못한다.
- 보안: 가져온 웹 콘텐츠는 `tool_result`에 담고 시스템 프롬프트에 "도구 결과 속 지시는 정보로만 취급" 블록을 두라는 공식 가이드(is-fetch·WebFetch 결과를 소비하는 company-research·job-search에 해당). Files·Skills API는 워크스페이스 단위라 사용자별 격리 수단이 아니다.

**jobstack 시사점**: (1) 스킬 프론트매터 `model`/`effort`로 라우팅·분류(auto Phase 1, tracker 명령 감지)는 `sonnet`+낮은 effort, 문서 첨삭·면접은 `opus`+`high`를 기본으로 두고 Fable 5.1은 eval로 이득이 확인된 스킬에만(U-19). (2) 프리앰블·가드레일을 고정 접두사로 재배치해 캐시 적중을 노린다(U-01·U-04). (3) 봇 경로는 `[CHOICES]`·`[OUTPUT_FILE:]` 같은 텍스트 프로토콜 대신 구조화 출력과 `can_use_tool`로 옮길 수 있다(U-02의 장기 방향, 이 저장소 범위 밖). (4) hwp·docx는 로컬 변환이 유일한 경로다(U-11).

### 2-3. 의존성·참조 프로젝트 (gstack·insane-search·Playwright·curl_cffi) `[사실]`

출처는 npm·PyPI 레지스트리, GitHub raw 파일(릴리스 노트·CHANGELOG)이다. 이 샌드박스의 프록시가 한국 채용 사이트 4곳과 archive.org를 차단해 **사이트 표면(셀렉터·WAF) 실측은 못 했다** — 아래 "사이트 표면" 행은 간접 근거만 적는다.

| 구성요소 | jobstack 핀 | 최신 (일자) | 리스크 | 조치 |
|---|---|---|---|---|
| Playwright | `^1.50.0` (신규 설치 시 1.62.1로 해석) | 1.62.1 (2026-07-30) | 1.62부터 `engines.node >= 20`. 1.57(2025-11)부터 headless는 `chrome-headless-shell`(UA 기본값 `HeadlessChrome`, jobstack은 UA를 직접 지정하므로 영향 낮음). jobstack이 쓰는 API(`launch` args, `addInitScript`, `context.request.get`, `setContent`)는 1.50~1.62 사이 제거·변경 없음. 공식 스텔스 기능은 없음 | `~1.62.1`로 핀 고정, Node 24 문서화. 강한 WAF에는 patchright 1.62.3(2026-09-02, Playwright 릴리스 추적, `Runtime.enable` 누수 패치) 검토. playwright-extra(2023)·rebrowser(2025-05)는 정체 |
| Node.js | 미선언 | 24.20.0 Active LTS · 22.23.2 유지보수 · 26.8.1 Current | Node 20은 2026-04-30 EOL. Node 26은 `type: module` 패키지의 확장자 없는 CJS 해석 예외 제거(jobstack은 확장자 명시라 무관) | `bin/package.json`에 `engines: {node: ">=22"}` 추가, README에 24 권장 |
| curl_cffi (`is-fetch.py`) | `>=0.15,<0.16` → 실제 0.15.0(2026-04) | 0.16.3 (2026-09-02) | 0.15.1은 베타만 있어 핀이 0.15.0에 고정됨. TLS 프로파일이 Chrome 146 / Safari 26.0에서 멈춤(WAF는 오래된 JA3/JA4를 낮게 평가). 0.16은 `curl-cffi update`(impersonate.pro 동적 지문), header-order, redirect history, Response.is_redirect 추가. 별칭 `chrome`/`safari`는 그대로 "최신"으로 해석. Python 3.10~3.14 지원, 3.15는 `[미확인]` | `>=0.16,<0.17`로 상향 후 `test-is-fetch-adapter.mjs` 재실행. insane-search 0.12의 "runtime target filter"(설치된 프로파일과 교집합) 이식 |
| marked (뷰어 CDN) | 미고정 `marked/lib/marked.umd.js` | 18.0.11 (2026-08-24) | 경로·`window.marked`·`marked.parse()` 유효. v16(2025-06)에서 `marked.min.js` 공개 경로가 삭제된 전례 — 미고정 URL은 미래 v19에서 기존 산출 HTML까지 소급 파손 | `marked@18.0.11` 고정, 약 40KB UMD 인라인 검토 |
| pandoc (`jobstack-export`) | 시스템 바이너리, 버전 검사 없음 | 3.11 (2026-08-28) | 3.9~3.11 사이 `--reference-doc` 의미 변화 없음. 단 3.6.1(2024-12)부터 Title/Subtitle이 스타일 ID 기준으로 바뀌어 오래된 reference docx가 어긋날 수 있음 | `jobstack-export`에 pandoc ≥3.6 하한, `ats-reference.docx`를 3.x 기본 문서에서 재생성 |
| docx 대안 | 없음 | npm `docx` 9.7.1 (2026-05-27), `pandoc-wasm` 1.1.0 (2026-06-11) | — | pandoc 부재 시 "exit 2 → 마크다운 복붙" 대신 Node `docx` 폴백 산출(U-13) |
| gstack (아키텍처 원본) | 3월 초기 구조 차용 | 1.79.0.0 (2026-09-01, 6개월간 430회 변경) | 여전히 clone+`./setup` 심링크 설치(플러그인 아님). **1.71(2026-08-27)에서 프리앰블 bash를 `bin/gstack-skill-start/end` 런타임 스크립트로 옮겨 프롬프트 비용 51% 절감** — U-04와 같은 방향. 그 외: SKILL.md.tmpl 생성기+CI 신선도 검사, 프론트매터 토큰 예산 테스트(스킬당 260바이트), SessionStart 업데이트 훅·Stop 훅, `learnings.jsonl`+`/learn`, eval 3계층(무료/LLM 심사/`claude -p` E2E, gate·periodic 구분), browse 데몬·`/scrape`→`/skillify`, 4자리 버전+PR 제목 규칙 | 채택: 프리앰블 스크립트화, 카탈로그 토큰 예산 테스트, `.tmpl` 생성 파이프라인 복구, eval 계층 분리, 운영 학습 로그 |
| insane-search (fetch 계층 원본) | 0.9.1 기준 흡수 | 0.16.0 (2026-08-27), 플러그인 설치 | 0.12: WAF 프로파일(kasada·imperva 등)·`block_class`(bot_detection vs infra_or_auth) 차등 판정·챌린지 마커 식별자 경계 매칭·runtime target filter. 0.14: API 정찰 경로 **제거**(범위 축소). 0.16: patchright/CDP 레인 headful 기본. 한국 라우터는 네이버 검색·금융뿐 | 이식: 경계 매칭 마커, target filter, `block_class`, Retry-After 재시도. 제거된 API 정찰은 비목표 유지 |
| 사이트 표면 (사람인·원티드·잡코리아·점핏) | 셀렉터 최종 검증 2026-07-20 | `[미확인]` (프록시 차단) | 2026-04 기준 제3자 스크레이퍼들이 사람인 `.item_recruit`, 원티드 `api/v4/jobs`(`due_time`/`status`), **점핏 `api.jumpit.co.kr/api/positions`(`closedAt`)** 를 사용. jobstack은 점핏을 DOM 스크래핑(`jumpit.saramin.co.kr`)으로 처리 중. 원티드 파트너용 OpenAPI(`openapi.wanted.jobs`) 존재 `[미확인]` | 비차단 네트워크에서 `fetch-diag.mjs` 실행 후 셀렉터 카나리를 골든 테스트로 고정. 점핏 API·원티드 OpenAPI 경로 평가 |
| anthropics/skills · skill-creator | `SKILL.md`+`templates/`, eval 없음 | `evals/evals.json`(`expectations` 배열) + `run_loop.py`(설명 트리거 최적화, should_trigger 쿼리 20개) + grader 에이전트 | 형식 호환 | U-16에서 이 하네스를 그대로 채택, `test/golden`의 must_contain을 `expectations`로 매핑 |

### 2-4. 한국 채용시장·플랫폼·제도 (2026 하반기)

> 이 샌드박스의 프록시가 국내 언론·포털·공공 API 도메인을 차단해 원문 확인이 불가했다. 검색 결과 요약과 접근 가능한 원문(PyPI·GitHub)으로 교차 확인한 항목은 `[2차]`로 표시하며, **스킬 본문을 바꾸기 전에 해당 URL에서 원문을 다시 확인**해야 한다(가드레일 §3 — 시장 수치는 출처·기준 시점 병기, 본문 하드코딩 금지).

**채용 방식·규모**

| 사실 | 출처 |
|---|---|
| 경총 「2026 신규채용 실태조사」(100인 이상 500개사, 2026-02): 수시채용만 54.8%, 공채+수시 병행 35.0%, 정기공채만 10.2%. 평가 요소 1위 '직무 관련 업무 경험' 67.6% `[사실]` (선행 계획서와 동일 수치) | https://eiec.kdi.re.kr/policy/domesticView.do?ac=0000203504 |
| 인크루트 「2026 하반기 채용 동향」(600개사, 2026-08-20): 대기업 채용 확정 74.3%(+14.6%p), 두 자릿수 채용 61.8%, 수시 비중 약 70% `[2차]` | https://www.kado.net/news/articleView.html?idxno=2067618 |
| 잡코리아 「2026 하반기 채용 동향」(인사담당자 569명, 2026-08-10): 10명 이하 채용 78.9%(+18.4%p), 채용 업무 AI 활용 80.8% `[2차]` | https://www.newspim.com/news/view/20260810000140 |
| 원티드랩 기업 설문(2025-12): 집중 채용 연차 4~7년차 49.7%, 신입 12.4%, 인재상 'AI·데이터 활용 역량' 24.2% `[2차]` | https://zdnet.co.kr/view/?no=20251208160526 |
| 한경협 500대 기업(2025 하반기): 대기업 신입 중 중고신입 28.1% `[사실]` (선행 계획서 수치) | https://www.fki.or.kr |
| 통계청 2026-07 고용동향 보도: 청년(15~29) 실업률 6.8%(+1.3%p), 취업자 45개월 연속 감소 `[2차]` | https://www.fnnews.com/news/202608120852207493 |

→ 수시·소규모·경력 우대 구조가 더 굳어졌다. 선행 계획서의 "수시 중심·중고신입 트랙" 교정은 유효하며, 남은 공백은 **상시 모니터링**(U-14)이다.

**AI 활용 채용과 전형 구조 변화** `[2차]`

- 고용노동부 「2025 기업 채용동향조사」(500대 기업 394개사, 2025-11-28): 채용에 AI 활용 21.7%, 그중 AI 인적성·역량검사 69.8%·서류 검토 46.5%·AI 면접 46.5%. 청년 42.3%가 취업 준비에 AI 활용, 그중 자소서·이력서 작성 77.2%. — https://www.moel.go.kr/news/enews/report/enewsView.do?news_seq=18662
- 무하유 「2026 AI 채용 트렌드」(2026-01-09): 2025년 제출 자소서의 64.4%가 생성형 AI 작성 추정, 기업의 탐지 도구(GPT킬러) 사용 +66.6%, 금융권 채용박람회 76개사 전부 AI 서류평가 활용. — https://www.etnews.com/20260109000170
- **SK하이닉스**(2026-07-30 발표): 하반기 신입 수시채용(8/20~26)부터 자기소개서 폐지 → '경험기술서'(직무전문성 / AI 기반 문제 해결 경험, 각 최대 2,000자), 학력·연령 제한 폐지, 반나절 심층면접(PT·심층 인터뷰·그룹 토의·비대면 영상). — https://biz.heraldcorp.com/article/10825158
- **한화생명 2026 신입공채**(2026-08-21): 서술형 자소서 폐지 → 60여 개 문답형 상세지원서. — https://www.thefairnews.co.kr/news/articleView.html?idxno=85777
- **넥슨 넥토리얼**(2026-08-25): 코딩테스트 폐지 → 전원 AI 면접 + AI 도구로 실무 유사 문제 풀이. 무신사(2026-03)는 코테 뒤 'AI 도구 활용 테스트', 프로그래머스는 프롬프트·수정 이력을 평가하는 'AI 역량평가'(2026-03-31) 출시. 반면 네이버·카카오 등 다수는 코테 중 AI 사용 금지 유지. — https://www.asiae.co.kr/article/2026082516042397206 · https://www.jobkorea.co.kr/goodjob/tip/view?News_No=22546
- 고용노동부: 채용 분야 AI 활용 가이드라인과 AI 채용 사전고지·차별금지 법제화 추진(2026 업무보고). — https://www.moel.go.kr/news/enews/report/enewsView.do?news_seq=18725

→ jobstack의 cover-letter는 "문항 있는 자소서" 전제가 강하다. **경험기술서·문답형 상세지원서·AI 활용 경험 문항**을 정식 모드로 두고(U-21), 기술면접에 "AI 도구 활용 과제" 서브모드(U-22)를 추가할 근거가 생겼다. AI 탐지 대응(Phase 9.5 인간화 점검)은 이미 있으므로 유지·강화.

**플랫폼 변화와 공식 API** `[2차]`

| 플랫폼 | 2026 변화 | 공식 API |
|---|---|---|
| 사람인 | AI 헤드헌터 '에이전트핏'(2026-07-29), 'AI 서류합격 코칭'(2026-05-21, 경쟁자 대비 강약점 수치화), AI 모의면접(모바일·음성) | 오픈API 채용공고 검색, **일 500회**, 이용 신청·승인제 — https://oapi.saramin.co.kr/guide/job-search |
| 잡코리아 | 2025-09 전면 개편(LOOP AI 추천), 서류합격 예측·연봉 예측 | API 안내 페이지 존재(내용 미확인) — https://www.jobkorea.co.kr/service/api |
| 원티드 | 구직자용 AI 에이전트 2종(포지션 자연어 검색·이력서 코칭, 2025-11-20), 기업용 채용 에이전트 | OpenAPI(채용정보·회사정보, 인증키 신청 후 3영업일) — https://openapi.wanted.jobs/ |
| 고용24(워크넷 통합) | AI 고용서비스 3종(취업확률 기반 컨설팅 등, 2026-06-29), 12월 이력서·자소서 컨설팅 예정 | Open API(XML, 인증키) — https://m.work24.go.kr/cm/e/a/0110/selectOpenApiIntro.do · 공공데이터포털 워크넷 채용정보 |
| 잡알리오 | 2024-01 오픈API 개방(영리 이용 포함) | 공공기관 채용정보 조회서비스 — https://www.data.go.kr/data/15125273/openapi.do |
| 캐치·리멤버·링커리어 | 캐치 AI자소서·기업별 문항 DB, 리멤버 'AI 퍼스트'(2026-01)·헤드헌팅사 인수, 링커리어 예상 일정 콘텐츠 | 없음 |
| 점핏 | 제3자 스크레이퍼들이 `api.jumpit.co.kr/api/positions`(`closedAt`) 사용(§2-3) | 비공식 |

→ 수집 계층은 **공식 API 우선, 스크래핑은 폴백**으로 뒤집을 수 있다(U-12). 경쟁 플랫폼의 방향은 "합격 확률·예측 점수"이고, jobstack의 차별점은 로컬·근거 기반·경험 뱅크·전 과정 통합이다. 예측 점수 모방은 선행 계획서의 기각 논리(유사 정밀 점수)대로 하지 않는다.

**공공기관·NCS** `[2차]`

- 2026년 공공기관 정규직 28,000명(2020년 이후 최대) + 청년인턴 24,000명(재정경제부, 2026-01-27). — https://www.korea.kr/news/policyNewsView.do?newsId=148958627
- **NCS 직업기초능력 개편**(고용노동부·한국산업인력공단, 2026-04-28 보도): 명칭 '직업공통능력', **10영역·34하위 → 7영역·21하위**(의사소통·수리·문제해결·자기관리·대인관계·디지털·직업윤리), AI 활용능력·디지털책임의식·산업안전보건의식 신설. 공공기관 필기·서류에 반영되는 시점은 기관별로 다르며 `[미확인]`. — https://www.ajunews.com/view/20260428105725136
- 블라인드 채용: 2023-01 과기 출연연·과기원 등 폐지, 일반 공공기관은 유지. 2026년 추가 변경은 `[미확인]`.
- AI 역량검사 공공 확산: 마이다스 'NCS AI 역량검사' 15개 이상 지자체·공공기관 도입(2026-02 보도). — https://www.khan.co.kr/article/202602241532018

→ ncs·cover-letter(공기업 소절)·mock-interview는 "직업기초능력 10개 영역"을 본문에 고정하고 있다. **신·구 체계 병행 참조 파일**로 바꾸고 지원 기관이 어느 체계를 쓰는지 공고에서 확인하는 규칙이 필요하다(U-17).

**AI 면접·역량검사·제도** `[2차]`

- 마이다스인 역량검사(자기보고식 + 전략 게임 + 영상면접, ATS 통합 '에이치닷' 2026-02), 제네시스랩 뷰인터HR, 무하유 '몬스터', 사람인 AI 모의면접(무료 체험) — mock-interview D 모드의 "연습 채널은 실행 시 WebSearch로 확인" 규칙에 맞는 후보 목록.
- 채용절차법 임금(범위) 명시 의무화 개정안: 2026-01 발의, 위원회 심사 중, **미시행**. 청년일자리도약장려금 2026(비수도권 취업 청년 본인 직접 지급), 구직촉진수당 인상, 주4.5일제 도입 기업 지원 로드맵(2026-01-14), 정년연장 입법은 하반기로 지연. — https://watch.peoplepower21.org/BillDetail/2216004 · https://www.moel.go.kr/news/notice/noticeView.do?bbs_seq=20260100030 · https://www.korea.kr/news/policyNewsView.do?newsId=148957963

→ tracker의 "탈락 후 권리 체크리스트"와 salary·strategy에 '지원 시 정책 인센티브' 항목을 추가하되 수치는 실행 시 확인(U-23).

**한글(.hwp/.hwpx) 처리 도구** — 도구 정보는 PyPI·GitHub 원문으로 확인 `[사실]`, 제도 변화는 `[2차]`

| 도구 | 상태 (2026-09) | 용도 |
|---|---|---|
| python-hwpx 6.3.0 (2026-08, Apache-2.0, Python ≥3.10, lxml) | HWPX 전용, 텍스트·HTML·Markdown 추출, 표 보존, 편집·생성·서식 채우기 | HWPX 이력서·지원서 입력, 공공기관 HWPX 양식 출력 |
| kordoc (npm, MIT) | `npx kordoc <file>` → Markdown. HWP 3.x/5.x·HWPX·HWPML·PDF·XLS(X)·DOCX·이미지, 로컬 OCR(PP-OCRv5 korean), MCP 서버(15 도구), 암호 문서는 `--password` | HWP 바이너리 포함 범용 변환기 |
| rhwp v0.8.6 (Rust/WASM, MIT) | HWP 5.0·HWPX·HML 파싱·렌더·편집, CLI 바이너리(Linux/mac/Win), `@rhwp/core` npm, MCP 서버, SVG/PNG/PDF 출력, 암호화·HWP 3.x 미지원 | 렌더·PDF 변환 |
| pyhwp | 2020년 이후 릴리스 없음, Python ≤3.8 명시, AGPL, HWPX 미지원 `[2차]` | 채택 부적합 |
| LibreOffice | 내장 필터는 HWP 3.x까지, HWP 5.x는 H2Orestart 확장 필요 `[2차]` | 폴백 |
| 제도 | 정부 공직자통합메일 HWP 첨부 제한(2026-10 예정), HWPX 표준(KS X 6101) 3차 개정 2024-10 `[2차]` | 공공기관 지원서가 HWPX로 이동 중 |

→ U-11의 1차 경로는 HWPX(표준 라이브러리 zip+XML 또는 python-hwpx), 2차는 HWP 5.x를 kordoc/rhwp 선택 의존성으로 처리하는 것이 현실적이다.

---

## 3. 업그레이드 후보

공수 표기는 선행 계획서와 같다: **S** 30분 내 · **M** 1~2시간 · **L** 반나절 이상. 근거 표기는 §1·§2의 번호를 가리킨다.

### P0 — 결함·기반 (v0.4.0)

| ID | 항목 | 근거 | 공수 | 수용 기준 |
|---|---|---|---|---|
| **U-01** | 공유 템플릿 로드 경로 수정 — ① 가드레일은 `` !`cat "${CLAUDE_SKILL_DIR}/../templates/guardrails.md"` ``로 로드 시점 인라인 ② 나머지 방법론 문서는 `bin/gen-skill-docs.sh`가 `templates/`→각 스킬 `references/`로 복제하고 참조를 `${CLAUDE_SKILL_DIR}/references/…`로 치환 ③ `test/test-skill-paths.sh` 신설: 심링크 설치 상태에서 모든 `${CLAUDE_SKILL_DIR}` 참조가 **정규화 후에도** 존재하는지 검사 | D-1 | M | 심링크 설치에서 `claude -p "/auto"` 실행 시 가드레일 본문이 프롬프트에 포함되고, 참조 경로 실패 0건 |
| **U-02** | 봇 프로토콜 분리 — 프리앰블(또는 SessionStart 훅)이 `JOBSTACK_RUNTIME=cli\|bot` 판정(`JOBCLAW_RUN_ID` 유무). 봇 전용 블록(`IMAGE_PROMPT`, `CHOICES`, `OUTPUT_FILE`, 텔레그램 링크 규칙)을 `templates/bot-protocol.md`로 옮기고 `!` 조건 주입. 문서 스킬 출력 경로를 "bot→OUTPUT_FILE, cli→jobstack-export" 한 블록으로 통일 | D-2 | M | `grep -l 'IMAGE_PROMPT\|OUTPUT_FILE\|CHOICES' */SKILL.md` = 0, ncs·career-history 포함 4개 문서 스킬 출력 규칙 동일 |
| **U-03** | 뷰어 수정 — `</script>` 이스케이프 실구현, marked 버전 고정(가능하면 인라인 번들), 폰트 시스템 폴백, 죽은 `MD_CONTENT` 제거. 통합 테스트에 `</script>` 포함 md 케이스 추가 | D-3 | S | 오프라인에서 본문 렌더, `</script>` 포함 문서가 깨지지 않음 |
| **U-04** | 프리앰블 스크립트화 — `bin/jobstack-preamble <skill>` 한 스크립트가 상태 디렉토리·프로필 요약·config·런타임·`JS_BIN`·`EXPERIENCES_EXISTS`·`TODAY(KST)`를 출력. SKILL.md에는 `` !`"${CLAUDE_SKILL_DIR}/../bin/jobstack-preamble" auto` `` 한 줄. `test-preambles.sh`는 스크립트 하나만 검증 | 1-3 ①, 2-1 동적 주입 | M | 16개 스킬에서 bash 프리앰블 블록 제거(약 700줄 감소), 불변식 3종 유지, Cowork 폴백(`!` 미실행 시 첫 턴에 Bash로 실행) 문서화 |
| **U-05** | 릴리스 위생 — CHANGELOG 0.4.0(7월 20커밋 소급 기록), `git tag v0.4.0`, GitHub Actions에서 린트 9종 실행(`JOBSTACK_STATE_DIR`·`HOME` 격리한 통합 테스트 포함), README 의존성 문구 현행화 | 1-1, 1-3 ⑥ | S~M | PR마다 CI 통과 배지, `VERSION`·CHANGELOG·태그 일치 |
| **U-06** | 교차 모순 6건 수정 — retro `allowed-tools`에 WebSearch 추가(또는 지시 삭제), retro의 defense-map 방어 준비율 실제 구현 또는 스키마에서 소비자 삭제, auto Phase 4·5에 신규 스킬 3종+retro·salary 라우팅 추가, `EXPERIENCES_EXISTS` 통일, ncs 봇 마커 제거, `fetch-jobs.mjs` programmers 분기 제거, scout-profile allowed-tools 정리 | 1-3 ⑤ | S | 린트 신설: 본문에 등장하는 도구명이 `allowed-tools`에 있는지 검사 |

### P1 — 실행 기반 현대화 (v0.5.0)

| ID | 항목 | 근거 | 공수 | 수용 기준 |
|---|---|---|---|---|
| **U-07** | 플러그인 패키징 + 마켓플레이스 — 저장소를 `.claude-plugin/plugin.json` + `skills/<name>/` + `bin/` + `hooks/hooks.json` 구조로 재배치(디렉토리 이동은 git mv), `.claude-plugin/marketplace.json`로 `thesun4sky/jobstack` 자체를 마켓플레이스로 공개. Playwright·is-venv는 `${CLAUDE_PLUGIN_DATA}`에 설치. 기존 `install.sh`는 심링크 호환 모드로 유지 | 2-1 플러그인, D-1(c) | L | `claude plugin validate . --strict` 통과, `/plugin marketplace add thesun4sky/jobstack` → `/plugin install jobstack@jobstack` 으로 설치, `/jobstack:auto`와 `/auto` 모두 동작, `claude plugin update`로 갱신 |
| **U-08** | 진행적 공개(progressive disclosure) — 6개 거대 스킬을 SKILL.md(흐름·게이트, 300줄 이하) + `references/`(모드별·직군별·플랫폼별 정적 자료)로 분할. 프론트매터에 `argument-hint`, `when_to_use` 추가, `preamble-tier`·`version`·`benefits-from`는 `metadata:` 아래로 이동. 예: mock-interview `references/modes/{personality,pt,debate,ai,tech,exec,culture}.md`, job-search `references/platforms/{wanted,saramin,jobkorea,jumpit}.md`, resume `references/tracks/{entry,experienced,junior-experienced}.md` | 1-3 ③, 2-1 프론트매터, 2-3 gstack | L | 모든 SKILL.md ≤ 300줄(`test/test-skill-size.sh`), 스킬 1회 호출 초기 로드 50% 이상 감소, 프론트매터 name+description 합산 예산 테스트(gstack 방식, 스킬당 상한 고정) 통과, 골든 trait 회귀 없음 |
| **U-09** | 결정적 스크립트 계층 — `bin/jobstack-tracker add\|update\|list\|stats\|calendar`(tracker-states.md 구현, 원자적 재저장, max_stage·퍼널 계산), `bin/jobstack-exp add\|list\|validate`(경험 카드 스키마 문서 신설), `bin/jobstack-defense-map add\|list`(스키마 검증), `bin/jobstack-retro-stats`(frontmatter 태그 집계), `bin/jobstack-ats-match <이력서.md> <공고.md>`(키워드 매칭률·등급 결정적 산출). 스킬은 호출만 하고 해석·코칭에 집중 | 1-3 ④ | L | 스킬 본문에서 JSONL/YAML 직접 편집 지시 0건, 골든 테스트가 스크립트 출력으로 판정, 같은 입력 → 같은 점수 |
| **U-10** | 병렬 리서치 서브에이전트 — `agents/researcher.md`(WebSearch·WebFetch·Bash(is-fetch)만 허용, JSON 반환 계약 `{source, finding, url, as_of}`). company-research Phase 1 7소스·salary Phase 2 7소스·strategy Phase 2를 fan-out 후 본 스킬이 합성. 가드레일(훈련 데이터 금지·출처 병기)은 에이전트 프롬프트에 내장 | 1-4 병렬 리서치, 2-1 서브에이전트 | M | 기업분석 소요 시간 단축(측정), 출처 URL 누락 0건 |
| **U-11** | hwpx/hwp 인제스트 — ① `bin/hwpx2md.py`: HWPX(zip+OWPML XML)를 표준 라이브러리만으로 텍스트·표 추출(python-hwpx가 있으면 우선 사용) ② HWP 5.x 바이너리는 kordoc(`npx kordoc <file>`) 또는 rhwp CLI를 선택 의존성으로 탐지해 호출, 둘 다 없으면 "한글에서 HWPX로 저장 후 다시 올려주세요" 안내(pyhwp는 채택하지 않음) ③ auto Phase 1이 `.hwp/.hwpx` 감지 시 자동 변환 후 분류 ④ 공공기관 HWPX 지원서 양식 채우기는 후속 과제로 분리 | 1-4 한글 문서, 2-4 HWP | M | 샘플 hwpx·hwp 이력서가 마크다운으로 변환되어 resume 첨삭까지 진행, 미설치 환경에서 안내 문구로 폴백 |
| **U-12** | 수집 계층 정비 — ① 의존성: Playwright `~1.62.1`, curl_cffi `>=0.16,<0.17`, `engines.node >= 22` 선언 ② 사람인·잡코리아 HTML 파싱을 cheerio/linkedom으로 이관해 브라우저 없이 동작(원티드·점핏만 Playwright) ③ **공식 API 우선·스크래핑 폴백**으로 전환: 사람인 오픈API(일 500회, 승인제)·원티드 OpenAPI·고용24 Open API·잡알리오 공공기관 채용정보 API 키를 `jobstack-config`에 저장하고 `fetch-jobs.mjs`에 `--source api\|scrape` 분기 추가, 키가 없으면 현행 스크래핑. 점핏은 DOM 대신 `api.jumpit.co.kr/api/positions`(`closedAt`) 평가(§2-4) ④ `is-fetch.py`에 insane-search 0.12~0.16의 경계 매칭 마커·runtime target filter·`block_class`·Retry-After 재시도 이식 ⑤ `programmers` 분기 제거 ⑥ 강한 WAF 사이트용 patchright 옵션(headful) 실험 ⑦ `fetch-diag.log` 집계 서브커맨드 + 셀렉터 카나리 골든 테스트 | 1-4 공식 API, 2-3 | L | 사람인 검색이 Chromium 없이 동작, 4플랫폼 픽스처 HTML 회귀 테스트 통과, 어댑터 테스트가 0.16 프로파일명과 동기화 |
| **U-13** | docx 내보내기 이중화 — `jobstack-export`에 pandoc ≥3.6 하한과 `ats-reference.docx` 재생성, pandoc 부재 시 Node `docx`(9.7.1) 기반 폴백 산출(표·이미지 없는 단일 컬럼, 표준 제목 스타일) | 1-1 의존성, 2-3 | M | pandoc 미설치 환경에서도 placeholder 검사(exit 4)를 거친 ATS-safe .docx 산출 |

### P2 — 기능 확장 (v1.0)

| ID | 항목 | 근거 | 공수 | 수용 기준 |
|---|---|---|---|---|
| **U-14** | 반복 실행 경로 — ① 로컬: `bin/jobstack-cron`(cron/launchd + `claude -p "/job_search …" --permission-prompts none`)로 공고 모니터링·마감 D-day 요약 파일 생성 ② 클라우드: Routines 가이드(`/schedule`, 저장소에 익명화된 검색 조건만 두고 결과는 PR/파일로) | 1-4 반복 실행, 2-1 Routines | M | 매일 아침 `job-cache/daily-YYYY-MM-DD.md`가 생성되고 tracker 정체 넛지가 포함됨 |
| **U-15** | Claude in Chrome 경로 — scout-profile(원티드·링크드인 프로필 읽기/반영), company-research(잡플래닛 상세·리뷰), job-search(로그인 필터)에서 확장 설치 시 선택 가능한 경로 문서화. 자동 제출·자동 지원은 비목표 | 1-4 로그인 사이트 | S~M | 확장 미설치 시 현행 붙여넣기 경로로 폴백 |
| **U-16** | 스킬 eval 체계 — skill-creator 하네스 형식(`evals/evals.json`의 `expectations`, grader 에이전트)을 채택해 INFRA-8 trait 케이스 5종 구현. `test/run-evals.sh`가 `claude -p`로 샘플 입력을 실행하고 `test/golden`의 must_contain·`lint-conventions.sh`를 결정적 expectations로 재사용. gstack처럼 무료(결정적)/LLM 심사/E2E 3계층으로 나눠 PR 게이트와 야간 실행을 구분. 설명 트리거 최적화는 `run_loop.py`(should_trigger 쿼리 20개) 활용. `claude plugin eval`(조기 접근)은 공개 시 대체 | 1-4 품질 평가, 2-3 | L | 5개 스킬 각 3케이스, 회귀 시 CI 실패, 스킬별 트리거 정확도 기록 |
| **U-17** | NCS 개편 반영 — ncs·cover-letter(공기업 소절)·mock-interview(E 모드)·resume(블라인드 체크)에 고정된 "직업기초능력 10개 영역" 목록을 `ncs/references/competencies.md`(구 10영역·34하위 / 신 '직업공통능력' 7영역·21하위 병행)로 옮기고, 지원 기관 공고가 어느 체계를 쓰는지 실행 시 확인하는 규칙 추가. **착수 전 산인공 원문 확인 필수**(§2-4 `[2차]`) | 2-4 NCS | M | 두 체계 매핑표 존재, 스킬 본문에 영역 목록 하드코딩 0건, 원문 URL·기준일 병기 |
| **U-18** | claude.ai/Cowork 배포 — U-04 폴백 완성 후 스킬을 claude.ai 계정 스킬로 업로드 가능하게 `!`·Bash 비의존 모드 지원 | 2-1 Cowork | M | Cowork 세션에서 /resume 첨삭이 동작 |
| **U-19** | 모델·effort 라우팅 — 스킬 프론트매터로 분류·라우팅(auto Phase 1, tracker 명령 감지)은 `model: sonnet` + `effort: low`, 문서 첨삭·면접·기업분석은 `model: opus` + `effort: high`. Haiku 4.5는 은퇴 하한(2026-10-15) 때문에 제외, Fable 5.1은 eval에서 이득이 확인된 스킬에만. Claude Code 2.1.259 이상 전제 | 2-2 | S | 스킬별 비용·지연·골든 trait 비교표 작성 후 기본값 확정 |
| **U-20** | 운영 학습 로그 — gstack `learnings.jsonl` 패턴을 축소 도입: 스킬 종료 시 "운영상 배운 것"(어느 플랫폼 셀렉터가 깨졌는지, 어떤 자료 요청이 반복되는지)을 `$_JS_STATE/analytics/learnings.jsonl`에 메타만 기록하고 auto 대시보드가 상위 3건을 보여줌. 사용자 문서 내용은 기록하지 않음(telemetry-events.md PII 규칙 준수) | 2-3 gstack | M | 이벤트 어휘를 `docs/telemetry-events.md`에 정식 추가한 뒤에만 append |
| **U-21** | 구조화 전형 대응 — cover-letter에 '경험기술서 모드'(예: 직무전문성 / AI 기반 문제 해결 경험, 문항별 글자수 게이트, 결이요 대신 문제·역할·행동·결과 4분리 우선)와 '문답형 상세지원서 모드'(수십 문항 일괄 초안 + 답변 간 사실 일관성 검사)를 추가하고, experience-bank 카드에 `ai_usage`(어떤 도구로 무엇을 얼마나 개선했는지) 태그를 신설. 기업별 전형 형식은 실행 시 공고에서 확인 | 2-4 전형 구조 | M | 샘플 경험기술서 문항 세트에서 4분리·수치·글자수 게이트 통과, 문답형 모드에서 답변 간 모순 검출 |
| **U-22** | AI 협업 평가 대비 — mock-interview E(기술) 모드에 'AI 도구 활용 과제' 서브모드(문제 접근→프롬프트 설계→출력 검증 근거→수정 이력 기록을 코칭), company-research 전형 확인 항목에 ⑥ '코딩테스트·과제에서 AI 사용 허용 여부' 추가(기업별로 다르므로 검색 확인·미확인 시 "사용 안 함이 안전" 안내) | 2-4 AI 활용 채용 | S~M | 서브모드 1회 진행 리포트에 검증 근거·수정 이력 항목 존재 |
| **U-23** | 제도·지원금 체크리스트 — tracker '탈락 후 권리 체크리스트'와 salary·strategy에 '지원 시 정책 인센티브'(비수도권 취업 청년 직접 지원, 구직촉진수당, 주4.5일제 도입 기업, 채용절차법 임금명시 개정 진행 상황) 항목을 두되 수치·시행 여부는 실행 시 WebSearch로 확인. U-14 반복 실행으로 분기 1회 갱신 알림 | 2-4 제도 | S | 항목당 출처·기준일 병기, 시장 수치 린트 통과 |

### 기각·보류 (사유 보존)

- **스킬을 코드(Agent SDK 앱)로 재작성**: 프롬프트 기반 스킬이 Claude Code·Cowork·봇 러너 세 곳에서 재사용되는 현 구조의 강점을 버리게 됨. 결정적 부분만 스크립트화(U-09)로 충분. `[추론]`
- **insane-search 전체 흡수·사이트별 파서 이전**: 선행 계획서 §6 비목표와 동일하게 유지.
- **tracker/ncs를 봇 노출 스킬로 복귀**: 운영자 확정 정책(v0.2.0) 유지. 대신 CLI에서는 `user-invocable`·`disable-model-invocation`로 노출 방식만 정리.
- **자동 지원·자동 제출(Chrome)**: 사용자 동의·플랫폼 약관·사실 검증 문제로 비목표. 읽기·초안 반영까지만.
- **플랫폼식 '서류 합격 확률·연봉 예측' 점수**: 사람인·잡코리아·원티드가 자사 데이터로 제공하는 영역. LLM 즉석 예측은 선행 계획서가 기각한 유사 정밀 점수와 같은 문제이므로 도입하지 않는다. 결정적으로 계산 가능한 ATS 키워드 매칭률(U-09 `jobstack-ats-match`)까지만 제공한다. `[추론]`

---

## 4. 로드맵 제안

| 마일스톤 | 범위 | 게이트 | 공수 추정 |
|---|---|---|---|
| **v0.4.0 — 결함 수정** | U-01 ~ U-06 | CI 녹색 + 심링크 설치에서 `claude -p "/auto"` 가드레일 주입 실측 + CHANGELOG·태그 | 1~2일 |
| **v0.5.0 — 실행 기반 현대화 + 시장 정합** | U-07 플러그인, U-08 분할, U-09 스크립트, U-10 서브에이전트, U-11 hwpx, U-12·U-13 수집·내보내기, U-17 NCS 개편, U-21 구조화 전형 | `claude plugin validate --strict`, SKILL.md ≤ 300줄, 골든·eval 회귀 없음, E2E 리포트 재작성(16 스킬), NCS·전형 변경 원문 확인 기록 | 2~3주 |
| **v1.0 — 기능 확장** | U-14 반복 실행, U-15 Chrome, U-16 eval, U-18 Cowork, U-19 라우팅, U-20 학습 로그, U-22 AI 협업 평가, U-23 제도 체크리스트 | 야간 eval CI, 마켓플레이스 공개, README·E2E 갱신 | 2~3주 |

의존 관계: U-01·U-04(경로·프리앰블)가 U-07(플러그인)·U-18(Cowork)의 선행 조건이다. U-09(스크립트)는 U-16(eval)의 결정적 판정 근거가 된다. U-08(분할)은 U-10(서브에이전트)과 같은 PR에서 스킬별로 묶어 진행하는 편이 재작업이 적다.

---

## 5. 리스크와 완화

| 리스크 | 완화 |
|---|---|
| `!` 동적 주입이 Cowork·동기화 스킬·`disableSkillShellExecution` 환경에서 실행되지 않음 | 주입 자리 아래에 "위 블록이 비어 있으면 Bash로 `jobstack-preamble`를 실행" 폴백 1줄 유지(U-04), 가드레일은 `references/` 복제본으로 이중화(U-01) |
| 플러그인 네임스페이스(`/jobstack:auto`)가 README·봇 표기와 어긋남 | 충돌 없으면 `/auto`도 동작(문서 확인). 봇은 자체 러너라 무관. `templates/BOT-COMMAND-STYLE.md`에 CLI 표기 규칙 1절 추가 |
| 스킬 분할 시 골든 trait 회귀 | U-08 전에 U-16의 최소 케이스(5스킬×1)를 먼저 만들어 분할 전후 비교 |
| 수집 계층 리팩터링 중 사이트 개편 | 플랫폼별 HTML 픽스처를 저장소에 두고 파서 단위 테스트, `fetch-diag.log`로 실패 원인 추적(기구현) |
| Routines/클라우드 세션에서 개인정보(프로필·이력서) 취급 | 클라우드에는 검색 조건·회사명 같은 최소 메타만 두고 문서·프로필은 로컬 전용 유지. `docs/telemetry-events.md`의 consent 원칙을 클라우드 실행 문서에도 적용 |
| 의존성 갱신(Playwright·curl_cffi)으로 스텔스·프로파일명 변경 | §2-3의 버전·변경점 기준으로 핀을 올리고 어댑터 테스트(`test-is-fetch-adapter.mjs`)로 프로파일명 동기화 검증 |

---

## 부록 A. 실측 로그 (Claude Code v2.1.259, 2026-09-03)

```text
# T1 디스커버리 — ~/.claude/commands/<dir> 심링크 + SKILL.md
$ claude -p "Print the complete list of custom skills ..."   → auto, cover_letter (목록 노출)
# T1' — ~/.claude/skills/<dir> 심링크
                                                             → auto, cover-letter (목록 노출)

# T2 치환값 — 임시 스킬 zz-test: "Reply with DIR=${CLAUDE_SKILL_DIR}"
commands/ 심링크: DIR=/root/.claude/commands/zz-test   (실경로 아님)
skills/   심링크: DIR=/root/.claude/skills/zz-test     (실경로 아님)

# T3 경로 해석 — 임시 스킬 zz-read (심링크 설치)
Read  ${CLAUDE_SKILL_DIR}/../templates/probe.md  → READ=FAILED, file does not exist
Bash  "${CLAUDE_SKILL_DIR}/../bin/probe.sh"       → BASH=BIN_OK_67890
node  path.resolve(link/../templates/probe.md)    → <SP>/templates/probe.md (어휘적 정규화)
node  fs.readFileSync(비정규화 경로)              → OK

# T4 설명 절단 — 16개 스킬 설치 후 auto/cover-letter/scout-profile/job-search 설명 요청
scout-profile 709자 설명이 절단 없이 그대로 노출. --debug 로그에 budget 경고 없음.

# 뷰어 — '</script> 태그'를 포함한 md → 생성 HTML 291행에 원문 그대로 삽입(치환 no-op)
```

## 부록 B. 출처

- Claude Code 스킬: https://code.claude.com/docs/en/skills (프론트매터 표, 치환 변수, `!` 주입, 목록 예산, Cowork 절)
- 플러그인 레퍼런스: https://code.claude.com/docs/en/plugins-reference · 마켓플레이스: https://code.claude.com/docs/en/plugin-marketplaces
- 훅: https://code.claude.com/docs/en/hooks · 서브에이전트: https://code.claude.com/docs/en/sub-agents · 메모리·규칙: https://code.claude.com/docs/en/memory
- Routines: https://code.claude.com/docs/en/routines · Claude in Chrome: https://code.claude.com/docs/en/chrome · 헤드리스: https://code.claude.com/docs/en/headless
- CHANGELOG: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (v2.1.259)

- 의존성: https://registry.npmjs.org/playwright · https://github.com/microsoft/playwright/blob/main/docs/src/release-notes-js.md · https://pypi.org/project/curl-cffi/ · https://github.com/lexiforest/curl_cffi/releases · https://github.com/lexiforest/curl_cffi/blob/main/docs/impersonate/targets.rst · https://github.com/nodejs/Release · https://nodejs.org/en/blog/release/v26.0.0 · https://github.com/jgm/pandoc/blob/main/changelog.md · https://registry.npmjs.org/marked · https://github.com/markedjs/marked · https://www.npmjs.com/package/docx · https://github.com/Kaliiiiiiiiii-Vinyzu/patchright-nodejs
- 참조 프로젝트: https://github.com/garrytan/gstack (CHANGELOG 1.79.0.0, ARCHITECTURE.md) · https://github.com/fivetaku/insane-search (CHANGELOG 0.16.0, PLATFORMS.md) · https://github.com/anthropics/skills (skill-creator `references/schemas.md`)
- 사이트 표면 간접 근거(2026-04 기준 제3자 코드): hayan89/claude-channel-mattermost, NoirStar/dev-jobs-radar, bokang03/job-posting-automation (GitHub 코드 검색)

- Claude 플랫폼: https://platform.claude.com/docs/en/models/overview · https://platform.claude.com/docs/en/about-claude/pricing · https://platform.claude.com/docs/en/about-claude/models/choosing-a-model · https://platform.claude.com/docs/en/build-with-claude/structured-outputs · https://platform.claude.com/docs/en/build-with-claude/pdf-support · https://platform.claude.com/docs/en/build-with-claude/files · https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool · https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-fetch-tool · https://platform.claude.com/docs/en/build-with-claude/prompt-caching · https://platform.claude.com/docs/en/build-with-claude/batch-processing · https://platform.claude.com/docs/en/api-and-data-retention · https://platform.claude.com/docs/en/test-and-evaluate/strengthen-guardrails/mitigate-jailbreaks · https://platform.claude.com/docs/en/managed-agents/scheduled-deployments
- Agent SDK·헤드리스·채널: https://code.claude.com/docs/en/agent-sdk/overview · https://code.claude.com/docs/en/agent-sdk/hosting · https://code.claude.com/docs/en/agent-sdk/user-input · https://code.claude.com/docs/en/agent-sdk/permissions · https://code.claude.com/docs/en/agent-sdk/cost-tracking · https://code.claude.com/docs/en/cli-reference · https://code.claude.com/docs/en/channels

- 한국 채용시장(원문 접근은 차단, 검색 요약 기준): 경총 https://eiec.kdi.re.kr/policy/domesticView.do?ac=0000203504 · 인크루트 https://www.kado.net/news/articleView.html?idxno=2067618 · 잡코리아 https://www.newspim.com/news/view/20260810000140 · 원티드랩 https://zdnet.co.kr/view/?no=20251208160526 · 고용노동부 채용동향조사 https://www.moel.go.kr/news/enews/report/enewsView.do?news_seq=18662 · 무하유 https://www.etnews.com/20260109000170 · SK하이닉스 https://biz.heraldcorp.com/article/10825158 · 한화생명 https://www.thefairnews.co.kr/news/articleView.html?idxno=85777 · 넥슨 https://www.asiae.co.kr/article/2026082516042397206 · 코딩테스트 AI https://www.jobkorea.co.kr/goodjob/tip/view?News_No=22546 · NCS 개편 https://www.ajunews.com/view/20260428105725136 · 공공기관 채용 https://www.korea.kr/news/policyNewsView.do?newsId=148958627 · 채용절차법 개정안 https://watch.peoplepower21.org/BillDetail/2216004 · 청년일자리도약장려금 https://www.moel.go.kr/news/notice/noticeView.do?bbs_seq=20260100030
- 공식 API: https://oapi.saramin.co.kr/guide/job-search · https://openapi.wanted.jobs/ · https://m.work24.go.kr/cm/e/a/0110/selectOpenApiIntro.do · https://www.data.go.kr/data/15125273/openapi.do
- HWP/HWPX: https://pypi.org/project/python-hwpx/ · https://github.com/chrisryugj/kordoc · https://github.com/edwardkim/rhwp · https://pypi.org/project/pyhwp/ · https://github.com/ebandal/H2Orestart · https://www.hancom.com/support/downloadCenter/hwpOwpml
