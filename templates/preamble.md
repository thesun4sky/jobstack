```bash
# ─── jobstack 프리앰블 ─────────────────────────
# 불변식 (test/test-preambles.sh가 검증):
#   1) ACTIVE_SESSIONS / PROACTIVE / SKILL_NAME 3변수를 반드시 echo (PR#4 회귀 이력)
#   2) trap EXIT로 세션 파일 정리 + stale PID 정리 루프 (리다이렉트를 for 리스트에 넣지 말 것 — bash 문법 오류)
#   3) JOBSTACK_STATE_DIR 폴백 유지 (jobclaw per-user 격리가 이 변수를 주입)
#   4) __SKILL_NAME__ 은 스킬 디렉토리명 리터럴로 치환 (basename 동적 계산 금지 — 심링크 경유 시 오판)
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/profiles" "$_JS_STATE/tracker" \
         "$_JS_STATE/company-cache" "$_JS_STATE/interview-history" "$_JS_STATE/sessions" "$_JS_STATE/defense-maps"

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

# 활성 세션 수 (죽은 세션 파일 정리 후 집계)
for _f in "$_JS_STATE/sessions/"*; do
  [ -f "$_f" ] || continue
  kill -0 "$(basename "$_f")" 2>/dev/null || rm -f "$_f"
done
ACTIVE_SESSIONS=$(ls "$_JS_STATE/sessions/" 2>/dev/null | wc -l | tr -d ' ')
echo "ACTIVE_SESSIONS=$ACTIVE_SESSIONS"
echo "PROACTIVE=$PROACTIVE"
echo "SKILL_NAME=__SKILL_NAME__"

# 텔레메트리 (entry 이벤트 — docs/telemetry-events.md 참조)
echo "{\"skill\":\"__SKILL_NAME__\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```
