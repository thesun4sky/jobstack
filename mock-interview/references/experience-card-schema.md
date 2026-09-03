# 경험 카드 스키마 (experience-card-schema)

`$_JS_STATE/profiles/experiences.yaml` 최상위 리스트에 담기는 경험 카드 1장의 데이터 계약. 카드는 experience-bank 스킬(Phase 4)이 생성하고, `bin/jobstack-exp.mjs`가 결정적으로 조작한다(U-09) — 같은 입력이면 같은 출력이 나온다. 소재 발굴·수치 코칭 방법론(6단계·4분리·수치 폴백)의 단일 소스는 `experience-bank/references/experience-methods.md`이며, 이 문서는 **저장 형식만** 정의한다.

---

## 필드

| 필드 | 타입 | 필수 | 설명 |
|---|---|---|---|
| `id` | string | Y | `exp-YYYYMMDD-NN` 형식. `YYYYMMDD`는 카드 생성일(KST), `NN`은 같은 날짜 안에서의 2자리 일련번호 |
| `title` | string | Y | 경험을 한 줄로 부르는 이름 |
| `problem` | string | Y | 무엇이 문제였나 (누가·언제·얼마나) |
| `role` | string | Y | 그중 내 역할 범위 |
| `action` | string | Y | 내가 바꾼 구체 행동 |
| `change` | string | Y | 검증 가능한 변화 (before→after). 수치가 없으면 정성 서술 또는 `[수치 확인 필요]` |
| `numbers` | string | N | 검증 가능한 수치·범위. 없으면 빈 문자열(`""`) — 필드 자체는 항상 존재한다 |
| `job_link_tags` | string[] | N | 일반 직무 연결 태그. 없으면 빈 배열(`[]`) |
| `ai_usage` | object \| null | N | AI 도구 활용 근거(U-21). 아래 §ai_usage 참조. 미사용이면 `null` |
| `ai_usage.tool` | string | `ai_usage`가 객체일 때 Y | 사용한 AI 도구명 |
| `ai_usage.task` | string | `ai_usage`가 객체일 때 Y | 그 도구로 수행한 작업 |
| `ai_usage.effect` | string | `ai_usage`가 객체일 때 Y | 개선 효과 (전후 비교) |
| `created_at` | string | Y | ISO 8601, UTC `Z` 표기 (예: `2026-09-03T02:00:00Z`) |

`job_link_tags`는 **일반 직무 연결 태그**까지만 담는다. NCS 능력단위 매핑은 ncs 스킬이 이 카드를 입력으로 이어받아 별도로 수행한다(경계 준수, 이 스키마는 관여하지 않음).

`ai_usage`가 존재(비-null)하면 `tool`·`task`·`effect` 세 필드 모두 문자열이어야 `bin/jobstack-exp.mjs validate`를 통과한다. `add`는 세 플래그(`--ai-usage-tool`/`--ai-usage-task`/`--ai-usage-effect`)를 함께 요구하고, `update`도 갱신 결과 세 값이 모두 채워져야 저장한다 — `ai_usage`가 없던 카드에 한 플래그만 주면 거부되고, 이미 완전한 `ai_usage`가 있는 카드는 일부 필드만 갱신할 수 있다(불완전한 `ai_usage`가 저장되는 경로를 두지 않는다. 그 밖의 필드는 `update`가 그대로 쓰고 `validate`가 완성도 게이트다).

---

## ai_usage 신설 사유 (U-21)

경험기술서·AI 활용 경험 문항 같은 구조화 전형이 늘면서 "어떤 AI 도구로, 무엇을, 얼마나 개선했는가"를 별도로 묻는 문항이 자리잡았다. 기존 카드 스키마(문제·역할·행동·결과)는 사람이 수행한 행동만 담는 구조라 이 문항에 바로 대응하지 못했다. `ai_usage`는 AI 협업 경험을 별도 필드로 분리해, 사람의 문제해결 과정(problem/role/action/change)과 AI 활용 근거가 섞이지 않게 한다.

형식 예시(값은 형식 참고용이며 실제 시장 사례를 주장하지 않는다):

```yaml
ai_usage:
  tool: "Claude Code"
  task: "리팩터링 검토"
  effect: "리뷰 시간 2h → 40m"
```

값은 항상 **세션에서 사용자가 확인한 사실**만 채운다 — 다른 사용자·훈련 데이터의 사례를 가져와 채우지 않는다(가드레일 §1 "사실 날조·PII 자동 채우기 금지"와 동일한 원칙).

---

## 수치 placeholder 규칙 (날조 금지)

- `numbers`·`change`에 검증 가능한 수치가 없다고 근거가 없으면, 숫자를 지어내지 않고 `[수치 확인 필요]` placeholder를 남긴다.
- 폴백 순서는 `experience-bank/references/experience-methods.md` §3(수치 폴백 5기준)을 그대로 따른다 — 전후 변화 → 역할 범위 분리 → 정성 근거 → 작은 검증 가능 숫자 → 면접 설명 가능성. 5기준으로도 근거가 안 나오면 placeholder를 유지한다(1회 질문 후 미응답이어도 반복 요구하지 않는다).
- 면접에서 1분 안에 설명하지 못할 수치는 애초에 카드에 넣지 않는다.
- `bin/jobstack-exp.mjs list`는 `numbers`만 보고 판정을 결정적으로 계산한다 — 비어 있으면 `X`, `[수치 확인 필요]`를 포함하면 `△`, 그 외는 `O`. 값을 채우는 것은 스크립트가 아니라 대화(experience-bank 스킬)의 몫이다.

---

## 스크립트 명령 요약 (`bin/jobstack-exp.mjs`)

| 명령 | 기능 |
|---|---|
| `add --title T --problem P --role R --action A --change C [--numbers N] [--tags a,b] [--ai-usage-tool X --ai-usage-task Y --ai-usage-effect Z] [--json '{...}']` | 카드 1장을 파일 끝에 append — 기존 카드·주석 보존, append 후 전체 재파싱에 실패하면 원본을 건드리지 않고 종료 |
| `list [--json]` | id·제목·수치 판정(O/△/X)·AI 열(`ai_usage` 존재 시 O)·직무 태그 요약표 + `카드 N장 · 수치 보강 필요 M장` |
| `show <id>` | 카드 1장을 YAML로 출력 |
| `update <id> [--title T] [--problem P] [--role R] [--action A] [--change C] [--numbers N] [--tags a,b] [--ai-usage-tool X] [--ai-usage-task Y] [--ai-usage-effect Z]` | 지정한 필드만 in-place 수정 (주석 보존) |
| `validate [file]` | 스키마 검사. 기본 대상은 `$_JS_STATE/profiles/experiences.yaml`, 위반마다 `[FAIL] id: 사유`, 통과 시 `[PASS] 카드 N장` |

모든 쓰기는 임시 파일 + rename으로 원자적이며, 상태 디렉토리(`$_JS_STATE` 또는 `JOBSTACK_STATE_DIR`) 밖에는 쓰지 않는다. 날짜 파일명·기준일은 KST(UTC+9) 기준이다.

---

## 스킬 소비자

- **resume**: 카드의 `problem`/`role`/`action`/`change`/`numbers`를 경력·프로젝트 항목 초안의 근거로 인용한다.
- **cover-letter**: 카드를 "결이요"(결론→이유→요청) 구조의 결론(성과)·이유(문제→행동) 소재로 재구성한다. `ai_usage`가 있는 카드는 구조화 전형의 "AI 활용 경험" 문항(U-21)에서 우선 활용 대상이 된다.
- **mock-interview**: 카드의 `change`·`numbers`를 면접 답변 골자로 그대로 재사용해 서류와 면접의 어조·근거를 일관되게 유지한다(experience-methods.md §6 "면접까지 일관된 스토리"). 미끼 문장 방어 준비는 별도 계약인 defense-map(`docs/defense-map-schema.md`)이 담당하며, 경험 카드와는 독립적으로 소비된다.
- **ncs**: `job_link_tags`(일반 직무 연결 태그)를 입력으로 받아 NCS 능력단위에 매핑한다. 능력단위 매핑 자체는 ncs 스킬의 책임이며 이 스키마·스크립트는 관여하지 않는다.
