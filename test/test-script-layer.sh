#!/usr/bin/env bash
# 결정적 스크립트 계층 린트 (U-09) — 스킬 본문이 상태 파일(지원 현황 JSONL·경험 카드 YAML·방어맵 YAML)을
# 손으로 쓰거나 append 하라고 지시하지 않는지 검사한다. 저장·집계는 bin/jobstack-tracker,
# bin/jobstack-exp.mjs, bin/jobstack-defense-map.mjs 가 담당하고 스킬은 호출·해석만 한다.
# 텔레메트리(analytics/skill-usage.jsonl append)는 대상이 아니다.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0
# ① 상태 파일로의 셸 리다이렉트/heredoc
RE_REDIRECT='>>?[[:space:]]*"?\$_JS_STATE/(tracker/applications\.jsonl|profiles/experiences\.yaml|defense-maps/)'
# ② Edit/Write 도구로 상태 파일을 직접 고치라는 지시
RE_TOOL='(Edit|Write)[^`\n]{0,40}(experiences\.yaml|applications\.jsonl)|(experiences\.yaml|applications\.jsonl)[^`\n]{0,40}(Edit로|Write로|append합니다|append 합니다)'
# ③ 수동 재저장 절차·카드 손편집 문구 (v0.4 이전 tracker/experience-bank 본문에서 실제로 쓰이던 표현)
RE_MANUAL='임시 파일에 쓰고|mv`?로 원본을 교체|파일 끝에 \*{0,2}append\*{0,2}합니다|Edit로 해당 필드'
for f in "$REPO"/*/SKILL.md; do
  skill="$(basename "$(dirname "$f")")"
  hits=$(grep -nE "$RE_REDIRECT" "$f" || true)
  hits2=$(grep -nE "$RE_TOOL" "$f" || true)
  hits3=$(grep -nE "$RE_MANUAL" "$f" || true)
  if [ -n "$hits$hits2$hits3" ]; then
    echo "[FAIL] $skill: 상태 파일 직접 편집 지시 — 스크립트(jobstack-tracker / jobstack-exp.mjs / jobstack-defense-map.mjs)를 호출하세요:"
    printf '%s\n%s\n%s\n' "$hits" "$hits2" "$hits3" | sed '/^$/d; s/^/    /' | cut -c1-160
    FAIL=$((FAIL+1))
  fi
done
if [ "$FAIL" -gt 0 ]; then echo "[FAIL] 스크립트 계층 린트 ${FAIL}건"; exit 1; fi
echo "[PASS] 스킬 본문에 상태 파일 직접 편집 지시 없음 (저장·집계는 bin/ 스크립트가 담당)"
