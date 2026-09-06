# defense-map 데이터 계약 — 문장↔꼬리질문 맵

자소서·이력서의 문장별 예상 꼬리질문 맵을 스킬 간에 주고받는 YAML 계약. ETHOS의 "미끼를 던져라 — 그리고 그 미끼에 대한 답변을 미리 준비하라"의 데이터 구현이다.

- **산출**: cover-letter (첨삭 완료 시), review (통합 리뷰 Phase 4), career-history (경력기술서 미끼 포인트 표시 시 — 선택)
- **소비**: mock-interview (개인화 질문 소스), retro (방어 준비율 집계 — 선택)
- 예시 파일: templates/defense-map-example.yaml

---

## 저장 위치·파일명

```
$_JS_STATE/defense-maps/<회사명>_<직무>_<YYYYMMDD>.yaml
```

- 회사명·직무의 공백은 하이픈으로 정규화한다 (예: `네이버_백엔드-개발자_20260703.yaml`)
- 같은 회사·직무로 재산출하면 날짜가 다른 새 파일을 만든다 (이력 보존)

## 스키마 (schema_version: 1)

| 필드 | 타입 | 설명 |
|---|---|---|
| `schema_version` | int | 1 고정 |
| `source_skill` | string | `cover-letter` \| `review` \| `career-history` |
| `created_at` | string | KST ISO 8601 (예: 2026-07-03T18:30:00+09:00) |
| `company` | string | 회사명 |
| `position` | string | 직무 |
| `document_ref` | string | 원문 파일 경로 또는 문항 식별자 |
| `entries` | list | 아래 entry 구조의 배열 |

### entry 구조

| 필드 | 타입 | 설명 |
|---|---|---|
| `id` | string | `dm-001` 형식 일련번호 |
| `sentence` | string | 미끼/위험 문장 원문 |
| `location` | string | 위치 (문항 번호·단락) |
| `bait_type` | enum | `수치` \| `기술선택` \| `역할범위` \| `성과` \| `갈등·판단` |
| `questions` | list | 예상 꼬리질문 **2개 이상** — 각각 `{q, intent, difficulty}` |
| `questions[].q` | string | 예상 질문 |
| `questions[].intent` | string | 검증 의도 (면접관이 확인하려는 것) |
| `questions[].difficulty` | enum | `mild` \| `normal` \| `hard` |
| `answer_hint` | string\|null | 1분 답변 골자. **사용자가 확인하기 전이면 null** (추정 작성 금지 — guardrails §1) |
| `defense_status` | enum | `ready`(방어 준비됨) \| `weak`(답변 불충분) \| `unprepared`(미준비) |

## 산출 규칙

- **cover-letter**: 미끼 5개 배치 원칙에 따라 `entries` 5개 이상
- **review**: 자소서·공고 기반 예상 질문을 entry로 귀속 (문장에 매이지 않는 공고 기반 질문은 `sentence`에 근거 요건 문구, `location`에 "공고" 표기)
- **career-history**: 경력기술서 프로젝트 성과 문장 중 미끼 문장을 entry로 귀속 (`bait_type`은 주로 `수치`·`기술선택`·`역할범위`·`성과`, `location`에 프로젝트명 표기). 선택 산출 — 사용자가 미끼 인벤토리 저장을 원할 때만 생성
- 질문은 꼬리질문 공통 5세트 프레임(어떤 문제였나 / 왜 그 방법이었나 / 역할 범위는 / 결과를 어떻게 확인했나 / 다시 한다면)을 기준으로 생성
- `answer_hint`는 사용자가 답을 확인·작성한 경우에만 기록 — 스킬이 대신 지어내지 않는다

## 소비 규칙 (mock-interview)

1. **파일 선택**: 회사명 느슨 매칭(공백 제거 + 소문자 부분일치) 후 **최신 파일 1개**
2. **주입 상한**: 질문 소스로 주입하는 분량은 1500자 이내 (컨텍스트 보호)
3. **우선 출제**: `defense_status`가 `weak`·`unprepared`인 entry를 먼저 출제
4. **면접 답변은 자유서술** — 질문 출제에만 사용하고, 답변 수집을 AskUserQuestion 선택지로 강제하지 않는다 (mock-interview 답변 수집 규칙과 정합)
5. **갱신(양방향)**: 면접 종료 후 해당 entry의 `defense_status`를 실전 답변 품질로 갱신한다
6. **파일 부재 시**: 기존 프리셋 질문 흐름으로 폴백 — 계약 위반이 아니다

## 소비 규칙 (retro — 선택)

- 방어 준비율 = `ready` entry 수 / 전체 entry 수. 회고 리포트의 참고 지표로만 사용.
