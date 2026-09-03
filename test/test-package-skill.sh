#!/usr/bin/env bash
# test-package-skill.sh — claude.ai/Cowork 업로드 패키지(U-18) 검증.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="${JOBSTACK_PACKAGE_BIN:-$REPO/bin/package-skill.sh}"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  [PASS] $1"; }
ng() { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jobstack-pkgtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

list_zip() { python3 -c "import sys,zipfile; print('\n'.join(zipfile.ZipFile(sys.argv[1]).namelist()))" "$1"; }

echo "## package-skill"
# 1. 단일 스킬
if OUTP=$(bash "$BIN" auto --out "$WORK/out" 2>&1) && [ -f "$WORK/out/auto.zip" ]; then ok "auto.zip 생성"; else ng "auto.zip 생성: $OUTP"; fi
NAMES=$(list_zip "$WORK/out/auto.zip" 2>/dev/null || true)
echo "$NAMES" | grep -q '^auto/SKILL.md$' && ok "SKILL.md 포함" || ng "SKILL.md 누락"
echo "$NAMES" | grep -q '^auto/references/guardrails.md$' && ok "references/guardrails.md 포함" || ng "guardrails 누락"
echo "$NAMES" | grep -q '^auto/scripts/preamble.sh$' && ok "scripts/preamble.sh 포함" || ng "preamble.sh 누락"
echo "$NAMES" | grep -q '^auto/references/cases.md$' && ok "스킬 소유 references 포함" || ng "스킬 소유 references 누락"
echo "$NAMES" | grep -qE '^auto/(bin|templates|docs)/' && ng "bin/templates/docs 가 섞임" || ok "bin/templates/docs 제외"

# 2. 전체 스킬
if bash "$BIN" all --out "$WORK/all" >/dev/null 2>&1; then
  N=$(ls "$WORK/all"/*.zip 2>/dev/null | wc -l | tr -d ' ')
  [ "$N" -ge 16 ] && ok "all → zip ${N}개" || ng "all → zip ${N}개(16 미만)"
else ng "all 실행 실패"; fi

# 3. 없는 스킬 → exit 1
bash "$BIN" no-such-skill --out "$WORK/x" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && ok "없는 스킬 exit 1" || ng "없는 스킬 exit $RC"

# 4. 참조 누락 → exit 2 (가짜 저장소)
mkdir -p "$WORK/fake/broken/scripts" "$WORK/fake/bin"
cp "$BIN" "$WORK/fake/bin/package-skill.sh"
printf -- '---\nname: broken\n---\n`${CLAUDE_SKILL_DIR}/references/missing.md` 를 Read\n' > "$WORK/fake/broken/SKILL.md"
touch "$WORK/fake/broken/scripts/preamble.sh"
JOBSTACK_ROOT="$WORK/fake" bash "$WORK/fake/bin/package-skill.sh" broken --out "$WORK/fake/out" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "참조 누락 exit 2" || ng "참조 누락 exit $RC"

# 5. 폴백 컨텍스트: 패키지만 풀어놓은 환경에서 preamble.sh 가 PREAMBLE_FALLBACK=true 를 낸다
mkdir -p "$WORK/unpacked" && (cd "$WORK/unpacked" && python3 -c "import zipfile; zipfile.ZipFile('$WORK/out/auto.zip').extractall('.')")
FB=$(cd "$WORK/unpacked" && HOME="$WORK/home" JOBSTACK_STATE_DIR="$WORK/state" bash auto/scripts/preamble.sh auto 2>/dev/null)
echo "$FB" | grep -q '^PREAMBLE_FALLBACK=true$' && ok "패키지 단독 실행 → 폴백 컨텍스트" || ng "폴백 컨텍스트 없음"

echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
