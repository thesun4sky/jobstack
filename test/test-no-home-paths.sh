#!/usr/bin/env bash
# 전 스킬 SKILL.md 본문에서 하드코딩된 홈 경로(~/.jobstack, $HOME/.jobstack)를 금지하는 린트.
# 봇 러너는 JOBSTACK_STATE_DIR을 강제하고 Write(~/*)를 deny하므로, 본문 지시는
# $_JS_STATE 또는 "$JOBSTACK_STATE_DIR" 표기를 써야 한다.
# 예외: 프리앰블의 폴백 패턴 `${JOBSTACK_STATE_DIR:-$HOME/.jobstack}` (CLI 폴백)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

HITS=$(grep -rn -e '~/\.jobstack' -e '\$HOME/\.jobstack' "$REPO"/*/SKILL.md 2>/dev/null \
  | grep -v 'JOBSTACK_STATE_DIR:-' || true)

if [ -n "$HITS" ]; then
  COUNT=$(echo "$HITS" | wc -l | tr -d ' ')
  echo "[FAIL] 하드코딩된 홈 경로 ${COUNT}건 발견 — \$_JS_STATE 표기로 치환하세요:"
  echo "$HITS" | sed "s|^$REPO/||; s/^/  /"
  exit 1
fi

echo "[PASS] */SKILL.md 에 하드코딩된 ~/.jobstack 경로 없음"
exit 0
