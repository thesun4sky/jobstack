# 프리앰블 (v0.4.0 — 동적 주입)

v0.3.0까지는 이 파일의 bash 블록을 16개 SKILL.md 상단에 복사해 두고 모델이 Bash 도구로 실행했다.
복사본이 스킬마다 드리프트했고(9~40줄 차이), 실행에 턴 하나와 권한이 들었다.

v0.4.0부터 프리앰블은 **한 스크립트**이며, 스킬 로드 시점에 Claude Code의 동적 주입으로 실행된다.

```markdown
!`bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" <skill> "${CLAUDE_SESSION_ID}"`
```

- `scripts/preamble.sh` — 생성 파일(원본 `templates/skill-preamble.sh`). 스킬 디렉토리의 **실경로**를 따라 올라가 `bin/jobstack-preamble`를 찾아 실행한다. 심링크 설치에서 `${CLAUDE_SKILL_DIR}`가 심링크 경로로 치환되어도 동작한다.
- `bin/jobstack-preamble` — 실행 컨텍스트 본체. 상태 디렉토리 생성, 런타임(cli/bot) 판정, 세션 파일, 설정(PROACTIVE), KST 기준일, 프로필·경험 카드 존재 여부, 수집 도구 가용성, `env.sh` 작성, 텔레메트리 entry 기록을 한 번에 한다.
- 출력은 프롬프트에 그대로 삽입된다. 불변식: `SKILL_NAME` / `JOBSTACK_RUNTIME` / `PROACTIVE` / `ACTIVE_SESSIONS` / `JS_BIN` / `JS_STATE` 가 `KEY=VALUE` 로 나온다 (`test/test-preambles.sh`).

## 변수 전달 — env.sh

동적 주입은 별도 셸에서 실행되므로 변수가 이후 Bash 도구 호출에 남지 않는다. 프리앰블은 `$JS_STATE/env.sh`에 `_JS_STATE`, `_JS_BIN`, `_JS_BROWSER_SCRIPT`, `JOBSTACK_FETCH_DIAG_LOG`, `TODAY`, `JOBSTACK_RUNTIME`를 쓰고, 스킬의 Bash 스니펫은 첫 줄에서 이를 source 한다:

```bash
. "${JOBSTACK_STATE_DIR:-$HOME/.jobstack}/env.sh"
```

## 폴백

- `!` 명령이 실행되지 않는 환경(Cowork·claude.ai 동기화 스킬·`disableSkillShellExecution` 정책)에서는 SKILL.md 상단 안내대로 첫 Bash 명령으로 같은 스크립트를 직접 실행한다.
- `bin/`을 찾지 못하는 설치(SKILL.md만 복사된 환경)에서는 `scripts/preamble.sh`가 최소 컨텍스트(`PREAMBLE_FALLBACK=true`)를 출력한다.

## 봇 런타임

`JOBCLAW_RUN_ID`가 있으면(또는 `JOBSTACK_RUNTIME=bot`) `JOBSTACK_RUNTIME=bot`이 되고, SKILL.md의 두 번째 주입 라인이 `references/bot-protocol.md`(`templates/bot-protocol.md` + `templates/bot/<skill>.md`)를 프롬프트에 넣는다. CLI에서는 주입되지 않는다.
