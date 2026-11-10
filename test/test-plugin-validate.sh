#!/usr/bin/env bash
# claude plugin validate 게이트 (N-06) — 오류 0건, 경고는 test/plugin-validate-allowed.txt 에 있는 것만 허용한다.
#
# --strict 는 쓰지 않는다. 루트 CLAUDE.md(개발 가이드)와 아이콘 없음 경고를 알고 받아들였기 때문이며,
# 대신 "허용 목록에 없는 새 경고"를 실패로 본다. claude CLI 가 없는 환경에서는 SKIP(exit 0)한다 —
# 이 검사는 CLI 가 있는 곳(로컬, CLI 를 설치한 CI)에서만 게이트로 동작한다.
# 환경: JOBSTACK_VALIDATE_OUTPUT=<파일> 을 주면 CLI 를 부르지 않고 그 출력을 판정한다(테스트용).
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
  [ $R -eq 0 ] && echo "[PASS] self-test — 허용 경고 통과 · 새 경고 실패 · 오류 실패"
  exit $R
fi

if [ -n "${JOBSTACK_VALIDATE_OUTPUT:-}" ]; then
  OUT=$(cat "$JOBSTACK_VALIDATE_OUTPUT"); RC=0
  grep -q 'Validation failed' <<<"$OUT" && RC=1
elif command -v claude >/dev/null 2>&1; then
  OUT=$(cd "$REPO" && claude plugin validate . 2>&1); RC=$?
  # 로그인·네트워크 문제로 검증 자체가 돌지 않았으면(판정 줄 없음) 게이트로 쓰지 않고 SKIP 한다.
  if ! grep -qE 'Validation (passed|failed)' <<<"$OUT"; then
    echo "[SKIP] claude plugin validate 가 판정을 내지 못했습니다(exit $RC) — 출력 앞부분:"
    echo "$OUT" | head -5 | sed 's/^/    /'
    exit 0
  fi
else
  echo "[SKIP] claude CLI 가 없어 plugin validate 를 건너뜁니다 (CLI 가 있는 환경에서만 게이트로 동작)"
  exit 0
fi

# "Found N … warning/error" 머리줄 아래의 '  > ' 항목만 모은다("About these checks" 안내문의 '  > ' 는 제외).
ITEMS=$(awk '
  /Found [0-9]+ .*(warning|error)/ { kind = ($0 ~ /error/) ? "error" : "warning"; inblk = 1; next }
  inblk && /^  > /                { print kind "\t" substr($0, 5); next }
  inblk && /^[^ ]/                { inblk = 0 }
' <<<"$OUT")

FAIL=0
if [ "$RC" -ne 0 ]; then echo "[FAIL] claude plugin validate 가 실패했습니다(exit $RC)"; FAIL=1; fi
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
N=$(grep -c . <<<"$ITEMS" || true)
echo "[PASS] claude plugin validate — 오류 0건, 경고 ${N}건 모두 허용 목록 안"
