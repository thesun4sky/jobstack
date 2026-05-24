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

  OUTPUT=$(
    JOBSTACK_STATE_DIR="$STATE_DIR" \
    CLAUDE_SKILL_DIR="$REPO/$s" \
    bash "$SCRIPT" 2>&1
  )
  EXIT=$?

  errors=()
  echo "$OUTPUT" | grep -q "^PROACTIVE=" || errors+=("missing PROACTIVE")
  echo "$OUTPUT" | grep -q "^ACTIVE_SESSIONS=" || errors+=("missing ACTIVE_SESSIONS")
  echo "$OUTPUT" | grep -q "^SKILL_NAME=$s\$" || errors+=("missing SKILL_NAME=$s")
  [ $EXIT -eq 0 ] || errors+=("exit=$EXIT")

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
