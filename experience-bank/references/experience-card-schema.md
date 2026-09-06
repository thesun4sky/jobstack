# 경험 카드 스키마 (experience-card-schema)

`$_JS_STATE/profiles/experiences.yaml` 최상위 리스트에 담기는 경험 카드 1장의 데이터 계약. 카드는 experience-bank 스킬(Phase 4)이 생성하고, `apply_plans` 항목(STAR-R 의 R = 입사 후 적용)은 experience-bank(Phase 3 '입사 후 적용' 절)와 company-research(Phase 5.5)가 `apply` 명령으로 덧붙이며, `bin/jobstack-exp.mjs`가 결정적으로 조작한다(U-09) — 같은 입력이면 같은 출력이 나온다. 소재 발굴·수치 코칭 방법론(6단계·4분리·수치 폴백)의 단일 소스는 `experience-bank/references/experience-methods.md`이며, 이 문서는 **저장 형식만** 정의한다.

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
| `apply_plans` | object[] | N | 입사 후 적용(STAR-R 의 R) 목록. 회사당 1건(정규화 회사명 기준 upsert). 없으면 필드 자체가 없을 수 있다(부재 == `[]`) — `add`는 쓰지 않고 `apply`만 쓴다 |
| `apply_plans[].company` | string | 항목 내 Y | 지원 기업 표시명. 중복 판정·`list --company` 매칭은 유니코드 NFKC 정규화 뒤 공백·대시·비가시 문자(zero-width·BOM) 제거·소문자 기준. 보이지 않는 문자만으로 된 회사명은 거부 |
| `apply_plans[].position` | string | N | 지원 직무 (있을 때만) |
| `apply_plans[].plan` | string | 항목 내 Y | R 한 문장 — "[기업의 과제·키워드]에 [카드의 행동·변화]를 적용해 [기대 변화]" (`experience-methods.md` §7) |
| `apply_plans[].basis` | string | 항목 내 Y | 근거 원문 1개 이상 — 기업분석 키워드 체크리스트·'이미 팀원처럼' 화두·공고 문구를 그대로 인용 |
| `apply_plans[].source` | string | 항목 내 Y | 출처 파일·기준일 (예: `company-cache/토스-2026-09-06.md`) |
| `apply_plans[].created_at` | string | 항목 내 Y | ISO 8601 UTC `Z` — 항목을 쓴(교체한) 시각 |
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

## apply_plans 신설 사유 (STAR-R)

결이요의 '요(청)'와 면접의 "입사하면 이 경험을 어떻게 쓰겠나" 답변은 매번 즉석에서 쓰여 카드에 남지 않았고, 기업분석 결과와도 연결되지 않아 일반론("귀사에서 성장하겠습니다")으로 흐르기 쉬웠다. `apply_plans`는 STAR-R 의 두 번째 R(**입사 후 적용**)을 **기업분석 근거와 함께** 카드에 저장해, 자소서 '요'·입사 후 포부·면접 답변이 같은 문장을 재사용하게 한다(ETHOS 원칙 8 "면접까지 일관된 스토리"). 작성 규칙(근거 1개 이상·한 문장·회사명 치환 테스트·감상 뒤에 잇지 않기)의 단일 소스는 `experience-methods.md` §7 이다.

형식 예시(값은 형식 참고용이며 실제 기업 사례를 주장하지 않는다):

```yaml
apply_plans:
  - company: "토스"
    position: "백엔드 개발자"
    plan: "결제 응답 지연 과제에 Redis 캐싱 설계 경험을 적용해 p95 지연 원인 분석부터 맡는다"
    basis: "핵심 키워드: 결제 안정성 · '이미 팀원처럼' 화두: 결제 p95 지연"
    source: "company-cache/토스-2026-09-06.md"
    created_at: "2026-09-06T05:00:00Z"
```

`basis`·`source`가 비면 `apply`가 저장을 거부한다 — 근거 없는 R 은 §1 의 사실 날조와 같은 취급이다. 회사당 1건이므로 같은 회사(정규화 기준)로 다시 `apply`하면 **항목 전체를 교체**하고 `created_at`도 새 값이 된다 — 재-apply 때 `--position` 을 생략하면 이전 `position` 은 이월되지 않고 사라지므로 유지하려면 다시 지정한다. 항목 삭제 명령은 두지 않는다(후속 후보).

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
| `list [--json] [--company C]` | id·제목·수치 판정(O/△/X)·AI 열(`ai_usage` 존재 시 O)·적용 열(`apply_plans` 항목 수, 없으면 `-`)·직무 태그 요약표 + `카드 N장 · 수치 보강 필요 M장 · 입사 후 적용 K장`. `--company C`는 정규화 부분일치로 그 회사의 `apply_plans`가 있는 카드만 보여 주고(값이 비면 exit 1 — 무필터로 폴백하지 않음), `--json`에는 `apply_plans_count`·`with_apply_plans`, 필터 시 `company_filter`·`ambiguous_company_matches`와 카드마다 `matched_apply_plan`(정규화 등치 1건 또는 부분일치가 1건일 때만, 아니면 null)·`matched_apply_plans`(부분일치 전체)·`ambiguous_company_match`가 붙는다. 한 카드에 계열사 항목이 여럿이면(토스페이먼츠·토스증권 ↔ `토스`) 단수 키를 비우고 표 푸터에 모호 카드 수를 안내하므로 정확한 회사명으로 다시 조회한다 |
| `show <id>` | 카드 1장을 YAML로 출력 |
| `update <id> [--title T] [--problem P] [--role R] [--action A] [--change C] [--numbers N] [--tags a,b] [--ai-usage-tool X] [--ai-usage-task Y] [--ai-usage-effect Z]` | 지정한 필드만 in-place 수정 (주석 보존) |
| `apply <id> --company C --plan P --basis B --source S [--position X]` | 입사 후 적용(STAR-R 의 R) 항목을 회사당 1건 upsert — 같은 회사(정규화 등치)는 교체, 다른 회사는 추가. `--basis`·`--source`가 비면 exit 1, 파일 미변경. `--position`을 값 없이 주면 exit 1. 교체해도 항목에 붙은 주석은 남는다. 주석 보존·원자적 쓰기·잠금은 `update`와 동일 |
| `validate [file]` | 스키마 검사. 기본 대상은 `$_JS_STATE/profiles/experiences.yaml`, 위반마다 `[FAIL] id: 사유`, 통과 시 `[PASS] 카드 N장` |

모든 쓰기는 임시 파일 + rename으로 원자적이며, 상태 디렉토리(`$_JS_STATE` 또는 `JOBSTACK_STATE_DIR`) 밖에는 쓰지 않는다. 날짜 파일명·기준일은 KST(UTC+9) 기준이다.

---

## 저장 직전 검사와 파일 권한

- `add`·`update`·`apply` 는 저장 직전에 `validate` 와 같은 카드 단위 검사(`cardErrors()`)를 돌린다. 공백만 있는 필수값, 문자열이 아닌 `--json` 값, `tool/task/effect` 가 하나라도 비거나 공백인 `ai_usage`, `apply_plans` 계약 위반은 exit 1 이며 파일은 바뀌지 않는다 — 이 스크립트가 만든 파일은 항상 `validate` 를 통과한다. `update --numbers ""` 만 빈 값(미지정)을 허용한다.
- 카드에는 개인 이력·지원 회사·근거가 담기므로 프리앰블(umask 077) 없이 직접 실행해도 새로 만드는 디렉토리(상태 디렉토리·`profiles/`·`defense-maps/`)는 0700, `experiences.yaml`·방어맵 파일·잠금 파일은 0600 으로 만든다. 이미 있는 디렉토리의 권한은 바꾸지 않는다(사용자가 정한 위치일 수 있음).

## 스킬 소비자

- **resume**: 카드의 `problem`/`role`/`action`/`change`/`numbers`를 경력·프로젝트 항목 초안의 근거로 인용한다. 이력서 본문은 S·T·A·R 까지만 쓰고 `apply_plans`(두 번째 R)는 쓰지 않는다.
- **cover-letter**: 카드를 "결이요"(결론→이유→요청) 구조의 결론(성과)·이유(문제→행동) 소재로 재구성한다. 요(청)는 지원 기업과 일치하는 `apply_plans[].plan`을 우선 쓴다(`list --company`). `ai_usage`가 있는 카드는 구조화 전형의 "AI 활용 경험" 문항(U-21)에서 우선 활용 대상이 된다.
- **mock-interview**: 카드의 `change`·`numbers`를 면접 답변 골자로 그대로 재사용해 서류와 면접의 어조·근거를 일관되게 유지한다(experience-methods.md §6 "면접까지 일관된 스토리"). 지원 기업과 일치하는 `apply_plans`는 "입사하면 이 경험을 어떻게 쓰겠나" 류 질문·답변 평가의 근거다. 미끼 문장 방어 준비는 별도 계약인 defense-map(`docs/defense-map-schema.md`)이 담당하며, 경험 카드와는 독립적으로 소비된다.
- **ncs**: `job_link_tags`(일반 직무 연결 태그)를 입력으로 받아 NCS 능력단위에 매핑한다. 능력단위 매핑 자체는 ncs 스킬의 책임이며 이 스키마·스크립트는 관여하지 않는다.
- **career-history**: 저장된 카드를 프로젝트 인벤토리에 먼저 제시하고, 지원 기업과 일치하는 `apply_plans`가 있는 카드를 배치 우선순위에 올린다. R 문장 자체는 경력기술서에 옮기지 않는다(자소서 소관).
- **scout-profile**: 카드의 확인된 수치·변화를 프로필 리라이팅의 근거 창고로만 읽는다.

**쓰기 경계**: 카드 생성(`add`)·수정(`update`)은 experience-bank 스킬만 하고, `apply_plans`는 experience-bank 와 company-research 가 `apply`로만 쓴다. 그 밖의 스킬은 읽기 전용이다.
