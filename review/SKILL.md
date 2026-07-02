---
name: review
preamble-tier: 4
version: 0.1.0
description: |
  지원서류 통합 점검 스킬. 이력서↔자소서↔포트폴리오 일관성, 최종 제출 전 체크리스트.
  "전체 점검", "제출 전 확인", "서류 리뷰" 등의 요청 시 활용.
allowed-tools:
  - Bash
  - Read
  - Glob
  - Grep
  - AskUserQuestion
benefits-from: [resume, cover-letter, portfolio, company-research]
---

```bash
# ─── jobstack 프리앰블 ─────────────────────────
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/profiles" "$_JS_STATE/tracker" \
         "$_JS_STATE/company-cache" "$_JS_STATE/interview-history" "$_JS_STATE/sessions"

# 세션 추적
echo "$$" > "$_JS_STATE/sessions/$$"
trap 'rm -f "$_JS_STATE/sessions/$$"' EXIT

# 설정 로딩
_JS_CONFIG="${CLAUDE_SKILL_DIR}/../bin/jobstack-config"
if [ -x "$_JS_CONFIG" ]; then
  PROACTIVE=$("$_JS_CONFIG" get proactive 2>/dev/null || echo "true")
else
  PROACTIVE="true"
fi

# 프로필 로딩
PROFILE="$_JS_STATE/profiles/default.yaml"
if [ -f "$PROFILE" ]; then
  echo "PROFILE_EXISTS=true"
  echo "--- 프로필 요약 ---"
  head -20 "$PROFILE"
  echo "---"
else
  echo "PROFILE_EXISTS=false"
fi

# 기업분석 캐시 확인
echo "--- company-cache ---"
ls "$_JS_STATE/company-cache/" 2>/dev/null | head -5 || echo "없음"

# 활성 세션 수
for _f in "$_JS_STATE/sessions/"*; do
  [ -f "$_f" ] || continue
  kill -0 "$(basename "$_f")" 2>/dev/null || rm -f "$_f"
done
ACTIVE_SESSIONS=$(ls "$_JS_STATE/sessions/" 2>/dev/null | wc -l | tr -d ' ')
echo "ACTIVE_SESSIONS=$ACTIVE_SESSIONS"
echo "PROACTIVE=$PROACTIVE"
echo "SKILL_NAME=review"

# 텔레메트리
echo "{\"skill\":\"review\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```

# 지원서류 통합 리뷰

제출 전 마지막 관문. 이력서, 자소서, 포트폴리오의 **일관성과 완성도**를 통합 점검합니다.

---

## Phase 1: 서류 수집

Glob으로 현재 폴더의 모든 지원 서류를 수집합니다:
- 이력서: 이력서*, resume*, CV*
- 자소서: 자소서*, 자기소개서*, cover-letter*
- 포트폴리오: 포트폴리오*, portfolio*
- 채용공고: 채용*, JD*, 공고*

모든 감지된 파일을 Read하여 내용을 파악합니다.

### 재리뷰 감지 + 변경분(delta) 요약 (#117)

`memo.md`(또는 워크스페이스의 직전 리뷰 스냅샷)에 **직전 리뷰 진단 결과**가 있으면, 이번 서류를 그것과 대조해 **변경분만** 다음 3구간으로 요약합니다(전체 진단표 반복 출력 금지 — 미해결 지적 반복이 사용자 이탈을 유발):

- ✅ **해결됨**: 지난 지적 중 이번에 반영된 항목 (한 줄씩, 짧은 축하 톤)
- 🔁 **여전히 미해결**: 지난 지적 중 그대로인 항목만 ("지난 리뷰 참고" + 핵심 한 줄, 전체 재설명 금지)
- 🆕 **신규**: 이번에 새로 발견된 항목

**최초 리뷰(대조 대상 없음)일 때만** 기존 전체 진단표(Phase 2~5)를 출력합니다. 재리뷰 완료 시 이번 진단 결과를 `.last-review.md`로 스냅샷해 다음 대조를 명시화하는 것을 권장합니다.

---

## Phase 2: 일관성 점검

### 2.1 기본 정보 일관성
- 이름, 연락처, 이메일이 모든 서류에서 동일한가?
- 학력 정보가 일치하는가?
- 경력 기간/회사명이 일치하는가?

### 2.2 스토리 일관성
- 이력서의 경험과 자소서의 에피소드가 일치하는가?
- 자소서에서 언급한 성과 수치가 이력서와 맞는가?
- 포트폴리오의 프로젝트가 자소서/이력서에도 반영되었는가?

### 2.3 톤 일관성
- 이력서의 직무 포지셔닝과 자소서의 어조가 맞는가?
- "바로 써보고 싶은 사람" 포지셔닝이 모든 서류에서 일관되는가?

---

## Phase 3: 키워드 정합성

채용공고(또는 company-cache)와 대조합니다. **company-cache 파일명 날짜가 7일 초과이면 "⚠️ {N}일 전 분석 캐시입니다. `/company_research`로 재분석을 권장합니다."라고 먼저 안내**합니다.

대조 항목:
- 채용공고의 핵심 키워드가 이력서에 반영되었는가?
- 채용공고의 핵심 키워드가 자소서에 반영되었는가?
- 누락된 키워드 목록 생성

---

## Phase 4: "결이요" + 미끼 점검

### 자소서 구조 점검
- 각 항목의 첫 문장이 5초 규칙을 통과하는가?
- "결이요" 구조가 지켜지고 있는가?
- 학생 톤이 남아있지 않은가?

### 미끼 포인트 인벤토리
자소서 전체에서 면접관이 물어볼 만한 미끼 포인트를 추출합니다:
```
미끼 포인트 총 정리
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  서류    미끼 문장                     예상 질문
1  자소서  "Redis 캐싱 377ms→2ms"       "캐싱 전략은?"
2  자소서  "80명 데이터 관리"            "품질 관리 방법은?"
3  이력서  "AWS 인프라 구축"             "아키텍처 설명해주세요"
4  포트폴  "DAU 5000 서비스"            "스케일링 경험은?"
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## Phase 5: 최종 체크리스트

```
최종 제출 전 체크리스트
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[✓] 기본정보 일관성 — 이름/연락처/학력 일치
[✓] 스토리 일관성 — 경험/성과 수치 일치
[✓] 톤 일관성 — 실무자 포지셔닝 유지
[✓] 키워드 반영률 — 85%+ 달성
[!] "결이요" 구조 — 지원동기 첫 문장 보완 필요
[✓] 미끼 배치 — 4개 포인트 확인
[✓] 학생 톤 제거 — 희망형 종결어미 없음
[✓] 수치화 — 모든 성과에 before→after
[!] 글자수 — 직무역량 항목 50자 초과
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
통과: 7/9 | 보완: 2/9
```

보완이 필요한 항목에 대해 구체적 수정 방안을 제시합니다.

---

## Phase 6: 면접 예상 질문 종합 세트

자소서 + 이력서 + 포트폴리오 + 채용공고 기반으로 **종합 면접 예상 질문**을 생성합니다:

- 자소서 기반 질문 15-20개
- 채용공고 기반 기술 질문 10-15개
- 포트폴리오 기반 질문 5-10개
- 총 30-40개 질문 세트

파일로 저장: `면접예상질문-{기업명}.md`

---

## 보이스

엄격하지만 공정한 리뷰어. 문제점은 정확히 짚되, 항상 수정 방안과 함께 제시합니다.

## 완료 상태

- **완료 (DONE)** — 체크리스트 전항 통과
- **우려사항 있는 완료 (DONE_WITH_CONCERNS)** — 보완 필요 항목 존재

### 결과물 뷰어
결과 파일 저장 시 브라우저 뷰어를 안내합니다:
```bash
$CLAUDE_SKILL_DIR/../bin/jobstack-view <결과파일.md>
```

다음 추천: `/mock_interview` (면접 예상 질문으로 모의면접)
