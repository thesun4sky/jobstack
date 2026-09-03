#!/usr/bin/env bash
# gen-skill-docs.sh — 스킬 디렉토리의 생성 파일을 templates/·docs/ 원본에서 동기화한다.
#
#   <skill>/scripts/preamble.sh   ← templates/skill-preamble.sh (동일 내용)
#   <skill>/references/<name>.md  ← templates/<name>.md 또는 docs/<name>.md
#   <skill>/references/bot-protocol.md ← templates/bot-protocol.md + templates/bot/<skill>.md (있으면)
#
# 각 스킬이 어떤 참조 파일을 필요로 하는지는 SKILL.md 본문의
# `${CLAUDE_SKILL_DIR}/references/<name>.md`(또는 bare `references/<name>.md`) 언급에서 읽는다. guardrails.md 는 항상 포함하고,
# bot-protocol.md 는 봇에 노출되는 스킬(tracker·ncs 제외)에 항상 포함한다.
#
# 스킬 안에 복제본을 두는 이유(검토 보고서 D-1): Claude Code 의 Read 도구는 심링크 설치에서
# ${CLAUDE_SKILL_DIR}/../templates/… 경로를 열지 못한다. 참조는 스킬 디렉토리 안쪽만 가리켜야 한다.
#
# 사용법: gen-skill-docs.sh            # 생성/갱신
#         gen-skill-docs.sh --check    # 드리프트 검사만 (CI). 차이가 있으면 exit 1
set -euo pipefail

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"
TEMPLATES="$ROOT/templates"
DOCS="$ROOT/docs"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

NO_BOT_SKILLS=" tracker ncs "

# 스킬 디렉토리 목록 (저장소 루트 배치와 skills/ 배치 둘 다 지원)
skill_dirs() {
  local d
  for d in "$ROOT"/skills/*/ "$ROOT"/*/; do
    d="${d%/}"
    [ -f "$d/SKILL.md" ] && echo "$d"
  done | sort -u
}

DRIFT=0
COUNT=0

sync_file() { # $1=source $2=target
  local src="$1" dst="$2"
  if [ "$CHECK" = 1 ]; then
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
      echo "  [DRIFT] ${dst#$ROOT/}  ←  ${src#$ROOT/}"
      DRIFT=$((DRIFT + 1))
    fi
  else
    mkdir -p "$(dirname "$dst")"
    if [ ! -f "$dst" ] || ! cmp -s "$src" "$dst"; then
      cp "$src" "$dst"
      echo "  updated: ${dst#$ROOT/}"
    fi
  fi
}

for dir in $(skill_dirs); do
  skill="$(basename "$dir")"
  COUNT=$((COUNT + 1))

  # 1. scripts/preamble.sh
  sync_file "$TEMPLATES/skill-preamble.sh" "$dir/scripts/preamble.sh"
  [ "$CHECK" = 1 ] || chmod +x "$dir/scripts/preamble.sh"

  # 2. references/*.md — SKILL.md 가 언급하는 것 + guardrails + (봇 노출 스킬) bot-protocol
  refs=$(grep -oE '(\$\{?CLAUDE_SKILL_DIR\}?/)?references/[A-Za-z0-9_-]+\.md' "$dir/SKILL.md" 2>/dev/null \
         | sed -E 's#^.*references/##' | sort -u || true)
  refs="$refs guardrails.md"
  case "$NO_BOT_SKILLS" in *" $skill "*) ;; *) refs="$refs bot-protocol.md" ;; esac

  wanted=""
  for name in $refs; do
    wanted="$wanted $name"
    if [ "$name" = "bot-protocol.md" ]; then
      tmp="$(mktemp "${TMPDIR:-/tmp}/jobstack-botproto.XXXXXX")"
      cat "$TEMPLATES/bot-protocol.md" > "$tmp"
      if [ -f "$TEMPLATES/bot/$skill.md" ]; then
        printf '\n---\n\n' >> "$tmp"
        cat "$TEMPLATES/bot/$skill.md" >> "$tmp"
      fi
      sync_file "$tmp" "$dir/references/bot-protocol.md"
      rm -f "$tmp"
    elif [ -f "$TEMPLATES/$name" ]; then
      sync_file "$TEMPLATES/$name" "$dir/references/$name"
    elif [ -f "$DOCS/$name" ]; then
      sync_file "$DOCS/$name" "$dir/references/$name"
    else
      echo "  [ERROR] $skill/SKILL.md 가 참조하는 references/$name 의 원본이 templates/ 나 docs/ 에 없습니다" >&2
      DRIFT=$((DRIFT + 1))
    fi
  done

  # 3. 참조되지 않는 생성 파일은 경고 (원본이 없어진 복제본)
  if [ -d "$dir/references" ]; then
    for f in "$dir"/references/*.md; do
      [ -f "$f" ] || continue
      base="$(basename "$f")"
      case " $wanted " in *" $base "*) ;; *)
        echo "  [WARN] ${f#$ROOT/} 는 SKILL.md 가 참조하지 않는 복제본입니다 (삭제 검토)"
        ;;
      esac
    done
  fi
done

if [ "$CHECK" = 1 ]; then
  if [ "$DRIFT" -gt 0 ]; then
    echo "[FAIL] 생성 파일 드리프트 ${DRIFT}건 — bin/gen-skill-docs.sh 를 실행해 동기화하세요"
    exit 1
  fi
  echo "[PASS] 스킬 ${COUNT}개의 scripts/·references/ 가 templates/·docs/ 원본과 일치"
else
  echo "Done. ${COUNT} skill(s) synced."
fi
