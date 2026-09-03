#!/usr/bin/env bash
# 스킬 참조 경로 린트 (검토 보고서 D-1 재발 방지).
#
# Claude Code 는 심링크 설치에서 ${CLAUDE_SKILL_DIR} 를 심링크 경로로 치환하고, Read 도구는
# 경로를 어휘적으로 정규화하므로 `${CLAUDE_SKILL_DIR}/../templates/x.md` 는 존재하지 않는 경로가
# 된다. 그래서 규칙은 하나다: **모든 ${CLAUDE_SKILL_DIR} 참조는 스킬 디렉토리 안쪽을 가리키고,
# 그 파일이 실제로 있어야 한다.** bin/ 스크립트는 프리앰블이 env.sh 로 내보내는 $_JS_BIN 으로 부른다.
#
# 검사:
#   ① ${CLAUDE_SKILL_DIR}/… 참조에 `..` 이 없고, 대상 파일이 존재
#   ② 생성 파일(scripts/·references/)이 원본과 일치 — bin/gen-skill-docs.sh --check
#   ③ 봇 노출 스킬은 bot-protocol 주입 라인이 있고, CLI 전용 스킬(tracker·ncs)은 없음
#   ④ 봇 전용 마커가 SKILL.md 본문에 남아 있지 않음 (IMAGE_PROMPT / [CHOICES] / OUTPUT_FILE / render-docx)
#   ⑤ 본문에 bare `docs/…md`·`templates/…md` 참조가 없음 — 스킬 밖이라 Read 실패(D-1 회귀, 리뷰 반영)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0
NO_BOT=" tracker ncs "

skill_dirs() {
  local d
  for d in "$REPO"/skills/*/ "$REPO"/*/; do
    d="${d%/}"
    [ -f "$d/SKILL.md" ] && echo "$d"
  done | sort -u
}

for dir in $(skill_dirs); do
  skill="$(basename "$dir")"
  # ① 참조 경로
  refs=$(grep -oE '\$\{?CLAUDE_SKILL_DIR\}?/[^ `"'"'"')>|,;]*' "$dir/SKILL.md" | sed -E 's/^\$\{?CLAUDE_SKILL_DIR\}?\///; s/[.:]+$//' | sort -u)
  for rel in $refs; do
    case "$rel" in
      *..*) echo "[FAIL] $skill: '\${CLAUDE_SKILL_DIR}/$rel' 는 스킬 디렉토리 밖을 가리킵니다 (심링크 설치에서 Read 실패)"; FAIL=$((FAIL+1)); continue ;;
    esac
    if [ ! -e "$dir/$rel" ]; then
      echo "[FAIL] $skill: '\${CLAUDE_SKILL_DIR}/$rel' 대상이 없습니다"; FAIL=$((FAIL+1))
    fi
  done
  # ③ 봇 주입 라인
  has_bot_line=0
  grep -qF '"${CLAUDE_SKILL_DIR}/references/bot-protocol.md"' "$dir/SKILL.md" && has_bot_line=1
  case "$NO_BOT" in
    *" $skill "*) [ $has_bot_line = 1 ] && { echo "[FAIL] $skill: CLI 전용 스킬에 bot-protocol 주입 라인이 있습니다"; FAIL=$((FAIL+1)); } ;;
    *) [ $has_bot_line = 1 ] || { echo "[FAIL] $skill: bot-protocol 주입 라인이 없습니다"; FAIL=$((FAIL+1)); } ;;
  esac
  # ④ 봇 마커 잔존
  # 주입 라인(!`…`)은 런타임 판정용으로 JOBCLAW_RUN_ID 를 언급하므로 제외한다
  hits=$(grep -nE 'IMAGE_PROMPT|\[CHOICES\]|OUTPUT_FILE|render-docx|JOBCLAW_RUN_ID' "$dir/SKILL.md" | grep -vE '^[0-9]+:!`' || true)
  if [ -n "$hits" ]; then
    echo "[FAIL] $skill: 봇 전용 마커가 SKILL.md 본문에 남아 있습니다 (references/bot-protocol.md 로 옮기세요):"
    echo "$hits" | sed 's/^/    /' | cut -c1-140
    FAIL=$((FAIL+1))
  fi
  # ⑤ bare docs/·templates/ 참조
  bare=$(grep -nE '(^|[^/A-Za-z0-9_])(docs|templates)/[A-Za-z0-9_-]+\.md' "$dir/SKILL.md" || true)
  if [ -n "$bare" ]; then
    echo "[FAIL] $skill: docs/·templates/ 를 직접 가리키는 참조가 있습니다 (\${CLAUDE_SKILL_DIR}/references/ 로 바꾸고 gen-skill-docs.sh 를 실행하세요):"
    echo "$bare" | sed 's/^/    /' | cut -c1-140
    FAIL=$((FAIL+1))
  fi
done

# ② 생성 파일 드리프트
if ! "$REPO/bin/gen-skill-docs.sh" --check; then
  FAIL=$((FAIL+1))
fi

if [ "$FAIL" -gt 0 ]; then
  echo "[FAIL] 스킬 참조 린트 ${FAIL}건"
  exit 1
fi
echo "[PASS] 모든 \${CLAUDE_SKILL_DIR} 참조가 스킬 디렉토리 안쪽을 가리키고 존재하며, 봇 마커가 본문에 없음"
exit 0
