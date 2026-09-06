#!/usr/bin/env bash
# bin/jobstack-cron 결정적 동작 테스트 (v1.0 U-14 초안).
#
# fetch-jobs.mjs 는 실행하지 않는다 — JOBSTACK_FETCH_JOBS 훅으로 가짜 스크립트를
# 주입해 네트워크·Playwright 없이 검증한다(스크립트에 구현된 훅, jobstack-cron 참고).
#
# jobstack-tracker 는 이 디렉토리(OUT/bin)에 없으므로 JOBSTACK_TRACKER_BIN 훅으로
# 저장소의 실제 bin/jobstack-tracker 를 가리켜야 한다. 이 스크립트가 저장소의
# test/ 로 통합되면(OUT 과 동일한 상대 경로) 기본값이 그대로 "../bin/jobstack-tracker"
# 를 가리키므로 훅 없이도 동작한다 — 지금은(초안 단계) 다음처럼 실행한다:
#   JOBSTACK_TRACKER_BIN=/path/to/jobstack/bin/jobstack-tracker bash OUT/test/test-cron.sh
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRON="$OUT_ROOT/bin/jobstack-cron"
TRACKER_BIN="${JOBSTACK_TRACKER_BIN:-$OUT_ROOT/bin/jobstack-tracker}"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }       # has NAME NEEDLE TEXT
hasnt() { grep -q -- "$2" <<<"$3" && bad "$1" "$3" || ok "$1"; }

[ -x "$CRON" ] || { echo "[FAIL] jobstack-cron 실행 파일 없음: $CRON"; exit 1; }
if [ ! -x "$TRACKER_BIN" ]; then
  echo "[안내] jobstack-tracker 를 찾을 수 없습니다: $TRACKER_BIN"
  echo "       JOBSTACK_TRACKER_BIN=<저장소>/bin/jobstack-tracker 로 지정해 다시 실행하세요."
fi

echo "## jobstack-cron"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/jobstack-cron-test.XXXXXX")"
FAKE="$WORK/fake-fetch-jobs.sh"
TODAY="$(TZ=Asia/Seoul date +%Y-%m-%d)"

# ─── 픽스처 fetch-jobs — $1=platform $2=keyword $3=limit $4=career $5=location ──
# saramin: 가까운(+3일)·먼(+30일) 마감 각 1건 (ISO 날짜 파싱 경로)
# jumpit : "N일 후 마감" 형식으로 가까운 마감 1건 (점핏 파싱 경로)
# wanted : 0건 (실제로도 자주 0건인 케이스를 재현)
# jobkorea: 상시채용 1건 (구체 날짜 없는 마감 — D-7 집계 제외 경로)
# FAKE_FAIL_PLATFORM 환경변수로 지정한 플랫폼은 실패(exit 1)를 흉내낸다.
cat > "$FAKE" <<'FAKE_EOF'
#!/usr/bin/env bash
platform="$1"
if [ -n "${FAKE_FAIL_ALL:-}" ]; then
  echo "[fixture] simulated failure (all platforms)" >&2
  exit 1
fi
if [ -n "${FAKE_FAIL_PLATFORM:-}" ] && [ "$platform" = "$FAKE_FAIL_PLATFORM" ]; then
  echo "[fixture] simulated failure for $platform" >&2
  exit 1
fi
soon=$(TZ=Asia/Seoul date -d '+3 day' +%Y-%m-%d 2>/dev/null || TZ=Asia/Seoul date -v+3d +%Y-%m-%d)
far=$(TZ=Asia/Seoul date -d '+30 day' +%Y-%m-%d 2>/dev/null || TZ=Asia/Seoul date -v+30d +%Y-%m-%d)
case "$platform" in
  saramin)
    printf '[{"platform":"saramin","company":"가까운전자","title":"백엔드 개발자","deadline":"%s","link":"https://fixture.example/saramin/1"},{"platform":"saramin","company":"먼회사","title":"서버 개발자","deadline":"%s","link":"https://fixture.example/saramin/2"}]\n' "$soon" "$far"
    ;;
  jumpit)
    echo '[{"platform":"jumpit","company":"점핏가까운","title":"백엔드 엔지니어","deadline":"5일 후 마감","link":"https://fixture.example/jumpit/1"}]'
    ;;
  wanted)
    echo '[]'
    ;;
  jobkorea)
    echo '[{"platform":"jobkorea","company":"잡코리아상시","title":"신입 백엔드","deadline":"상시채용","link":"https://fixture.example/jobkorea/1"}]'
    ;;
  *)
    echo '[]'
    ;;
esac
FAKE_EOF
chmod +x "$FAKE"

# ── (d) 검색 조건 없음 → exit 1 ─────────────────────────────────────────────
STATE_D="$WORK/state-d"
OUT_D=$(JOBSTACK_STATE_DIR="$STATE_D" JOBSTACK_FETCH_JOBS="$FAKE" "$CRON" run 2>&1); RC_D=$?
[ "$RC_D" -eq 1 ] && ok "(d) 검색 조건 없음 → exit 1" || bad "(d) 조건 없음 exit 코드" "rc=$RC_D"
has "(d) 조건 없음 안내 메시지" "jobstack-config set cron_keyword" "$OUT_D"
if ls "$STATE_D/job-cache"/daily-*.md >/dev/null 2>&1; then
  bad "(d) 조건 없을 때 daily 파일이 생기면 안 됨" "$(ls "$STATE_D/job-cache"/daily-*.md 2>/dev/null)"
else
  ok "(d) 조건 없을 때 daily 파일 미생성"
fi

# ── (a) daily 파일 생성 · 새 공고만 포함 + (b) 마감 D-7 이내 ───────────────
STATE_A="$WORK/state-a"
DAILY_A="$STATE_A/job-cache/daily-$TODAY.md"
OUT1=$(JOBSTACK_STATE_DIR="$STATE_A" JOBSTACK_FETCH_JOBS="$FAKE" JOBSTACK_TRACKER_BIN="$TRACKER_BIN" \
  "$CRON" run --keyword 백엔드 --career entry --location seoul --limit 5 2>&1); RC1=$?
[ "$RC1" -eq 0 ] && ok "(a) 1회차 run exit 0" || bad "(a) 1회차 exit 코드" "rc=$RC1 / $OUT1"
[ -f "$DAILY_A" ] && ok "(a) daily 파일 생성" || bad "(a) daily 파일 생성" "$DAILY_A 없음"
has "(a) 1회차 새 공고 4건 보고(stdout)" "새 공고 4건" "$OUT1"
D1="$(cat "$DAILY_A" 2>/dev/null)"
has "(a) 새 공고 표에 saramin 픽스처 포함" "가까운전자" "$D1"
has "(a) 새 공고 표에 jobkorea 픽스처 포함" "잡코리아상시" "$D1"
has "(a) daily 파일에 검색 조건(직무) 표기" "직무: 백엔드" "$D1"

D1_D7="$(printf '%s\n' "$D1" | sed -n '/마감 D-7 이내/,/^## /p')"
has "(b) D-7 섹션 헤더 2건 집계" "마감 D-7 이내 (2건)" "$D1"
has "(b) ISO 날짜(+3일) 마감 공고가 D-7 표에 포함" "가까운전자" "$D1_D7"
has "(b) 'N일 후 마감' 형식 공고가 D-7 표에 포함" "점핏가까운" "$D1_D7"
hasnt "(b) +30일 마감 공고는 D-7 표에서 제외" "먼회사" "$D1_D7"
hasnt "(b) 상시채용(구체 날짜 없음)은 D-7 표에서 제외" "잡코리아상시" "$D1_D7"

OUT2=$(JOBSTACK_STATE_DIR="$STATE_A" JOBSTACK_FETCH_JOBS="$FAKE" JOBSTACK_TRACKER_BIN="$TRACKER_BIN" \
  "$CRON" run --keyword 백엔드 --career entry --location seoul --limit 5 2>&1); RC2=$?
[ "$RC2" -eq 0 ] && ok "(a) 2회차 run exit 0" || bad "(a) 2회차 exit 코드" "rc=$RC2"
has "(a) 2회차 새 공고 0건(중복 제외) — stdout" "새 공고 0건" "$OUT2"
D2="$(cat "$DAILY_A" 2>/dev/null)"
has "(a) 2회차 daily 파일에 '이전 실행과 동일' 문구" "이전 실행과 동일" "$D2"
has "(a) 2회차에도 D-7 표는 그대로 유지" "가까운전자" "$(printf '%s\n' "$D2" | sed -n '/마감 D-7 이내/,/^## /p')"

# ── (c) 지원 정체 알림(nudge) 섹션 ───────────────────────────────────────
has "(c) 지원 정체 알림 섹션 헤더 존재" "지원 정체 알림" "$D1"
if [ -x "$TRACKER_BIN" ]; then
  STATE_C="$WORK/state-c"
  ADD_OUT=$(JOBSTACK_STATE_DIR="$STATE_C" "$TRACKER_BIN" add --company 넛지테스트 --position 백엔드 --status applied 2>&1)
  has "(c) tracker add 성공" "추가됨" "$ADD_OUT"
  OUT_C=$(JOBSTACK_STATE_DIR="$STATE_C" JOBSTACK_FETCH_JOBS="$FAKE" JOBSTACK_TRACKER_BIN="$TRACKER_BIN" \
    "$CRON" run --keyword 테스트 2>&1); RC_C=$?
  [ "$RC_C" -eq 0 ] && ok "(c) nudge 연동 run exit 0" || bad "(c) nudge 연동 exit 코드" "rc=$RC_C"
  DAILY_C="$STATE_C/job-cache/daily-$TODAY.md"
  NUDGE_C="$(sed -n '/지원 정체 알림/,$p' "$DAILY_C" 2>/dev/null)"
  # 방금(오늘) add 한 항목은 nudge 기본 기준(7일)에 걸리지 않는다 — mtime 조작 없이
  # "정체 항목 없음" 문구가 그대로 뜨는지만 확인한다(과제 지시대로).
  has "(c) 방금 add한 항목은 정체 없음 문구로 표시" "정체 항목 없음" "$NUDGE_C"
else
  bad "(c) nudge 연동 테스트" "JOBSTACK_TRACKER_BIN 실행 불가: $TRACKER_BIN"
fi

# ── (e) install --dry-run 출력에 마커 ────────────────────────────────────
STATE_E="$WORK/state-e"
# Linux 기대값(crontab 마커·시각 포맷)이므로 macOS 호스트에서도 OS 를 고정한다(PR #17 리뷰 반영)
OUT_E=$(JOBSTACK_STATE_DIR="$STATE_E" JOBSTACK_CRON_OS_NAME=Linux "$CRON" install --time 07:30 --dry-run 2>&1); RC_E=$?
[ "$RC_E" -eq 0 ] && ok "(e) install --dry-run exit 0" || bad "(e) install --dry-run exit 코드" "rc=$RC_E"
has "(e) install --dry-run 출력에 jobstack-cron 마커" "# jobstack-cron" "$OUT_E"
has "(e) install --dry-run 은 실제 등록 생략 안내" "dry-run" "$OUT_E"
has "(e) install --dry-run 출력에 지정한 시각 반영" "30 7 \* \* \*" "$OUT_E"
has "(e) crontab 항목에 PATH 지정(축소된 cron PATH 에서 node·python3 탐색)" 'PATH="' "$OUT_E"

# ── (f) 플랫폼 실패 시 표기 ───────────────────────────────────────────────
STATE_F="$WORK/state-f"
DAILY_F="$STATE_F/job-cache/daily-$TODAY.md"
OUT_F=$(JOBSTACK_STATE_DIR="$STATE_F" JOBSTACK_FETCH_JOBS="$FAKE" FAKE_FAIL_PLATFORM=jobkorea \
  JOBSTACK_TRACKER_BIN="$TRACKER_BIN" "$CRON" run --keyword 실패테스트 2>&1); RC_F=$?
[ "$RC_F" -eq 0 ] && ok "(f) 일부 플랫폼 실패해도 exit 0" || bad "(f) 플랫폼 실패 시 exit 코드" "rc=$RC_F"
[ -f "$DAILY_F" ] && ok "(f) 플랫폼 실패해도 daily 파일 생성됨" || bad "(f) 플랫폼 실패 시 daily 파일" "$DAILY_F 없음"
has "(f) 실행 결과(stdout)에 실패 플랫폼 표기" "수집 실패: jobkorea" "$OUT_F"
DF="$(cat "$DAILY_F" 2>/dev/null)"
has "(f) daily 파일 헤더에 수집 실패 표기" "수집 실패: jobkorea" "$DF"
has "(f) daily 파일에 성공 플랫폼도 함께 표기" "수집 성공: saramin, jumpit, wanted" "$DF"
has "(f) 실패 플랫폼을 제외한 새 공고 3건 집계" "새 공고 3건" "$OUT_F"

# ── (g) status: 실행 기록 없음 문구 ────────────────────────────────────────
STATE_G="$WORK/state-g"
OUT_G=$(JOBSTACK_STATE_DIR="$STATE_G" "$CRON" status 2>&1); RC_G=$?
[ "$RC_G" -eq 0 ] && ok "(g) status exit 0" || bad "(g) status exit 코드" "rc=$RC_G"
has "(g) status: 실행 기록 없음 문구" "마지막 실행 기록 없음" "$OUT_G"

# ── (h) uninstall: 마커 없는 crontab 에서 안전 종료 ────────────────────────
# 실제 crontab 을 절대 건드리지 않도록 PATH 맨 앞에 가짜 crontab 을 둔다. 가짜는 -l 에
# jobstack-cron 마커가 없는 다른 항목을 돌려주고, - (쓰기)가 호출되면 실패로 표시한다 —
# 마커가 없으면 uninstall 은 애초에 crontab - 를 부르지 않아야 하므로, 이 표시가 나오면 버그다.
FAKEBIN="$WORK/fakebin"
mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/crontab" <<'FAKECRONTAB_EOF'
#!/usr/bin/env bash
case "$1" in
  -l) echo "0 9 * * * /some/other/job.sh  # not-jobstack-cron"; exit 0 ;;
  -) cat >/dev/null; echo "[fake crontab] unexpected write attempt" >&2; exit 9 ;;
  *) exit 0 ;;
esac
FAKECRONTAB_EOF
chmod +x "$FAKEBIN/crontab"
STATE_H="$WORK/state-h"
OUT_H=$(PATH="$FAKEBIN:$PATH" JOBSTACK_STATE_DIR="$STATE_H" JOBSTACK_CRON_OS_NAME=Linux "$CRON" uninstall 2>&1); RC_H=$?
[ "$RC_H" -eq 0 ] && ok "(h) uninstall(마커 없음) exit 0" || bad "(h) uninstall exit 코드" "rc=$RC_H"
has "(h) uninstall: 등록된 항목 없음 안내" "등록된 crontab 항목이 없습니다" "$OUT_H"
hasnt "(h) uninstall: 가짜 crontab 에 쓰기 시도 없음(실제 crontab 미접촉 확인용)" "unexpected write attempt" "$OUT_H"

# ── (i) JOBSTACK_CRON_OS_NAME=Darwin: install --dry-run 이 launchd plist 를 출력하고
#        & 가 든 상태 디렉토리 경로가 &amp; 로 이스케이프되는지 ────────────────────
STATE_AMP="$WORK/cron&state"
mkdir -p "$STATE_AMP"
OUT_I=$(JOBSTACK_STATE_DIR="$STATE_AMP" JOBSTACK_CRON_OS_NAME=Darwin "$CRON" install --time 08:15 --dry-run 2>&1); RC_I=$?
[ "$RC_I" -eq 0 ] && ok "(i) Darwin install --dry-run exit 0" || bad "(i) Darwin install --dry-run exit 코드" "rc=$RC_I"
has "(i) Darwin install --dry-run: launchd job 안내 출력" "launchd job" "$OUT_I"
has "(i) Darwin install --dry-run: plist XML 마커 출력" "<key>Label</key>" "$OUT_I"
has "(i) Darwin install --dry-run: plist 에 EnvironmentVariables PATH" "<key>PATH</key>" "$OUT_I"
has "(i) Darwin install --dry-run: & 가 든 경로가 &amp; 로 이스케이프됨" "cron&amp;state" "$OUT_I"
hasnt "(i) Darwin install --dry-run: 이스케이프 안 된 날 & 경로는 남지 않음" "cron&state" "$OUT_I"

# ── (j) % 가 든 상태 디렉토리 경로 → Linux install --dry-run 도 exit 1 로 거부 ──────
STATE_PCT="$WORK/state%pct"
mkdir -p "$STATE_PCT"
OUT_J=$(JOBSTACK_STATE_DIR="$STATE_PCT" JOBSTACK_CRON_OS_NAME=Linux "$CRON" install --time 09:00 --dry-run 2>&1); RC_J=$?
[ "$RC_J" -eq 1 ] && ok "(j) % 경로 Linux install --dry-run exit 1" || bad "(j) % 경로 install exit 코드" "rc=$RC_J"
has "(j) % 경로 거부 안내 메시지" "crontab 에 등록할 수 없습니다" "$OUT_J"

# ── (k) --time 형식 오류(25:99) → exit 1 ──────────────────────────────────
STATE_K="$WORK/state-k"
OUT_K=$(JOBSTACK_STATE_DIR="$STATE_K" JOBSTACK_CRON_OS_NAME=Linux "$CRON" install --time 25:99 --dry-run 2>&1); RC_K=$?
[ "$RC_K" -eq 1 ] && ok "(k) --time 25:99 형식 오류 exit 1" || bad "(k) --time 25:99 exit 코드" "rc=$RC_K"
has "(k) --time 형식 오류 안내 메시지" "HH:MM" "$OUT_K"

# ── (l) PII 불변식: analytics/cron.log 에 검색 조건(직무·경력·지역) 평문이 남지 않음 ──
# (a) 블록에서 --keyword 백엔드 --career entry --location seoul 로 이미 두 번 실행했다 —
# 그 실행이 남긴 cron.log 를 재검사한다(새로 실행하지 않음, 로그는 메타만 남겨야 한다).
CRONLOG_A="$STATE_A/analytics/cron.log"
if [ -f "$CRONLOG_A" ]; then
  ok "(l) cron.log 존재"
  CL_CONTENT="$(cat "$CRONLOG_A")"
  hasnt "(l) cron.log 에 검색 직무(키워드) 평문 없음" "백엔드" "$CL_CONTENT"
  hasnt "(l) cron.log 에 경력 조건(entry) 평문 없음" "entry" "$CL_CONTENT"
  hasnt "(l) cron.log 에 지역 조건(seoul) 평문 없음" "seoul" "$CL_CONTENT"
else
  bad "(l) cron.log 존재" "$CRONLOG_A 없음"
fi

# ── (m) node 부재 → "새 공고 0건" 이 아니라 exit 1 + 안내(PR #17 리뷰 반영) ──────────
STATE_M="$WORK/state-m"
OUT_M=$(JOBSTACK_STATE_DIR="$STATE_M" JOBSTACK_NODE_BIN=/nonexistent/node-bin JOBSTACK_TRACKER_BIN="$TRACKER_BIN" \
  "$CRON" run --keyword 노드없음 2>&1); RC_M=$?
[ "$RC_M" -eq 1 ] && ok "(m) node 부재 → exit 1" || bad "(m) node 부재 exit 코드" "rc=$RC_M out=$OUT_M"
has "(m) node 부재 안내 메시지" "node 를 찾을 수 없습니다" "$OUT_M"
hasnt "(m) node 부재 시 성공 문구 없음" "채용 모니터링 완료" "$OUT_M"

# ── (n) 전 플랫폼 수집 실패 → exit 2(degraded), daily 파일 없음, cron.log 에 degraded ──
STATE_N="$WORK/state-n"
DAILY_N="$STATE_N/job-cache/daily-$TODAY.md"
OUT_N=$(JOBSTACK_STATE_DIR="$STATE_N" JOBSTACK_FETCH_JOBS="$FAKE" FAKE_FAIL_ALL=1 JOBSTACK_TRACKER_BIN="$TRACKER_BIN" \
  "$CRON" run --keyword 전부실패 2>&1); RC_N=$?
[ "$RC_N" -eq 2 ] && ok "(n) 전 플랫폼 실패 → exit 2" || bad "(n) 전 플랫폼 실패 exit 코드" "rc=$RC_N out=$OUT_N"
has "(n) 전 플랫폼 실패 안내" "전 플랫폼" "$OUT_N"
hasnt "(n) 전 플랫폼 실패 시 성공 문구 없음" "채용 모니터링 완료" "$OUT_N"
[ ! -f "$DAILY_N" ] && ok "(n) 전 플랫폼 실패 시 daily 파일 미생성" || bad "(n) daily 파일" "$DAILY_N 생성됨"
grep -q '"status":"degraded"' "$STATE_N/analytics/cron.log" 2>/dev/null && ok "(n) cron.log 에 degraded 기록" || bad "(n) cron.log degraded" "$(cat "$STATE_N/analytics/cron.log" 2>/dev/null)"

# ── (o) --limit 검증: 0·문자 → exit 1 ──────────────────────────────────────────
for BAD_LIMIT in 0 abc 101; do
  OUT_O=$(JOBSTACK_STATE_DIR="$WORK/state-o" JOBSTACK_FETCH_JOBS="$FAKE" JOBSTACK_TRACKER_BIN="$TRACKER_BIN" \
    "$CRON" run --keyword 한도 --limit "$BAD_LIMIT" 2>&1); RC_O=$?
  [ "$RC_O" -eq 1 ] && has "(o) --limit $BAD_LIMIT → exit 1 + 안내" "1~100" "$OUT_O" || bad "(o) --limit $BAD_LIMIT exit 코드" "rc=$RC_O out=$OUT_O"
done

rm -rf "$WORK"

echo ""
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] jobstack-cron"; exit 0; } || { echo "[FAIL] jobstack-cron"; exit 1; }
