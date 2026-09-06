# tracker 상태 모델 (canonical)

지원 현황 상태의 단일 정의 문서. tracker/retro/auto 스킬과 골든 테스트가 이 문서를 기준으로 삼는다.

- 확정 근거: Council #1 (2026-07-03) — watching 미포함(3:1), preparing 유지(4:0), 마이그레이션은 읽기 정규화+승인 재작성(4:0), withdrawn 라벨 "지원취소"(4:0)
- 원칙: **저장은 영문 키, 표시는 한글 라벨**
- **작업 범위 경계**: M1(INFRA-5)은 이 canonical 정의 문서 확정까지다. `tracker/SKILL.md`의 add/update 선택지·JSONL 예시·stats 분포를 이 모델로 실제 교체하는 편집과 `retro`/`auto`의 소비 배선은 **TRK-1(M4)** 작업이다. 그 사이 tracker/SKILL.md 본문은 구버전(v1) 예시를 유지하되 상단 경고로 이 문서를 기준으로 가리킨다.

---

## canonical 9상태

파이프라인 7 + 종결 2.

| # | 영문 키 (저장) | 한글 라벨 (표시) | 의미 | 진입 시점 | 이후 전이 |
|---|---|---|---|---|---|
| 1 | `preparing` | 준비중 | 지원 결심~서류 작성 중 (미제출) | 항목 등록 기본값 | applied, withdrawn |
| 2 | `applied` | 지원완료 | 서류 제출 완료, 서류전형 진행/결과 대기 | 서류 제출 | document_pass, rejected, withdrawn |
| 3 | `document_pass` | 서류합격 | 서류전형 통과 | 서류 결과 발표 | interview_1, rejected, withdrawn |
| 4 | `interview_1` | 1차면접 | 1차(실무) 면접 단계 | 면접 일정 확정 | interview_2, final, offer, rejected, withdrawn |
| 5 | `interview_2` | 2차면접 | 2차 면접 단계 | 1차 통과 | final, offer, rejected, withdrawn |
| 6 | `final` | 최종면접 | 최종 면접 단계 (임원 면접 등) | 이전 면접 통과 | offer, rejected, withdrawn |
| 7 | `offer` | 최종합격 | 오퍼 수령 (합격 결과) | 최종 결과 발표 | (종결) |
| 8 | `rejected` | 불합격 | 전형 탈락 (종결) | 탈락 통보 | — |
| 9 | `withdrawn` | 지원취소 | 사용자가 접은 지원 (종결) | 사용자 결정 | — |

- `final`과 `offer`의 구분: final = 최종 **면접 단계**, offer = 최종 **합격 결과**. 전형이 짧으면 중간 단계를 건너뛰어도 된다(interview_1 → offer 허용).
- `withdrawn`은 `rejected`와 반드시 구분한다 — 합격률·전환율 산출 시 withdrawn을 탈락으로 집계하면 수치가 왜곡된다.
- `watching`(관심 공고)은 canonical에 **포함하지 않는다** (Council #1). 관심 기업 북마크는 지원 파이프라인 상태가 아니므로 v0.3+에서 job-search 쪽 북마크 축으로 별도 설계한다.

---

## v1(한글 저장) → v2(영문 키) 매핑

| v1 값 (기존 파일) | v2 영문 키 | 비고 |
|---|---|---|
| 준비중 | `preparing` | |
| 서류전형 | `applied` | v1 "서류전형" = 제출 후 전형 중 |
| 서류합격 | `document_pass` | |
| 1차면접 | `interview_1` | |
| 2차면접 | `interview_2` | |
| 최종합격 | `offer` | v1 "최종합격" = 합격 결과 |
| 불합격 | `rejected` | |
| — (v1에 없음) | `final` | 신규 상태 (한글 라벨: 최종면접) |
| — (v1에 없음) | `withdrawn` | 신규 상태 (한글 라벨: 지원취소) |

매핑표에 없는 값을 만나면: 원문을 유지하고 표시 시 `(구버전 상태)` 표기를 붙인다. 절대 임의 추정으로 변환하지 않는다.

---

## 저장 스키마 v2

```json
{"id":"app-001","company":"삼성전자","position":"SW엔지니어","status":"applied","max_stage":"applied","schema_version":2,"applied_at":"2026-07-01","deadline":"2026-07-15","updated_at":"2026-07-03","notes":""}
```

- **쓰기**: 항상 영문 키 + `"schema_version":2` 필드 포함
- **읽기**: `status`가 한글이면 위 매핑표로 정규화 (v1 하위호환 — 구버전 파일도 오류 없이 동작)
- **표시**: 사용자 출력은 항상 한글 라벨
- **`max_stage`** (파이프라인 최고 도달 단계): 상태를 갱신할 때마다 파이프라인 순서(preparing<applied<document_pass<interview_1<interview_2<final<offer)상 더 높은 단계면 갱신한다. 종결(rejected/withdrawn) 전환 시에는 `status`만 종결 값으로 바꾸고 `max_stage`는 직전 진행 단계를 보존한다 — 이 필드가 있어야 "면접 중 탈락"을 퍼널에서 복원할 수 있다. rejected/withdrawn은 파이프라인 단계가 아니므로 `max_stage`에 절대 기록하지 않는다.
- v1 파일이나 `max_stage`가 없는 항목을 읽을 때: 진행 상태면 현재 `status`를, 종결 상태면 `applied`(최소 도달)를 폴백값으로 간주하되, 폴백 사실을 집계에 반영해 상향 왜곡을 피한다(아래 퍼널 규칙 참조).

---

## 마이그레이션 절차 (Council #1 결정)

1. **읽기 정규화 (항상)**: v1 라인이 섞여 있어도 읽기 시점에 영문 키로 정규화해 처리한다. 파일은 건드리지 않는다.
2. **일괄 재작성 제안 (최초 1회)**: tracker 스킬 실행 중 v1 라인을 발견하면 사용자에게 제안한다 — "구버전 형식 N건을 새 형식으로 정리할까요? 원본은 applications.jsonl.bak으로 백업됩니다." 승인 시에만 재작성한다. 거절하면 같은 세션에서 재제안하지 않는다.
3. **강제 재작성 금지**: 사용자 승인 없이 파일을 재작성하지 않는다.

---

## jobclaw(봇) 동기화 매핑

봇에서 지원 현황 관리는 네이티브 명령 `/track`·`/myapps`가 담당한다 (tracker 스킬은 CLI 용도로 잔존 — templates/BOT-COMMAND-STYLE.md §2). jobclaw DB는 8상태(preparing 없음)를 쓴다.

- `preparing` → `applied` **단방향 매핑** (Council #1 — 봇 측으로 내보낼 때만 승격, 역방향 없음)
- 나머지 8개 상태는 1:1 동일 키

---

## 넛지·집계 규칙 (소비 스킬 공통 기준)

- **7일 정체 넛지**:
  - jobclaw 봇 넛지는 `applied` 상태 한정(검증된 application-reminder-cron 설계와 일치).
  - CLI(tracker/auto)의 정체 감지는 `updated_at` 기준 7일 이상 경과한 진행 상태(preparing~final) 전체를 대상으로 확장한다 — 봇보다 넓은 범위임을 의도적으로 명시. 종결 상태(offer/rejected/withdrawn)는 양쪽 모두 제외.
- **퍼널 전환율** (retro 집계): `max_stage`(최고 도달 단계) 기준으로 계산한다. "X 이상 도달" = `max_stage`가 파이프라인 순서상 X 이상인 건.
  - 서류 통과율 = (`max_stage` ≥ document_pass 인 건) / (`max_stage` ≥ applied 인 건)
  - 면접 통과율 = (`status` = offer 인 건) / (`max_stage` ≥ interview_1 인 건)
  - `max_stage`가 없는 v1/폴백 항목은 종결 상태를 어느 단계에서 마쳤는지 알 수 없으므로 분자·분모 판정이 불확실하다 — 이런 항목 수를 별도로 세어 "정확도 제한: 구버전 N건 제외" 형태로 함께 표기한다(상향 왜곡 방지).
- **합격률 분모에서 withdrawn 제외** — 사용자가 접은 지원은 탈락이 아니다.
- 표본이 작을 때(그룹당 3건 미만) 비교 수치를 단정 서술하지 않는다.

---

## 소비 문서 (이 정의를 참조해야 하는 곳)

| 문서 | 사용 지점 |
|---|---|
| tracker/SKILL.md | add/update 선택지, list 그룹핑, stats 분포 (TRK-1에서 개정) |
| retro/SKILL.md | 탈락 원인 분기·퍼널 집계 (RET 항목에서 개정) |
| auto/SKILL.md | 대시보드 지원 현황 줄·정체 넛지 (AUTO-6에서 개정) |
| test/golden/tracker | v1→v2 정규화 하위호환 골든 테스트 (INFRA-8) |
