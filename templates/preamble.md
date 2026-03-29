```bash
# ─── jobstack 프리앰블 ─────────────────────────
_JS_STATE="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"
mkdir -p "$_JS_STATE/analytics" "$_JS_STATE/profiles" "$_JS_STATE/tracker" \
         "$_JS_STATE/company-cache" "$_JS_STATE/interview-history" "$_JS_STATE/sessions"

# 세션 추적
echo "$$" > "$_JS_STATE/sessions/$$"

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

# 활성 세션 수
ACTIVE_SESSIONS=$(ls "$_JS_STATE/sessions/" 2>/dev/null | wc -l | tr -d ' ')
echo "ACTIVE_SESSIONS=$ACTIVE_SESSIONS"
echo "PROACTIVE=$PROACTIVE"
echo "SKILL_NAME=$(basename "$CLAUDE_SKILL_DIR" 2>/dev/null || echo "unknown")"

# 텔레메트리
echo "{\"skill\":\"$(basename "$CLAUDE_SKILL_DIR" 2>/dev/null || echo "unknown")\",\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"pid\":$$}" \
  >> "$_JS_STATE/analytics/skill-usage.jsonl" 2>/dev/null || true
```
