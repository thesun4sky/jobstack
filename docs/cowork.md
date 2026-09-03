# claude.ai / Cowork 에서 jobstack 쓰기 (U-18)

Cowork 와 claude.ai 는 `~/.claude/skills/` 나 플러그인 캐시를 읽지 않고, 계정에 업로드한 스킬만 로드한다(출처: code.claude.com/docs/en/skills 의 "Skills in Cowork and cloud sessions" 절, 2026-09-03 원문 확인 — 검토 보고서 §2-1 `[사실]` 항목과 같은 근거; 실제 Cowork 세션에서의 동작은 아래 확인 상태대로 미검증). 이 저장소의 스킬은 `bin/` 스크립트와 `~/.jobstack/` 상태 디렉토리를 전제로 만들어졌으므로, 업로드 환경에서는 **Bash·상태 비의존 모드**로 동작한다.

> 확인 상태: 이 문서의 동작 설명은 저장소 안에서 재현 가능한 부분(패키지 구성·폴백 컨텍스트·참조 무결성)만 테스트했다(`test/test-package-skill.sh`). 실제 Cowork 세션에서의 `/resume` 첨삭은 이 저장소를 검토한 환경에서 실행할 수 없어 **미검증**이다. 업로드 후 첫 실행에서 아래 "확인 항목"을 점검한다.

## 패키지 만들기

```bash
bin/package-skill.sh all            # dist/skills/<skill>.zip 16개
bin/package-skill.sh resume         # 하나만
```

zip 에는 `SKILL.md`, `references/**`, `scripts/preamble.sh` 만 들어간다. `bin/`·`templates/`·`docs/` 는 넣지 않는다 — 참조는 이미 `references/` 복제본으로 스킬 안에 들어 있다(v0.4.0 D-1 수정의 결과).

## 업로드 환경에서 달라지는 것

| 항목 | 저장소·플러그인 설치 | 업로드(Cowork·claude.ai) |
|---|---|---|
| 프리앰블 `!` 주입 | 실행됨 | 실행되지 않을 수 있음 → SKILL.md 상단 안내대로 첫 Bash 로 `scripts/preamble.sh` 실행. Bash 도 없으면 컨텍스트 없이 진행 |
| `scripts/preamble.sh` | `bin/jobstack-preamble` 실행 | bin 이 없어 폴백 컨텍스트(`PREAMBLE_FALLBACK=true`, `JS_BIN=unresolved`) |
| 가드레일 | `!` sed 주입 | `references/guardrails.md` 를 Read (상단 안내) |
| 상태 저장(프로필·경험뱅크·지원 현황·방어맵) | `bin/jobstack-*` 스크립트 | 저장 단계 생략 — 결과는 채팅·파일 산출물로만 남김 |
| 수집(job-search)·내보내기(docx)·한글 변환 | 스크립트 | 불가 → 자료 요청(공고 본문 붙여넣기)·마크다운 산출로 폴백 |
| 리서치 서브에이전트 | Agent 도구 | 도구가 없으면 순차 WebSearch |

## 스킬별 기대 동작

- **온전히 동작**: resume·cover-letter·career-history·review·mock-interview·strategy·portfolio·scout-profile·ncs·experience-bank(카드는 채팅으로 제시) — 방법론·게이트·references 가 모두 패키지 안에 있다.
- **축소 동작**: company-research·salary(WebSearch 만), job-search(붙여넣은 공고 분석만), auto(파일 스캔은 가능하나 대시보드의 상태 파일은 없음), tracker(스크립트 없음 — 표로만 정리), retro(집계 스크립트 없음).

## 업로드 후 확인 항목

1. 스킬을 호출했을 때 상단 실행 컨텍스트가 `KEY=VALUE` 로 보이는가, 아니면 `!` 명령이 그대로 보이는가(후자면 첫 Bash 실행 안내가 작동하는지).
1-1. `/resume` 은 Claude Code 내장 "대화 재개" 명령과 이름이 같다 — 업로드 환경에서 `/resume` 을 쳤을 때 이력서 스킬이 뜨는지, 아니면 자연어("이력서 첨삭해줘")로 불러야 하는지 확인한다.
2. `references/guardrails.md` 를 Read 하는가(가드레일 §1 개인정보·§2 자료 요청 전환이 적용되는지).
3. 상태 파일을 쓰려 하지 않고 채팅 산출물로 마무리하는가.
4. 문제가 있으면 `docs/plans/version-upgrade-review-2026-09.md` U-18 항목에 실측을 남긴다.
