# 스킬 eval 체계 (U-16)

`docs/plans/version-upgrade-review-2026-09.md` U-16의 실행 형태. skill-creator 하네스(`evals/evals.json`
의 `expectations` 배열)와 gstack의 3계층(무료 결정적 / LLM 채점 / E2E) 구분을 채택해, jobstack 골든
테스트(`test/golden`)의 trait 판정과 `test/lint-conventions.sh`의 금지 표현 목록을 각 케이스의
`expectations`로 재사용한다.

기존 `test/golden`이 "산출물 md를 사람이 스킬로 만들어 온 뒤 `run-golden.sh <산출물> <케이스>`로 반수동
채점"하는 구조라면, 이 체계는 `claude -p`로 스킬을 **직접 실행**해 산출·도구 호출까지 자동으로 판정한다.
`test/golden`을 대체하지 않는다 — tracker v1 호환 매핑표 검증처럼 스킬 실행 없이 데이터 정합성만
보는 결정적 케이스는 계속 `run-golden.sh`가 담당하고, 이 체계의 `tracker-gate-v1-migration-list`
케이스는 같은 입력·기대 특성을 재사용해 "실제 스킬 실행에서도 유지되는가"를 추가로 검증한다.

---

## 3계층

| 계층 | 채점 방식 | 실행 시점 | 성격 |
|---|---|---|---|
| **gate** | 결정적 — `expectations`를 grep/토큰 매칭으로 자동 PASS/FAIL | PR 게이트 후보 | 저비용·고신뢰. `bin/jobstack-tracker`·`bin/jobstack-exp.mjs`·`bin/jobstack-ats-match` 같은 결정적 스크립트 출력을 스킬이 그대로 relay하는지 확인하는 케이스 위주 — 모델 출력의 자유도가 낮아 회귀에 민감하다 |
| **periodic** | LLM 채점(`claude -p --model haiku`) 병행 | 야간 배치 | 코칭 톤·"결이요"·미끼 배치·날조 금지 준수처럼 grep만으로 판정하기 어려운 질적 특성. 결정적 `expectations`도 함께 확인하지만 최종 판정은 "결정적 통과 AND LLM 채점 PASS" |
| **e2e** | 결정적 또는 LLM(케이스별 `grader`로 지정) | 야간 배치 | 여러 Phase·여러 스크립트 호출이 한 세션 안에서 이어지는 전체 흐름. `max_turns`가 더 크고 비용이 더 든다 |

같은 스킬 안에서도 케이스마다 계층·채점 방식이 다를 수 있다 — 이 저장소의 5개 스킬(auto·resume·
cover-letter·tracker·experience-bank) 초안은 스킬당 gate 1·periodic 1·e2e 1로 구성했다
(`evals/<skill>/evals.json`).

**PR 게이트로는 gate 계층만 켠다.** periodic·e2e는 `claude -p` 호출 비용과 LLM 채점 비용이 들어
매 PR마다 돌리기엔 비싸고, 결과가 모델 버전·재현성에 더 민감하다 — 야간 1회로 충분하다.

---

## evals.json 형식

`evals/<skill>/evals.json` 한 파일당 스킬 하나. 형식:

```json
{
  "skill": "tracker",
  "cases": [
    {
      "id": "tracker-gate-v1-migration-list",
      "tier": "gate",
      "prompt": "지원 현황 목록 보여줘.",
      "files": [],
      "setup": ["mkdir -p \"$STATE_DIR/tracker\"", "cp \"$REPO/test/golden/tracker/v1-compat/input.jsonl\" \"$STATE_DIR/tracker/applications.jsonl\""],
      "expectations": {
        "must_contain": ["진행중", "대기중", "종료"],
        "must_not_contain": ["다각적", "합격 보장"],
        "must_call": ["jobstack-tracker list"],
        "must_read": [],
        "max_turns": 6
      },
      "grader": "deterministic",
      "note": "사람이 읽는 케이스 설계 의도 — 파서는 무시해도 되는 선택 필드"
    }
  ],
  "should_trigger": [
    {"query": "지원 현황 목록 보여줘", "expect": true},
    {"query": "이력서 첨삭해줘", "expect": false}
  ]
}
```

- **`files`**: 저장소 상대 경로(`test/sample-data/…`). 케이스 작업 디렉토리(격리 HOME 아래 임시
  워크스페이스)로 파일명만 남기고 복사된다 — 스킬이 Glob·Read로 발견하는 입력.
- **`setup`**: 케이스 실행 **전** 상태를 미리 만드는 쉘 명령 목록. 각 명령은 **한 줄**이어야 한다
  (여러 줄 heredoc 금지 — 파서가 줄 단위로 파싱한다). `$REPO`(저장소 경로)·`$STATE_DIR`(격리
  `JOBSTACK_STATE_DIR`)·`$HOME`(격리 HOME)을 참조할 수 있다. tracker 케이스들은 이걸로
  `test/golden/tracker/v1-compat/input.jsonl`을 그대로 시드해, 골든 테스트의 기대 특성을 재사용한다.
- **`expectations.must_contain` / `must_not_contain`**: 최종 산출 텍스트(전체 assistant 텍스트를
  이어붙인 것) + 케이스 작업 디렉토리에 새로 생긴 파일 내용을 합친 문자열에 대해 **부분 문자열**로
  판정한다. `test/golden`의 must_contain은 누락 시 WARN(반수동 확인)이지만, 이 체계는 `claude -p`로
  실제 실행까지 자동화하므로 **누락 시 그대로 FAIL**한다 — 더 엄격하다.
- **`expectations.must_call`**: 문자열 하나를 공백으로 나눈 각 단어가, 이 케이스 실행 중 기록된
  **모든 Bash 도구 호출 명령을 이어붙인 문자열**에 전부 등장하는지로 판정한다. 한 Bash 호출 안에
  다 있을 필요는 없다(예: `env.sh` 소싱과 스크립트 호출이 서로 다른 Bash 호출로 나뉘어도 통과) —
  대신 단어가 우연히 다른 호출에 흩어져 있어도 통과하는 느슨함이 있다. 실행 로그가 남는 결정적
  스크립트 호출(`jobstack-tracker`·`jobstack-exp.mjs`·`jobstack-ats-match` 등) 확인에 쓴다.
- **`expectations.must_read`**: 문자열이 이 케이스 실행 중 기록된 **모든 Read 호출 경로를 이어붙인
  문자열**에 부분 문자열로 등장하는지로 판정한다. 주로 `references/*.md` — 어느 Phase의 참조 자료를
  실제로 읽었는지 확인한다.
- **`expectations.max_turns`**: `claude -p --max-turns`에 그대로 전달.
- **`grader`**: `deterministic`(위 판정만) 또는 `llm`(위 판정 + haiku 채점, 둘 다 통과해야 PASS).
- **`should_trigger`**: 스킬당 자연어 요청 8~10개, `expect: true`(이 스킬이 트리거돼야 함)
  /`false`(다른 스킬이거나 애매해서 이 스킬이 뜨면 안 됨). `run-evals.sh --trigger`가 채점한다 —
  cases와 별도 실행(비용이 다르게 든다).

---

## 실행 방법

```bash
# 전체 15케이스 나열만(과금 없음) — claude CLI 가 없어도 동작
test/run-evals.sh --dry-run

# gate 계층만 (PR 게이트 후보)
test/run-evals.sh --tier gate

# 스킬 하나만, 특정 모델로
test/run-evals.sh --skill tracker --model sonnet

# 트리거 정확도 (스킬당 8~10건 별도 호출 — 비용 안내 출력됨)
test/run-evals.sh --trigger --skill resume
test/run-evals.sh --trigger --dry-run   # 나열만
```

`claude` CLI를 찾지 못하거나 `--dry-run`이면 케이스·실행 예정 명령만 출력하고 항상 exit 0 한다(CI가
`claude` 미설치 상태로 이 스크립트를 우발적으로 부르더라도 실패하지 않는다 — 단, 이는 "돌지 않음"이지
"통과"가 아니므로 **PR 게이트로 쓸 때는 `claude` 가용성을 별도로 확인**해야 한다. §"CI 미포함 이유"
참조).

각 케이스는 `mktemp` 격리 HOME에서 `install.sh`로 스킬을 심링크 설치한 뒤, 그 HOME 아래 별도
작업 디렉토리에서 `claude -p --output-format stream-json --verbose --model <model>
--permission-mode auto --max-turns N "<prompt>"`를 실행한다(실제 저장소 파일은 절대 건드리지
않는다 — 읽기는 `$REPO`에서, 상태는 격리 `JOBSTACK_STATE_DIR`에서). `--permission-mode auto`은
과제 스펙의 예시 명령에는 없지만, 이 플래그 없이는 Bash·Write 권한 승인을 기다리며 무인 실행이
멈춘다(검토 보고서 §2-2가 "무인 호스트용"으로 명시한 2.1.259 플래그) — 헤드리스 실행이 목적이므로
추가했다.

스트림에서 `tool_use`(Bash 명령·Read 경로)와 텍스트를 모아 `expectations`를 판정하고,
`test/eval-report.md`(표)와 `test/eval-report.json`(전체 판정 근거)에 쓴다. `--trigger`는 별도로
`test/eval-trigger-report.md`(스킬별 TP/FP/TN/FN·정확도)를 쓴다. 실패한 케이스는 진단을 위해 격리
HOME을 지우지 않고 로그 경로를 리포트에 남긴다(통과한 케이스는 정리).

### 헤드리스 실행과 AskUserQuestion

`claude -p` 한 번 호출 안에서도 모델은 AskUserQuestion을 여러 번 쓸 수 있지만, 실제 사람이 답하는
것은 아니므로 케이스 프롬프트를 **선제적으로 정보가 충분하도록** 작성해야 한다(예: "확인 질문 없이
진행해주세요", 6단계 정보를 프롬프트 하나에 다 담기). `resume-periodic-pii-sample-guard`처럼 질문
발생 **자체**가 판정 대상인 케이스는 예외 — 그 경우 흐름이 질문에서 멈춰도 `must_contain`이 이미
출력된 질문 문구를 잡아내면 통과한다. 새 케이스를 쓸 때 이 두 유형 중 어느 쪽인지 `note`에 남겨두면
좋다.

---

## 비용 추정 방식

**금액을 단정하지 않는다**(가드레일 §3과 동일 원칙 — 모델 가격은 바뀐다). 대신 다음 두 축으로
상대 비용을 가늠한다:

1. **케이스당 턴 수 × 모델**: `max_turns`가 예산 상한이고, `result` 이벤트의 `num_turns`·
   `total_cost_usd`가 실측값이다(리포트 JSON의 `result_summary`에 보존). gate 케이스는 6~10턴,
   e2e는 14~18턴으로 설계했다 — e2e가 gate보다 요청당 비쌀 확률이 높다.
2. **grader가 늘리는 호출 수**: `llm` 케이스는 본 실행 1회 + haiku 채점 1회(1턴)가 추가로 든다.
   `--trigger`는 케이스당 1턴짜리 호출을 쿼리 수(스킬당 8~10건)만큼 반복한다 — 회당 비용은
   작지만 횟수가 많다.

실측 금액이 필요하면 `test/eval-report.json`의 `result_summary.total_cost_usd`(스트림의 `result`
이벤트 실측치, Anthropic API가 산출)를 합산하되, Claude Agent SDK 문서가 명시하듯 이 값은
**추정치이지 청구 근거가 아니다**(검토 보고서 §2-2). 주기적으로 절감하려면 Batch API(50% 할인,
24시간 이내 완료 — 검토 보고서 §2-2)를 nightly periodic/e2e 실행에 적용하는 것을 후속 과제로 남긴다.

---

## 케이스 추가 규칙

1. **개인정보 없는 가상 샘플만** 쓴다. `test/sample-data`의 기존 홍길동 픽스처를 우선 재사용하고,
   새 픽스처가 필요하면 같은 디렉토리에 같은 방식(가상 인물·가상 회사)으로 추가한다.
2. **최소 1개 케이스는 결정적 스크립트 출력에 근거**하게 만든다 — `bin/jobstack-tracker`,
   `bin/jobstack-exp.mjs`, `bin/jobstack-ats-match`처럼 같은 입력이면 같은 출력이 나오는 스크립트의
   산출을 스킬이 그대로 relay하는지 확인하는 케이스가 gate 후보 1순위다(회귀에 가장 민감하고
   가장 싸다).
3. **`test/golden`과 `test/lint-conventions.sh`를 재사용**한다 — 새로 금지어 목록을 만들지 말고
   `test/lint-conventions.sh`의 AI 만능 표현(다각적·포괄적·심층적·혁신적·체계적)·금지 표현(합격
   보장·무조건 통과·전문가가 직접 첨삭·AI 대체 불가) 9개를 모든 케이스의 `must_not_contain`
   기본값으로 둔다. `test/golden/<skill>/<case>`가 있으면 그 `expected-traits.yaml`의
   `must_contain`/`must_not_contain`을 그대로 가져와 케이스를 만든다(tracker가 이 방식).
4. **`setup` 명령은 한 줄**로 쓴다(파서가 줄 단위로 읽는다). 여러 단계가 필요하면 `&&`로 잇거나
   여러 항목으로 나눈다.
5. **`prompt`에 개행이 필요하면**(JD 원문 붙여넣기 등) JSON 문자열 안에 `\n`으로 넣는다 — 실행 시
   그대로 한 번의 사용자 메시지로 전달된다.
6. **tier는 비용·판정 방식으로 정한다**, 스킬 커버리지로 정하지 않는다 — 결정적으로 grep 가능하고
   싸면 gate, 질적 판단이 필요하면 periodic, 여러 Phase·여러 스크립트가 한 세션에서 이어져야
   확인되면 e2e.
7. **`should_trigger`는 참/거짓을 섞는다** — 이 스킬을 향한 자연어 요청뿐 아니라, 인접 스킬(예:
   resume ↔ career-history ↔ review)을 향한 요청도 `expect: false`로 넣어야 과잉 트리거(FP)를
   잡을 수 있다.
8. 새 스킬을 추가하면(예: v1.0 로드맵의 다른 항목이 스킬을 늘리면) `evals/<skill>/evals.json`을
   새로 만들고 `test/run-evals.sh`는 고치지 않아도 된다(`evals/*/evals.json`을 자동 탐색).

---

## 알려진 한계 (초안 단계)

- **`must_call`의 흩어짐 허용**: 여러 Bash 호출을 이어붙여 판정하므로, 실제로는 스크립트를 안
  불렀는데 다른 맥락에서 우연히 같은 단어가 등장해 통과로 오판할 여지가 이론상 있다(현재 케이스
  설계에서는 발생 가능성이 낮다 — 토큰이 `jobstack-tracker add --company --position`처럼 스크립트
  이름을 포함해 충분히 구체적이다).
- **LLM 채점의 비결정성**: `grader: llm` 케이스는 같은 산출물에도 채점이 매번 완전히 같지 않을 수
  있다 — periodic/nightly로만 쓰고 PR 게이트에 넣지 않는 이유다.
- **AskUserQuestion과 단일 헤드리스 호출의 상호작용**: 위 "헤드리스 실행과 AskUserQuestion" 절
  참조 — 확실히 검증되지 않은 영역이라 케이스 설계로 우회했다.
- **트리거 판정은 `Skill` 도구 호출 1건만** 본다 — 모델이 스킬을 부르지 않고 인라인으로 답했지만
  사실상 올바르게 대응한 경우(예: 아주 짧은 질문에 스킬 로드 없이 바로 답함)를 오탐(FN)으로 셀 수
  있다. 임계가 너무 엄격하면 케이스별로 조정한다.

---

## `claude plugin eval` 공개 시 대체 계획

검토 보고서(§2-3)는 `claude plugin eval`이 조기 접근(early access) 단계라고 기록한다. 정식
공개되면:

- `evals/<skill>/evals.json`의 케이스 정의(특히 `expectations`)는 형식을 맞춰 재사용할 수 있을
  가능성이 높다(skill-creator 하네스와 이미 같은 어휘를 쓴다).
- `test/run-evals.sh`의 격리 HOME·install.sh·스트림 파싱·판정 로직은 `claude plugin eval`이
  대신하면 걷어낸다 — 이 저장소가 유지할 것은 케이스 정의(`evals/`)와 케이스 작성 규칙(이 문서)만
  남기는 방향이 유력하다.
- 대체 시점은 공식 기능이 안정화(early access 딱지 해제)된 뒤로 미루고, 그 전까지는 이 초안이
  유일한 실행 경로다.

---

## 관련 파일

- `evals/<skill>/evals.json` — 케이스 정의 5개
- `test/run-evals.sh` — 러너
- `test/eval-report.md` / `test/eval-report.json` — 실행 결과(러너가 생성, 저장소에 커밋하지 않음
  — CI 미포함 이유는 아래 "왜 CI 에 넣지 않나" 절 참조)
- `test/eval-trigger-report.md` / `test/eval-trigger-report.json` — `--trigger` 결과
- `test/golden/`, `test/lint-conventions.sh` — 이 체계가 재사용하는 기존 결정적 판정 근거

## 권한 플래그 실측 (2026-09-03)

`--permission-prompts none` 은 "승인 요청을 전부 거부"라 Skill 도구 호출부터 막혔고, `--dangerously-skip-permissions`/`--permission-mode bypassPermissions` 는 root 컨테이너에서 거부된다. 실제로 동작한 것은 `--permission-mode auto`(모델 분류기가 승인/거부 판단)이며 runner 는 이것을 쓴다. 또 `while read … < <(…)` 루프 안의 `claude -p` 는 반드시 `</dev/null` 로 표준입력을 끊어야 두 번째 케이스부터 조용히 누락되지 않는다(runner 에 반영).

## must_output (2026-09-03 추가)

`must_output` 은 도구 결과(Bash stdout 등)에 있어야 하는 토큰이다. 스크립트가 낸 값이 근거인 케이스(tracker stats 의 `퍼널 전환율` 등)는 모델이 최종 답변에서 출력을 요약해도 스크립트 실행 자체를 판정해야 하므로 `must_contain` 대신 이것을 쓴다. `must_contain` 은 여전히 최종 텍스트 + 생성 파일만 본다.

## 왜 CI 에 넣지 않나

API 키·비용이 필요하고(GitHub Actions 는 모든 브랜치 push 에서 돌아 포크 PR 에 시크릿이 노출될 수 있다), LLM 채점은 비결정적이다. gate 계층만 시크릿이 있는 예약 워크플로우로 돌리는 것이 다음 단계다.
