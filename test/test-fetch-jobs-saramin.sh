#!/usr/bin/env bash
# test-fetch-jobs-saramin.sh — fetch-jobs.mjs 사람인 --source=api|scrape|auto 통합 회귀
# (U-12 ②③ — 사람인 오픈API/스크래핑 이관, Chromium lazy 기동).
#
# 실제 네트워크·Chromium 을 타지 않는다:
#   - 스크래핑 경로는 JOBSTACK_SARAMIN_HTML_FIXTURE(테스트 훅, fetch-jobs.mjs 주석 참조)로
#     고정 HTML을 주입한다.
#   - 오픈API 경로는 JOBSTACK_SARAMIN_API_FIXTURE(테스트 훅)로 고정 JSON을 주입한다 —
#     이 JSON은 사람인과 무관한 합성 데이터이며 매 실행 시 mktemp로 생성해 커밋되지 않는다.
#   - PLAYWRIGHT_BROWSERS_PATH=/nonexistent 로 Chromium 바이너리 부재 상황을 강제한다.
#     사람인 경로는 이 상황에서도 성공해야 한다(어떤 --source 값이든 브라우저를 기동하지
#     않는다는 요구사항의 직접 증거).
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
FETCH_JOBS="$REPO/bin/fetch-jobs.mjs"
HTML_FIXTURE="$HERE/sample-data/saramin-search.html"

PASS=0
FAIL=0

log() { # $1=PASS|FAIL $2=이름 $3=상세(FAIL 시)
  if [ "$1" = "PASS" ]; then
    PASS=$((PASS + 1))
    echo "  [PASS] $2"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $2: ${3:-}"
  fi
}

# jobstack-config 가 실제 사용자 설정을 읽지 않도록 격리된 상태 디렉터리를 쓴다.
STATE_DIR=$(mktemp -d)
API_FIXTURE=$(mktemp)
OUT=$(mktemp)
ERR=$(mktemp)
ISOLATED=$(mktemp -d)
cleanup() { rm -rf "$STATE_DIR" "$API_FIXTURE" "$OUT" "$ERR" "$ISOLATED"; }
trap cleanup EXIT

if [ ! -f "$HTML_FIXTURE" ]; then
  log "FAIL" "HTML 픽스처 존재" "$HTML_FIXTURE 없음 — test-saramin-parser.mjs 픽스처 확인"
  echo ""
  
echo "PASS: $PASS / FAIL: $FAIL"
  exit 1
fi

# fetchSaraminApi(bin/sources/saramin-api.mjs) 응답 형태에 맞춘 가상 3건 — 실명·실제
# 채용정보 없음. company.detail.name/position.title/position.job-code.name/url/
# expiration-timestamp(epoch초) 필드 매핑을 검증한다.
cat > "$API_FIXTURE" <<'JSON'
{
  "jobs": {
    "count": "3",
    "job": [
      {
        "url": "http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=91000001",
        "company": { "detail": { "name": "가짜테크(주)" } },
        "position": { "title": "백엔드 개발자 채용(API 가상1)", "job-code": { "name": "백엔드 개발자" } },
        "expiration-timestamp": 1893456000
      },
      {
        "url": "http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=91000002",
        "company": { "detail": { "name": "모의상사(유)" } },
        "position": { "title": "서버 개발자 채용(API 가상2)", "job-code": { "name": "서버 개발자" } },
        "expiration-timestamp": 1893456000
      },
      {
        "url": "http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=91000003",
        "company": { "detail": { "name": "테스트랩스(주)" } },
        "position": { "title": "QA 엔지니어 채용(API 가상3)", "job-code": { "name": "QA 엔지니어" } }
      }
    ]
  }
}
JSON

# $1=json 파일 $2=node 식(파싱 결과가 d로 바인딩됨, boolean 반환) → "true"/"false"/"PARSE_ERROR"/"EVAL_ERROR:..."
json_check() {
  node -e '
    const fs = require("fs");
    let d;
    try { d = JSON.parse(fs.readFileSync(process.argv[1], "utf8")); }
    catch (e) { console.log("PARSE_ERROR:" + e.message); process.exit(0); }
    try { console.log(!!(eval(process.argv[2]))); }
    catch (e) { console.log("EVAL_ERROR:" + e.message); }
  ' "$1" "$2"
}

no_chromium_launched() { # $1=stderr 파일 — 브라우저 기동 흔적이 없으면 성공(0)
  ! grep -qiE 'browserType\.launch|chromium|playwright|chrome-headless' "$1"
}

# ── (a) --source=scrape + HTML 픽스처 → 5건, fetch_via= 진단, Chromium 미기동 ──────
JOBSTACK_STATE_DIR="$STATE_DIR" \
JOBSTACK_SARAMIN_HTML_FIXTURE="$HTML_FIXTURE" \
PLAYWRIGHT_BROWSERS_PATH=/nonexistent \
node "$FETCH_JOBS" saramin 백엔드 5 --source=scrape >"$OUT" 2>"$ERR"
RC=$?

[ "$RC" -eq 0 ] && log "PASS" "(a) scrape: exit 0" || log "FAIL" "(a) scrape: exit 0" "실제 exit=$RC, stderr: $(cat "$ERR")"
[ "$(json_check "$OUT" 'Array.isArray(d) && d.length === 5')" = "true" ] \
  && log "PASS" "(a) scrape: JSON 배열 5건" \
  || log "FAIL" "(a) scrape: JSON 배열 5건" "$(cat "$OUT")"
[ "$(json_check "$OUT" "d.every(j => j.platform === 'saramin' && j.title && j.company)")" = "true" ] \
  && log "PASS" "(a) scrape: 전 항목 platform=saramin·title/company 존재" \
  || log "FAIL" "(a) scrape: 전 항목 platform=saramin·title/company 존재" "$(cat "$OUT")"
grep -q 'fetch_via=' "$ERR" \
  && log "PASS" "(a) scrape: stderr fetch_via= 진단" \
  || log "FAIL" "(a) scrape: stderr fetch_via= 진단" "$(cat "$ERR")"
no_chromium_launched "$ERR" \
  && log "PASS" "(a) scrape: Chromium 미기동(브라우저 부재 환경에서도 성공)" \
  || log "FAIL" "(a) scrape: Chromium 미기동" "브라우저 기동 흔적 발견: $(cat "$ERR")"

# ── (b) --source=api + API 픽스처(키 없음) → 3건 매핑 ──────────────────────────────
: > "$OUT"; : > "$ERR"
JOBSTACK_STATE_DIR="$STATE_DIR" \
JOBSTACK_SARAMIN_API_FIXTURE="$API_FIXTURE" \
PLAYWRIGHT_BROWSERS_PATH=/nonexistent \
node "$FETCH_JOBS" saramin 백엔드 5 --source=api >"$OUT" 2>"$ERR"
RC=$?

[ "$RC" -eq 0 ] && log "PASS" "(b) api: exit 0(키 없어도 픽스처로 실행)" || log "FAIL" "(b) api: exit 0" "실제 exit=$RC, stderr: $(cat "$ERR")"
[ "$(json_check "$OUT" 'Array.isArray(d) && d.length === 3')" = "true" ] \
  && log "PASS" "(b) api: JSON 배열 3건 매핑" \
  || log "FAIL" "(b) api: JSON 배열 3건 매핑" "$(cat "$OUT")"
[ "$(json_check "$OUT" "d.every(j => j.platform === 'saramin') && d.some(j => j.company === '가짜테크(주)' && j.title.includes('API 가상1'))")" = "true" ] \
  && log "PASS" "(b) api: company/title 필드 매핑 확인" \
  || log "FAIL" "(b) api: company/title 필드 매핑 확인" "$(cat "$OUT")"
no_chromium_launched "$ERR" \
  && log "PASS" "(b) api: Chromium 미기동" \
  || log "FAIL" "(b) api: Chromium 미기동" "브라우저 기동 흔적 발견: $(cat "$ERR")"
grep -q 'fetch_via=api' "$ERR" \
  && log "PASS" "(b) api: stderr fetch_via=api 진단" \
  || log "FAIL" "(b) api: stderr fetch_via=api 진단" "$(cat "$ERR")"

# ── (c) --source=auto + 키 없음 + HTML 픽스처(API 픽스처 없음) → 스크래핑 폴백 ────────
: > "$OUT"; : > "$ERR"
JOBSTACK_STATE_DIR="$STATE_DIR" \
JOBSTACK_SARAMIN_HTML_FIXTURE="$HTML_FIXTURE" \
PLAYWRIGHT_BROWSERS_PATH=/nonexistent \
node "$FETCH_JOBS" saramin 백엔드 5 --source=auto >"$OUT" 2>"$ERR"
RC=$?

[ "$RC" -eq 0 ] && log "PASS" "(c) auto: exit 0" || log "FAIL" "(c) auto: exit 0" "실제 exit=$RC, stderr: $(cat "$ERR")"
[ "$(json_check "$OUT" 'Array.isArray(d) && d.length === 5')" = "true" ] \
  && log "PASS" "(c) auto: API 미가용 → 스크래핑 폴백 5건" \
  || log "FAIL" "(c) auto: API 미가용 → 스크래핑 폴백 5건" "$(cat "$OUT")"
grep -q 'fetch_via=api cause=no_key' "$ERR" \
  && log "PASS" "(c) auto: 키 없음 진단(cause=no_key)" \
  || log "FAIL" "(c) auto: 키 없음 진단(cause=no_key)" "$(cat "$ERR")"
grep -q 'fallback=scrape' "$ERR" \
  && log "PASS" "(c) auto: 스크래핑 폴백 진단(fallback=scrape)" \
  || log "FAIL" "(c) auto: 스크래핑 폴백 진단(fallback=scrape)" "$(cat "$ERR")"
no_chromium_launched "$ERR" \
  && log "PASS" "(c) auto: Chromium 미기동" \
  || log "FAIL" "(c) auto: Chromium 미기동" "브라우저 기동 흔적 발견: $(cat "$ERR")"

# ── (d) 잘못된 --source=x → exit 1, JSON 미출력 ───────────────────────────────────
: > "$OUT"; : > "$ERR"
JOBSTACK_STATE_DIR="$STATE_DIR" \
node "$FETCH_JOBS" saramin 백엔드 5 --source=x >"$OUT" 2>"$ERR"
RC=$?

[ "$RC" -eq 1 ] && log "PASS" "(d) 잘못된 --source=x → exit 1" || log "FAIL" "(d) 잘못된 --source=x → exit 1" "실제 exit=$RC"
grep -qi 'source' "$ERR" \
  && log "PASS" "(d) stderr 에 --source 관련 오류 메시지" \
  || log "FAIL" "(d) stderr 에 --source 관련 오류 메시지" "$(cat "$ERR")"
[ ! -s "$OUT" ] \
  && log "PASS" "(d) stdout 미출력(JSON 없음)" \
  || log "FAIL" "(d) stdout 미출력(JSON 없음)" "$(cat "$OUT")"

# ── (e) cheerio 없는 격리 환경에서 jumpit 호출 → saramin.mjs 정적 import 만으로는 안 죽음 ──
# fetch-jobs.mjs 가 bin/parsers/saramin.mjs 를 최상위에서 정적 import 한다. cheerio 로드가
# lazy(호출 시점)가 아니라 모듈 로드 시점(top-level require)이면, saramin 이 아닌 플랫폼을
# 호출해도 cheerio 미설치 환경에서 모듈 로드 단계에서 크래시한다(리뷰 반영 회귀 포인트).
# node_modules 를 실제로 비운 격리 디렉터리를 만들어 검증한다(cwd 조작이 아니라 ESM 모듈
# 해석이 실제로 참조하는 파일 트리 자체를 옮겨야 한다 — cwd 는 bare specifier 해석에 영향 없음).
mkdir -p "$ISOLATED/bin/parsers" "$ISOLATED/bin/sources" "$ISOLATED/bin/node_modules"
cp "$REPO/bin/fetch-jobs.mjs" "$REPO/bin/fetch-diag.mjs" "$REPO/bin/wanted-verify.mjs" \
   "$REPO/bin/is-fetch-adapter.mjs" "$ISOLATED/bin/"
cp "$REPO/bin/parsers/saramin.mjs" "$ISOLATED/bin/parsers/"
cp "$REPO/bin/sources/saramin-api.mjs" "$ISOLATED/bin/sources/"
# playwright 만 심링크 — cheerio 는 이 트리 어디에도 없다(node_modules 통째로 복사 안 함).
ln -s "$REPO/bin/node_modules/playwright" "$ISOLATED/bin/node_modules/playwright"

: > "$OUT"; : > "$ERR"
PLAYWRIGHT_BROWSERS_PATH=/nonexistent \
node "$ISOLATED/bin/fetch-jobs.mjs" jumpit x >"$OUT" 2>"$ERR"
RC=$?

[ "$RC" -eq 0 ] && log "PASS" "(e) cheerio 없는 환경 + jumpit: exit 0" || log "FAIL" "(e) cheerio 없는 환경 + jumpit: exit 0" "실제 exit=$RC, stderr: $(cat "$ERR")"
[ "$(json_check "$OUT" 'Array.isArray(d) && d.length === 0')" = "true" ] \
  && log "PASS" "(e) cheerio 없는 환경 + jumpit: 빈 배열([])" \
  || log "FAIL" "(e) cheerio 없는 환경 + jumpit: 빈 배열([])" "$(cat "$OUT")"
! grep -qi 'cheerio' "$ERR" \
  && log "PASS" "(e) cheerio 없는 환경 + jumpit: cheerio 관련 크래시 없음(모듈 로드가 죽지 않음)" \
  || log "FAIL" "(e) cheerio 없는 환경 + jumpit: cheerio 관련 크래시 없음" "$(cat "$ERR")"

# ── limit 검증(PR #17 리뷰 반영): 1~100 정수만 허용, 그 외는 네트워크 접근 전에 exit 1 ──
for bad_limit in 0 -5 1e+21 101 007x; do
JOBSTACK_STATE_DIR="$STATE_DIR" node "$FETCH_JOBS" saramin 백엔드 "$bad_limit" >"$OUT" 2>"$ERR"; rc=$?
if [ "$rc" -eq 1 ] && grep -q '1~100' "$ERR"; then
  log "PASS" "limit=$bad_limit → exit 1 + 사용법 오류"
else
  log "FAIL" "limit=$bad_limit 검증" "rc=$rc $(cat "$ERR")"
fi
done

echo ""
echo "════════════════════════════════════════"
echo "  test-fetch-jobs-saramin: PASS=$PASS FAIL=$FAIL"
echo "════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
