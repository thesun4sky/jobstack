#!/usr/bin/env bash
# 전 스킬 SKILL.md의 첫 번째 ```bash 프리앰블 블록을 격리 실행하고
# PROACTIVE / ACTIVE_SESSIONS / SKILL_NAME 출력과 trap EXIT 정리를 검증한다.

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
SKILLS="auto strategy tracker review retro portfolio ncs salary job-search cover-letter mock-interview resume company-research"
PASS=0
FAIL=0
FAILED_LIST=()

extract_bash() {
  awk '
    /^```bash$/ { in_block=1; next }
    /^```$/ && in_block { exit }
    in_block { print }
  ' "$1"
}

for s in $SKILLS; do
  SKILL_FILE="$REPO/$s/SKILL.md"
  [ -f "$SKILL_FILE" ] || { echo "[SKIP] $s — file missing"; continue; }

  STATE_DIR=$(mktemp -d)
  SCRIPT=$(mktemp)
  extract_bash "$SKILL_FILE" > "$SCRIPT"

  # (d) stale PID 정리 검증: 죽은 세션 파일을 미리 심는다 (eea3c6c 회귀의 핵심 로직).
  # 999999는 현실적으로 살아있지 않은 PID라 kill -0 실패 → stale 루프가 제거해야 한다.
  mkdir -p "$STATE_DIR/sessions"
  DEAD_PID=999999
  echo "$DEAD_PID" > "$STATE_DIR/sessions/$DEAD_PID"

  OUTPUT=$(
    JOBSTACK_STATE_DIR="$STATE_DIR" \
    CLAUDE_SKILL_DIR="$REPO/$s" \
    bash "$SCRIPT" 2>&1
  )
  EXIT=$?

  errors=()
  # (f) JOBSTACK_STATE_DIR 폴백 분기 존재 확인 (실행 시엔 주입되므로 소스로 검증)
  grep -q '${JOBSTACK_STATE_DIR:-' "$SCRIPT" || errors+=("missing JOBSTACK_STATE_DIR fallback")
  echo "$OUTPUT" | grep -q "^PROACTIVE=" || errors+=("missing PROACTIVE")
  echo "$OUTPUT" | grep -q "^ACTIVE_SESSIONS=" || errors+=("missing ACTIVE_SESSIONS")
  echo "$OUTPUT" | grep -q "^SKILL_NAME=$s\$" || errors+=("missing SKILL_NAME=$s")
  [ $EXIT -eq 0 ] || errors+=("exit=$EXIT")

  # (d) 죽은 세션 파일이 stale 루프로 제거됐는지
  [ -e "$STATE_DIR/sessions/$DEAD_PID" ] && errors+=("stale PID $DEAD_PID not removed")

  # (e) 6개 상태 디렉토리 생성 확인
  for d in analytics profiles tracker company-cache interview-history sessions; do
    [ -d "$STATE_DIR/$d" ] || errors+=("missing dir: $d")
  done

  remaining=$(ls "$STATE_DIR/sessions/" 2>/dev/null | wc -l | tr -d ' ')
  [ "$remaining" -eq 0 ] || errors+=("sessions/ not cleaned: $remaining files left")

  if [ ${#errors[@]} -eq 0 ]; then
    PASS=$((PASS+1))
    printf "[PASS] %-18s  ACTIVE_SESSIONS=%s  SKILL_NAME=%s\n" \
      "$s" \
      "$(echo "$OUTPUT" | grep ^ACTIVE_SESSIONS= | cut -d= -f2)" \
      "$(echo "$OUTPUT" | grep ^SKILL_NAME= | cut -d= -f2)"
  else
    FAIL=$((FAIL+1))
    FAILED_LIST+=("$s")
    printf "[FAIL] %-18s  errors: %s\n" "$s" "${errors[*]}"
    echo "  ---- output (last 15 lines) ----"
    echo "$OUTPUT" | tail -15 | sed 's/^/    /'
    echo "  --------------------------------"
  fi

  rm -rf "$STATE_DIR" "$SCRIPT"
done

echo
echo "===================="
echo "PASS: $PASS / FAIL: $FAIL"
if [ $FAIL -eq 0 ]; then
  echo "ALL GREEN"
  exit 0
else
  echo "FAILED: ${FAILED_LIST[*]}"
  exit 1
fi
