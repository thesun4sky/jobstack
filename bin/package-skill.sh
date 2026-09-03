#!/usr/bin/env bash
# package-skill.sh — 스킬을 claude.ai / Cowork 업로드용 zip 으로 묶는다 (U-18).
#
# 포함: <skill>/SKILL.md, <skill>/references/**, <skill>/scripts/preamble.sh
# 제외: bin/, templates/, docs/ — Cowork 에는 저장소가 없으므로 scripts/preamble.sh 는 bin/ 을 찾지 못해
#       최소 컨텍스트(PREAMBLE_FALLBACK=true)를 내고, 스킬은 상단 안내대로 상태 저장·스크립트 단계를 건너뛴다.
#
# 사용법: package-skill.sh <skill|all> [--out <dir>]     (기본 out: <repo>/dist/skills)
# 종료: 0 성공 · 1 인자/스킬 없음 · 2 참조 누락(SKILL.md 가 가리키는 references 파일이 패키지에 없음) · 3 zip 실패
set -u

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${JOBSTACK_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
OUT="$ROOT/dist/skills"

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "사용법: package-skill.sh <skill|all> [--out <dir>]" >&2; exit 1; }
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || { echo "옵션 --out 에 값이 필요합니다." >&2; exit 1; }
      OUT="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done
mkdir -p "$OUT" || { echo "출력 디렉토리를 만들 수 없습니다: $OUT" >&2; exit 3; }

skill_list() {
  if [ "$TARGET" = all ]; then
    for d in "$ROOT"/*/; do d="${d%/}"; [ -f "$d/SKILL.md" ] && basename "$d"; done
  else
    echo "$TARGET"
  fi
}

# zip 은 있으면 쓰고, 없으면 python3 zipfile 로 대체한다.
make_zip() { # $1=작업 디렉토리(스킬 상위) $2=스킬명 $3=출력 zip
  if command -v zip >/dev/null 2>&1; then
    (cd "$1" && zip -qr "$3" "$2")
  else
    python3 - "$1" "$2" "$3" <<'PY'
import os, sys, zipfile
base, skill, out = sys.argv[1:4]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(os.path.join(base, skill)):
        for f in sorted(files):
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, base))
PY
  fi
}

RC=0
for skill in $(skill_list); do
  SRC="$ROOT/$skill"
  if [ ! -f "$SRC/SKILL.md" ]; then echo "[FAIL] $skill: SKILL.md 없음" >&2; RC=1; continue; fi
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/jobstack-pkg.XXXXXX")" || {
    echo "[FAIL] $skill: 임시 작업 디렉토리를 만들 수 없습니다." >&2
    RC=3
    continue
  }
  mkdir -p "$WORK/$skill"
  cp "$SRC/SKILL.md" "$WORK/$skill/"
  [ -d "$SRC/references" ] && cp -R "$SRC/references" "$WORK/$skill/"
  if [ -d "$SRC/scripts" ]; then mkdir -p "$WORK/$skill/scripts"; cp "$SRC/scripts/preamble.sh" "$WORK/$skill/scripts/" 2>/dev/null || true; fi
  # 참조 무결성: SKILL.md 가 가리키는 references/·scripts/ 경로가 패키지 안에 있어야 한다
  MISSING=0
  for rel in $(grep -oE '\$\{?CLAUDE_SKILL_DIR\}?/[^ `"'"'"')>|,;]*' "$SRC/SKILL.md" | sed -E 's/^\$\{?CLAUDE_SKILL_DIR\}?\///; s/[.:]+$//' | sort -u); do
    [ -e "$WORK/$skill/$rel" ] || { echo "[FAIL] $skill: 패키지에 없는 참조 $rel" >&2; MISSING=1; }
  done
  if [ "$MISSING" = 1 ]; then RC=2; rm -rf "$WORK"; continue; fi
  ZIP="$OUT/$skill.zip"
  rm -f "$ZIP"
  if make_zip "$WORK" "$skill" "$ZIP"; then
    SIZE=$(wc -c < "$ZIP" | tr -d ' ')
    echo "$ZIP ($SIZE bytes)"
  else
    echo "[FAIL] $skill: zip 생성 실패" >&2; RC=3
  fi
  rm -rf "$WORK"
done
exit $RC
