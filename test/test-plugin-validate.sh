#!/usr/bin/env bash
# claude plugin validate 게이트 (N-06) — 오류 0건, 경고는 test/plugin-validate-allowed.txt 에 있는 것만 허용한다.
#
# --strict 는 쓰지 않는다. 루트 CLAUDE.md(개발 가이드)와 아이콘 없음 경고를 알고 받아들였기 때문이며,
# 대신 "허용 목록에 없는 새 경고"를 실패로 본다. claude CLI 가 없는 환경에서는 SKIP(exit 0)한다 —
# 이 검사는 CLI 가 있는 곳(로컬, CLI 를 설치한 CI)에서만 게이트로 동작한다.
# 환경: JOBSTACK_VALIDATE_OUTPUT=<파일> 을 주면 CLI 를 부르지 않고 그 출력을 판정한다(테스트용).
#       JOBSTACK_REQUIRE_VALIDATE=1 이면 SKIP 을 실패로 본다(CI 용 — 게이트가 조용히 꺼지지 않게).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOW="${JOBSTACK_VALIDATE_ALLOW:-$SCRIPT_DIR/plugin-validate-allowed.txt}"

if [ "${1:-}" = "--self-test" ]; then
  T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
  printf 'CLAUDE\\.md at the plugin root\n' > "$T/allow"
  printf 'Validating plugin\n\n! Found 1 warning:\n\n  > root: CLAUDE.md at the plugin root is not loaded\n\nAbout these checks:\n\n  > 안내문은 경고가 아니다\n\nValidation passed with warnings\n' > "$T/ok"
  printf 'Validating plugin\n\n! Found 2 warnings:\n\n  > root: CLAUDE.md at the plugin root is not loaded\n  > skills/x: 새로 생긴 경고\n    Fix: 이어지는 줄\n\nValidation passed with warnings\n' > "$T/new"
  printf 'Validating plugin\n\nx Found 1 error:\n\n  > plugin.json: name 누락\n\nValidation failed\n' > "$T/err"
  R=0
  JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/ok"  bash "$0" >/dev/null 2>&1 || { echo "[FAIL] self-test: 허용된 경고만 있는데 실패"; R=1; }
  JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/new" bash "$0" >/dev/null 2>&1 && { echo "[FAIL] self-test: 새 경고를 놓침"; R=1; }
  JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/err" bash "$0" >/dev/null 2>&1 && { echo "[FAIL] self-test: 오류를 놓침"; R=1; }
  # 제출 거부 블록(머리줄에 warning·error 라는 말이 없다)도 오류로 본다 (리뷰 C3)
  printf 'Validating plugin\n\nx Found 1 problem the plugin directory refuses a submission for:\n\n  > LICENSE: License missing (LICENSE_MISSING).\n\nValidation passed\n' > "$T/refuse"
  JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/refuse" bash "$0" >/dev/null 2>&1 && { echo "[FAIL] self-test: 제출 거부 블록을 놓침"; R=1; }
  # 출력 형식이 바뀌어 항목을 못 읽으면 통과시키지 않는다 (리뷰 C4)
  printf 'Validating plugin\n\n! Found 2 warnings:\n\n* 들여쓰기가 바뀐 경고\n* 또 하나\n\nValidation passed with warnings\n' > "$T/fmt"
  JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/fmt" bash "$0" >/dev/null 2>&1 && { echo "[FAIL] self-test: 머리줄 건수와 항목 수 불일치를 놓침"; R=1; }
  printf 'Validating plugin\n\nWarnings (1):\n\n  > 머리줄이 바뀐 경고\n\nValidation passed with warnings\n' > "$T/hdr"
  JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/hdr" bash "$0" >/dev/null 2>&1 && { echo "[FAIL] self-test: passed with warnings 인데 항목 0건을 놓침"; R=1; }
  JOBSTACK_REQUIRE_VALIDATE=1 PATH=/nonexistent /bin/bash "$0" >/dev/null 2>&1 && { echo "[FAIL] self-test: REQUIRE 인데 CLI 없음이 통과"; R=1; }
  # 불릿 글리프가 달라도(❯) 같은 항목으로 읽는다 — 터미널·로케일에 따라 CLI 가 바꿔 낸다(실측)
  printf 'Validating plugin\n\n\xe2\x9a\xa0 Found 2 warnings:\n\n  \xe2\x9d\xaf root: CLAUDE.md at the plugin root is not loaded\n  \xe2\x9d\xaf skills/x: 새 경고\n\nValidation passed with warnings\n' > "$T/glyph"
  GO=$(JOBSTACK_VALIDATE_ALLOW="$T/allow" JOBSTACK_VALIDATE_OUTPUT="$T/glyph" bash "$0" 2>&1) && { echo "[FAIL] self-test: ❯ 불릿의 새 경고를 놓침"; R=1; }
  grep -q '허용 목록에 없는 경고: skills/x' <<<"$GO" || { echo "[FAIL] self-test: ❯ 불릿 항목을 읽지 못함"; R=1; }
  [ $R -eq 0 ] && echo "[PASS] self-test — 허용 경고 통과 · 새 경고·오류·제출 거부·형식 변화·필수 모드 SKIP 은 실패"
  exit $R
fi

skip() { # $1=사유
  if [ "${JOBSTACK_REQUIRE_VALIDATE:-}" = 1 ]; then echo "[FAIL] $1 (JOBSTACK_REQUIRE_VALIDATE=1 — SKIP 불가)"; exit 1; fi
  echo "[SKIP] $1"; exit 0
}

if [ -n "${JOBSTACK_VALIDATE_OUTPUT:-}" ]; then
  OUT=$(cat "$JOBSTACK_VALIDATE_OUTPUT"); RC=0
  grep -q 'Validation failed' <<<"$OUT" && RC=1
elif command -v claude >/dev/null 2>&1; then
  OUT=$(cd "$REPO" && claude plugin validate . 2>&1); RC=$?
  # 로그인·네트워크 문제로 검증 자체가 돌지 않았으면(판정 줄 없음) 게이트로 쓰지 않고 SKIP 한다.
  if ! grep -qE 'Validation (passed|failed)' <<<"$OUT"; then
    echo "$OUT" | head -5 | sed 's/^/    /'
    skip "claude plugin validate 가 판정을 내지 못했습니다(exit $RC)"
  fi
else
  skip "claude CLI 가 없어 plugin validate 를 건너뜁니다 (CLI 가 있는 환경에서만 게이트로 동작)"
fi

# "Found N …" 머리줄 아래의 '  > ' 항목만 모은다("About these checks" 안내문의 '  > ' 는 머리줄이 없어 제외된다).
# 머리줄에 warning 이 있으면 경고, 그 밖(error·problem·refuses …)은 전부 오류로 본다.
PARSED=$(awk '
  /Found [0-9]+ / { kind = ($0 ~ /warning/) ? "warning" : "error"; inblk = 1
                    for (i = 1; i <= NF; i++) if ($i == "Found") { declared += $(i+1); break }
                    next }
  # 항목 줄 = 들여쓰기 2칸 + 불릿 한 토큰(터미널에 따라 ">" 또는 "❯") + 공백. 이어지는 줄("    Fix: …")은 4칸이라 제외된다.
  inblk && /^  [^ ]+ / { line = $0; sub(/^  [^ ]+ /, "", line); print kind "\t" line; next }
  inblk && /^[^ ]/   { inblk = 0 }
  END { print "DECLARED\t" declared + 0 }
' <<<"$OUT")
DECLARED=$(awk -F'\t' '$1=="DECLARED"{print $2}' <<<"$PARSED")
ITEMS=$(grep -v '^DECLARED' <<<"$PARSED" || true)
N=$(grep -c . <<<"$ITEMS" || true)

FAIL=0
if [ "$RC" -ne 0 ]; then echo "[FAIL] claude plugin validate 가 실패했습니다(exit $RC)"; FAIL=1; fi
# 출력 형식이 바뀌어 항목을 못 읽은 채 통과하는 일을 막는다.
if [ "${DECLARED:-0}" -ne "${N:-0}" ]; then echo "[FAIL] 머리줄이 알린 건수(${DECLARED})와 읽은 항목 수(${N})가 다릅니다 — CLI 출력 형식이 바뀌었는지 확인하세요"; FAIL=1; fi
if grep -q 'passed with warnings' <<<"$OUT" && [ "${N:-0}" -eq 0 ]; then echo "[FAIL] 경고가 있다는데 항목을 하나도 읽지 못했습니다 — CLI 출력 형식 확인"; FAIL=1; fi
while IFS=$'\t' read -r kind msg; do
  [ -n "${kind:-}" ] || continue
  if [ "$kind" = error ]; then echo "[FAIL] 오류: $msg"; FAIL=1; continue; fi
  allowed=0
  while IFS= read -r pat; do
    case "$pat" in ''|'#'*) continue ;; esac
    grep -qE -- "$pat" <<<"$msg" && { allowed=1; break; }
  done < "$ALLOW"
  [ $allowed -eq 1 ] || { echo "[FAIL] 허용 목록에 없는 경고: $msg"; FAIL=1; }
done <<<"$ITEMS"

if [ $FAIL -ne 0 ]; then
  echo "  새 경고가 의도된 것이면 test/plugin-validate-allowed.txt 에 사유와 함께 추가하세요."
  echo "$OUT" | sed 's/^/    /' | head -40
  exit 1
fi
echo "[PASS] claude plugin validate — 오류 0건, 경고 ${N}건 모두 허용 목록 안"
