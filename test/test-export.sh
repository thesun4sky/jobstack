#!/usr/bin/env bash
# bin/jobstack-export U-13(docx 내보내기 이중화) 회귀.
#
# pandoc 유무·버전에 따른 분기(기존 pandoc 경로 / 경고+Node 폴백 / exit 2)를 mktemp 격리
# 환경에서 검증한다. jobstack-export 를 실행할 때 PATH 를 node·grep·dirname·basename 만
# 심볼릭 링크한 전용 디렉터리로 좁혀서, 이 스크립트를 돌리는 호스트에 실제 pandoc 이
# 있든 없든 매 케이스가 같은 결과를 내도록 만든다(pandoc 이 필요한 케이스만 그 앞에
# 가짜 pandoc 디렉터리를 따로 붙인다).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
EXPORT="$REPO/bin/jobstack-export"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ── 실행 파일 절대경로를 호스트 PATH 제한 전에 미리 확보 ──
BASH_ABS="$(command -v bash)"
NODE_ABS="$(command -v node)"
GREP_ABS="$(command -v grep)"
DIRNAME_ABS="$(command -v dirname)"
BASENAME_ABS="$(command -v basename)"

CLEAN_BIN="$WORK/clean-bin"
mkdir -p "$CLEAN_BIN"
ln -sf "$NODE_ABS" "$CLEAN_BIN/node"
ln -sf "$GREP_ABS" "$CLEAN_BIN/grep"
ln -sf "$DIRNAME_ABS" "$CLEAN_BIN/dirname"
ln -sf "$BASENAME_ABS" "$CLEAN_BIN/basename"
BASE_RUN_PATH="$CLEAN_BIN"   # pandoc 없음(의도적으로 심볼릭 링크하지 않음)

# jobstack-export 를 지정한 PATH 로 실행한다. $1=PATH  나머지=jobstack-export 인자.
# bash 절대경로로 직접 실행해 셔뱅(#!/usr/bin/env bash)의 PATH 탐색을 우회한다.
run_export() {
  local runpath="$1"; shift
  PATH="$runpath" "$BASH_ABS" "$EXPORT" "$@"
}

# python3 로 .docx(zip) 유효성 + <w:tbl 존재 여부를 확인. echo: OK_NOTBL | OK_HASTBL | ZIPERR:...
zip_table_check() {
  python3 -c "
import sys, zipfile
try:
    with zipfile.ZipFile(sys.argv[1]) as z:
        xml = z.read('word/document.xml').decode('utf-8')
except Exception as e:
    print('ZIPERR:' + str(e))
    sys.exit(0)
print('OK_HASTBL' if '<w:tbl' in xml else 'OK_NOTBL')
" "$1"
}

# ── 공통 픽스처 ──
VALID_MD="$WORK/valid.md"
cat > "$VALID_MD" <<'MD'
# 홍길동 이력서

## 경력 요약

**백엔드 개발자** 로 3년 근무했습니다.

| 회사 | 기간 |
| --- | --- |
| 예시기업 | 2023-2025 |

- 성과1
- 성과2
MD

PLACEHOLDER_MD="$WORK/placeholder.md"
cat > "$PLACEHOLDER_MD" <<'MD'
# 홍길동 이력서

이메일: [이메일 확인 필요]
MD

echo "## test-export (U-13 docx 내보내기 이중화)"

# ── (1) placeholder 잔존 → exit 4, 파일 미생성 ──
OUT1="$WORK/case1.docx"
STDOUT1="$WORK/case1.stdout"; STDERR1="$WORK/case1.stderr"
run_export "$BASE_RUN_PATH" "$PLACEHOLDER_MD" "$OUT1" >"$STDOUT1" 2>"$STDERR1"
RC1=$?
[ "$RC1" -eq 4 ] && ok "(1) placeholder 잔존 → exit 4" || bad "(1) exit 코드" "rc=$RC1"
[ ! -f "$OUT1" ] && ok "(1) 파일 미생성" || bad "(1) 파일 미생성" "생성됨: $OUT1"
grep -q '확인 필요' "$STDERR1" && ok "(1) stderr 에 placeholder 항목 표시" || bad "(1) stderr 항목 표시" "$(cat "$STDERR1")"

# ── (2) PATH 에 pandoc 없음 + docx 있음 → exit 0, 절대경로, 표 태그 없음 ──
OUT2="$WORK/case2.docx"
STDOUT2="$WORK/case2.stdout"; STDERR2="$WORK/case2.stderr"
run_export "$BASE_RUN_PATH" "$VALID_MD" "$OUT2" >"$STDOUT2" 2>"$STDERR2"
RC2=$?
[ "$RC2" -eq 0 ] && ok "(2) pandoc 없음 + docx 있음 → exit 0" || bad "(2) exit 코드" "rc=$RC2 stderr=$(cat "$STDERR2")"
[ "$(wc -l < "$STDOUT2" | tr -d ' ')" = "1" ] && ok "(2) stdout 정확히 한 줄" || bad "(2) stdout 줄 수" "$(cat "$STDOUT2")"
STDOUT2_LINE="$(cat "$STDOUT2")"
case "$STDOUT2_LINE" in
  /*) ok "(2) stdout 절대경로" ;;
  *)  bad "(2) stdout 절대경로" "$STDOUT2_LINE" ;;
esac
[ -f "$STDOUT2_LINE" ] && ok "(2) stdout 경로에 실제 파일 존재" || bad "(2) 산출 파일 존재" "$STDOUT2_LINE"
R2="$(zip_table_check "$OUT2")"
[ "$R2" = "OK_NOTBL" ] && ok "(2) 산출 docx 에 <w:tbl 없음(유효 zip)" || bad "(2) 표 태그/zip 유효성" "$R2"

# ── (3) 가짜 pandoc 3.1.9(< 3.6) → 경고 + Node 폴백, 가짜의 '빈 파일' 동작은 호출되지 않아야 함 ──
FAKE3_DIR="$WORK/fake-pandoc-old"
mkdir -p "$FAKE3_DIR"
cat > "$FAKE3_DIR/pandoc" <<EOF
#!$BASH_ABS
if [ "\${1:-}" = "--version" ]; then
  echo "pandoc 3.1.9"
  echo "Compiled with pandoc-types 1.23"
  exit 0
fi
# 변환 모드(case 3 에서는 호출되면 안 됨 — 호출되면 zip 이 아닌 텍스트를 남겨 zip 검사가 이를 잡아낸다.
# force 케이스에서는 이 출력이 그대로 산출물이 되므로 비어 있지 않아야 한다 — jobstack-export 가
# pandoc 경로에서도 산출물 존재를 확인하기 때문(PR #17 리뷰 반영))
out=""; prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  prev="\$a"
done
[ -n "\$out" ] && echo "fake-pandoc-output" > "\$out"
exit 0
EOF
chmod +x "$FAKE3_DIR/pandoc"
RUN_PATH3="$FAKE3_DIR:$BASE_RUN_PATH"
OUT3="$WORK/case3.docx"
STDOUT3="$WORK/case3.stdout"; STDERR3="$WORK/case3.stderr"
run_export "$RUN_PATH3" "$VALID_MD" "$OUT3" >"$STDOUT3" 2>"$STDERR3"
RC3=$?
[ "$RC3" -eq 0 ] && ok "(3) pandoc 3.1.9(<3.6) → exit 0(Node 폴백)" || bad "(3) exit 코드" "rc=$RC3 stderr=$(cat "$STDERR3")"
grep -q '< 3.6' "$STDERR3" && ok "(3) stderr 버전 경고(< 3.6)" || bad "(3) 버전 경고" "$(cat "$STDERR3")"
grep -q 'Node docx 폴백' "$STDERR3" && ok "(3) stderr 폴백 알림" || bad "(3) 폴백 알림" "$(cat "$STDERR3")"
R3="$(zip_table_check "$OUT3")"
[ "$R3" = "OK_NOTBL" ] && ok "(3) 산출물이 Node 변환 유효 zip(가짜 pandoc 의 텍스트 파일이 아님)" || bad "(3) 산출물 zip 유효성" "$R3"

# ── (4) 가짜 pandoc 3.7.0(>= 3.6) → 실제 사용, 마커 파일로 호출 확인 ──
FAKE4_DIR="$WORK/fake-pandoc-new"
mkdir -p "$FAKE4_DIR"
MARKER4="$WORK/case4-pandoc-called.marker"
cat > "$FAKE4_DIR/pandoc" <<EOF
#!$BASH_ABS
if [ "\${1:-}" = "--version" ]; then
  echo "pandoc 3.7.0"
  echo "Compiled with pandoc-types 1.23"
  exit 0
fi
: > "$MARKER4"
out=""; prev=""
for a in "\$@"; do
  [ "\$prev" = "-o" ] && out="\$a"
  prev="\$a"
done
[ -n "\$out" ] && echo "fake-pandoc-output" > "\$out"
exit 0
EOF
chmod +x "$FAKE4_DIR/pandoc"
RUN_PATH4="$FAKE4_DIR:$BASE_RUN_PATH"
OUT4="$WORK/case4.docx"
STDOUT4="$WORK/case4.stdout"; STDERR4="$WORK/case4.stderr"
run_export "$RUN_PATH4" "$VALID_MD" "$OUT4" >"$STDOUT4" 2>"$STDERR4"
RC4=$?
[ "$RC4" -eq 0 ] && ok "(4) pandoc 3.7.0(>=3.6) → exit 0" || bad "(4) exit 코드" "rc=$RC4 stderr=$(cat "$STDERR4")"
[ -f "$MARKER4" ] && ok "(4) 가짜 pandoc 3.7.0 이 실제로 호출됨(마커 파일)" || bad "(4) pandoc 호출 확인" "마커 없음"
! grep -q 'Node docx 폴백' "$STDERR4" && ok "(4) Node 폴백 알림 없음(pandoc 경로 사용)" || bad "(4) 폴백 알림 없어야 함" "$(cat "$STDERR4")"

# ── (5) JOBSTACK_MD2DOCX=존재하지 않는 경로 + pandoc 없음 → exit 3 ──
OUT5="$WORK/case5.docx"
STDOUT5="$WORK/case5.stdout"; STDERR5="$WORK/case5.stderr"
JOBSTACK_MD2DOCX="$WORK/nonexistent-md2docx.mjs" run_export "$BASE_RUN_PATH" "$VALID_MD" "$OUT5" >"$STDOUT5" 2>"$STDERR5"
RC5=$?
[ "$RC5" -eq 3 ] && ok "(5) JOBSTACK_MD2DOCX 미존재 + pandoc 없음 → exit 3" || bad "(5) exit 코드" "rc=$RC5 stderr=$(cat "$STDERR5")"
[ ! -s "$OUT5" ] && ok "(5) 산출 파일 미생성(빈 상태)" || bad "(5) 산출 파일 없어야 함" "$(ls -la "$OUT5" 2>&1)"

# ── (6) JOBSTACK_MD2DOCX 가 'docx 패키지 없음'을 흉내내는 가짜 스크립트 → exit 2 ──
FAKE_NO_DOCX="$WORK/fake-no-docx.mjs"
cat > "$FAKE_NO_DOCX" <<'JS'
process.stderr.write('md2docx: `docx` 패키지가 없습니다 — bin/ 에서 `npm install` 후 재시도하세요\n');
process.exit(3);
JS
OUT6="$WORK/case6.docx"
STDOUT6="$WORK/case6.stdout"; STDERR6="$WORK/case6.stderr"
JOBSTACK_MD2DOCX="$FAKE_NO_DOCX" run_export "$BASE_RUN_PATH" "$VALID_MD" "$OUT6" >"$STDOUT6" 2>"$STDERR6"
RC6=$?
[ "$RC6" -eq 2 ] && ok "(6) docx 패키지 없음 시늉 → exit 2" || bad "(6) exit 코드" "rc=$RC6 stderr=$(cat "$STDERR6")"
grep -q 'brew install pandoc' "$STDERR6" && ok "(6) exit 2 안내에 pandoc 설치법 포함" || bad "(6) pandoc 설치법 안내" "$(cat "$STDERR6")"
grep -q 'npm install' "$STDERR6" && ok "(6) exit 2 안내에 npm install 설치법 포함" || bad "(6) npm install 안내" "$(cat "$STDERR6")"

# ── JOBSTACK_EXPORT_FORCE_PANDOC=1 → 구버전 pandoc 이라도 경고만 내고 그대로 사용 ──
OUT7="$WORK/case7.docx"
STDOUT7="$WORK/case7.stdout"; STDERR7="$WORK/case7.stderr"
JOBSTACK_EXPORT_FORCE_PANDOC=1 run_export "$RUN_PATH3" "$VALID_MD" "$OUT7" >"$STDOUT7" 2>"$STDERR7"
RC7=$?
[ "$RC7" -eq 0 ] && ok "(force) FORCE_PANDOC=1 + pandoc 3.1.9 → exit 0" || bad "(force) exit 코드" "rc=$RC7 stderr=$(cat "$STDERR7")"
grep -q '< 3.6' "$STDERR7" && ok "(force) 버전 경고는 그대로 출력" || bad "(force) 버전 경고" "$(cat "$STDERR7")"
grep -q "fake-pandoc-output" "$OUT7" 2>/dev/null && ok "(force) 가짜 pandoc 의 출력이 그대로 산출물(pandoc 경로 사용)" || bad "(force) pandoc 강행 확인" "$(ls -la "$OUT7" 2>&1)"

# ── (8) 심링크를 거친 bin 경로로 실행(macOS /tmp → /private/tmp 재현) → Node 폴백이 실제로 파일을 만든다 ──
# PR #17 리뷰 반영: md2docx.mjs 의 CLI 진입 판정이 심링크 경로에서 어긋나 exit 0 인데 산출물이 없던 회귀.
ln -s "$REPO/bin" "$WORK/binlink"
OUT8="$WORK/case8.docx"
STDOUT8="$WORK/case8.stdout"; STDERR8="$WORK/case8.stderr"
PATH="$BASE_RUN_PATH" "$BASH_ABS" "$WORK/binlink/jobstack-export" "$VALID_MD" "$OUT8" >"$STDOUT8" 2>"$STDERR8"
RC8=$?
[ "$RC8" -eq 0 ] && ok "(8) 심링크 경로 실행 → exit 0" || bad "(8) exit 코드" "rc=$RC8 stderr=$(cat "$STDERR8")"
[ -s "$OUT8" ] && ok "(8) 심링크 경로 실행에서도 산출물 존재" || bad "(8) 산출물 존재" "$OUT8 없음"
R8="$(zip_table_check "$OUT8")"
[ "$R8" = "OK_NOTBL" ] && ok "(8) 산출물 유효 zip" || bad "(8) 산출물 zip 유효성" "$R8"

# ── (9) 변환기가 exit 0 을 내고도 파일을 만들지 않으면 성공으로 보고하지 않는다 → exit 3 ──
FAKE_NOOP="$WORK/fake-noop-md2docx.mjs"
cat > "$FAKE_NOOP" <<'NOOP_EOF'
process.stdout.write(process.argv[3] + '\n');
NOOP_EOF
OUT9="$WORK/case9.docx"
STDOUT9="$WORK/case9.stdout"; STDERR9="$WORK/case9.stderr"
JOBSTACK_MD2DOCX="$FAKE_NOOP" run_export "$BASE_RUN_PATH" "$VALID_MD" "$OUT9" >"$STDOUT9" 2>"$STDERR9"
RC9=$?
[ "$RC9" -eq 3 ] && ok "(9) 산출물 없는 exit 0 변환기 → exit 3" || bad "(9) exit 코드" "rc=$RC9 stdout=$(cat "$STDOUT9")"
[ ! -s "$STDOUT9" ] && ok "(9) stdout 에 성공 경로를 출력하지 않음" || bad "(9) stdout" "$(cat "$STDOUT9")"
grep -q '산출물' "$STDERR9" && ok "(9) stderr 에 산출물 부재 안내" || bad "(9) stderr 안내" "$(cat "$STDERR9")"

echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] test-export"; exit 0; } || { echo "[FAIL] test-export"; exit 1; }
