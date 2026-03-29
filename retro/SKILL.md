---
name: retro
preamble-tier: 2
version: 0.1.0
description: |
  면접/지원 회고 스킬. 면접 결과 분석, 탈락 원인 진단, 개선 포인트 도출.
  "면접 회고", "왜 떨어졌을까", "개선점" 등의 요청 시 활용.
allowed-tools:
  - Bash
  - Read
  - Write
  - AskUserQuestion
benefits-from: [mock-interview, tracker]
---

```bash
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/sessions"
echo "$$" > "$_JS_STATE/sessions/$$"
# 최근 면접 기록 확인
echo "--- 최근 면접 기록 ---"
ls -t "$_JS_STATE/interview-history/" 2>/dev/null | head -5 || echo "기록 없음"
echo "--- 최근 지원 현황 ---"
tail -5 "$_JS_STATE/tracker/applications.jsonl" 2>/dev/null || echo "기록 없음"
echo "{\"skill\":\"retro\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

# 면접/지원 회고

면접이나 지원 결과를 돌아보고, 다음 지원을 위한 구체적 개선 포인트를 도출합니다.

---

## Phase 1: 회고 대상 선택

interview-history와 tracker에서 최근 기록을 확인합니다.

AskUserQuestion:
```
회고할 면접/지원 건을 선택해주세요.

A) 최근 면접 회고 (면접 경험 분석)
B) 탈락 원인 분석 (불합격 건)
C) 전체 지원 현황 회고
```

---

## Phase 2: 면접 경험 인터뷰

AskUserQuestion으로 하나씩 질문합니다:

1. "어떤 기업/직무 면접이었나요?"
2. "면접 형식은 무엇이었나요? (인성/PT/토론/기술/임원)"
3. "기억나는 면접 질문을 알려주세요. (최대한 많이)"
4. "각 질문에 어떻게 답변했나요?"
5. "면접 분위기는 어땠나요? (꼬리질문이 많았나, 긍정적 반응이 있었나)"
6. "본인이 느끼기에 잘한 점과 아쉬운 점은?"

---

## Phase 3: 분석

### 3.1 답변 품질 분석
수집된 질문-답변을 "결이요" 프레임워크로 평가:
- 첫 문장에 결론이 있었나?
- 구체적 수치/사례가 있었나?
- 직무/기업 연결이 있었나?

### 3.2 준비 vs 실제 GAP
- 준비한 답변 vs 실제 답변 비교 (면접 예상 질문 세트가 있다면 대조)
- 예상치 못한 질문 유형 분석
- 미끼 전략이 작동했는지 확인

### 3.3 패턴 분석
- 반복되는 약점이 있는가?
- 특정 질문 유형에 취약한가?
- 기업 연구가 충분했는가?

---

## Phase 4: 개선 액션플랜

```
회고 결과 요약
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
강점:
  - 기술적 깊이 있는 답변 (Redis 캐싱 설명)
  - 프로젝트 경험 구체적 전달

개선 필요:
  - 지원동기 답변에서 기업 연구 부족
    → 액션: /company-research로 심화 분석
  - 꼬리질문 대응 미흡
    → 액션: /mock-interview로 꼬리질문 연습
  - 숫자 기반 성과 전달 부족
    → 액션: 주요 경험 3개에 before→after 수치 추가

다음 면접까지 To-Do:
  1. [ ] 기업 키워드 체크리스트 재작성
  2. [ ] 자소서 미끼 포인트 답변 준비
  3. [ ] 모의면접 2회 이상 진행
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 5: 기록 및 추적

- 회고 결과를 `~/.jobstack/interview-history/retro-{기업명}-{date}.md`에 저장
- tracker의 해당 건 notes에 회고 요약 추가 제안

---

## 보이스

따뜻하지만 솔직한 코치. 실패를 비난하지 않되, 원인은 정확히 짚습니다. 항상 구체적 다음 행동과 함께.

## 완료 상태

- **완료 (DONE)** — 회고 + 액션플랜 완료

다음 추천: `/strategy` (전략 재수립) 또는 `/mock-interview` (재연습)
