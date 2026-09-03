#!/usr/bin/env bash
# bin/jobstack-tracker 결정적 동작 테스트 (docs/tracker-states.md 규칙).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
T="$REPO/bin/jobstack-tracker"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }       # has NAME PATTERN TEXT
hasnt() { grep -q -- "$2" <<<"$3" && bad "$1" "$3" || ok "$1"; }

WORK=$(mktemp -d)
export JOBSTACK_STATE_DIR="$WORK/state"
F="$JOBSTACK_STATE_DIR/tracker/applications.jsonl"
rec() { python3 -c "import json,sys; rows=[json.loads(l) for l in open(sys.argv[1],encoding='utf-8')]; r=[x for x in rows if x['id']==sys.argv[2]][0]; print(r.get(sys.argv[3]))" "$F" "$1" "$2"; }

echo "## jobstack-tracker"
OUT=$("$T" add --company 삼성전자 --position SW엔지니어 --status 준비중 --deadline 2099-04-15 --notes "자소서 3번" 2>&1)
has "add 준비중" "추가됨: app-001" "$OUT"
"$T" add --company 카카오 --position 서버개발자 --status applied --json >/dev/null
has "add 영문 키 저장" '"status":"applied"' "$(cat "$F")"
has "schema_version 2" '"schema_version":2' "$(cat "$F")"

"$T" update app-002 --status 1차면접 >/dev/null
[ "$(rec app-002 max_stage)" = interview_1 ] && ok "update 1차면접 max_stage" || bad "update max_stage" "$(rec app-002 max_stage)"
OUT=$("$T" update app-002 --status document_pass 2>&1)
has "서류합격 추천 힌트" "mock_interview" "$OUT"
[ "$(rec app-002 max_stage)" = interview_1 ] && ok "낮은 단계로 갱신해도 max_stage 유지" || bad "max_stage 유지" "$(rec app-002 max_stage)"
"$T" update app-002 --status interview_2 >/dev/null
OUT=$("$T" update app-002 --status rejected 2>&1)
[ "$(rec app-002 status)" = rejected ] && [ "$(rec app-002 max_stage)" = interview_2 ] && ok "rejected 후 max_stage 보존" || bad "rejected max_stage" "$(rec app-002 max_stage)"
has "rejected 시 retro 추천" "/retro" "$OUT"

OUT=$("$T" update 삼성 --status applied 2>&1)
has "회사명 부분일치 갱신" "갱신됨: app-001" "$OUT"
"$T" add --company 삼성SDS --position 개발 >/dev/null
OUT=$("$T" update 삼성 --status applied 2>&1); RC=$?
[ $RC -eq 1 ] && has "모호한 회사명은 오류" "부분일치" "$OUT" || bad "모호한 회사명 exit 1" "rc=$RC"

OUT=$("$T" list 2>&1)
has "list 대기중 그룹" "⏳ 대기중" "$OUT"
has "list 종료 그룹" "❌ 종료" "$OUT"
has "list 한글 라벨" "지원완료" "$OUT"
hasnt "list 에 영문 키 노출 없음" "applied" "$OUT"
has "list 기준일 KST" "기준일: 20" "$OUT"
has "list D-day" "D-" "$OUT"
OUT=$("$T" calendar 2>&1)
has "calendar 다가오는 마감" "삼성전자" "$OUT"

"$T" add --company 네이버 --position 백엔드 --status applied >/dev/null
"$T" update 네이버 --status withdrawn >/dev/null
OUT=$("$T" stats --json 2>&1)
python3 -c "import json,sys; f=json.loads(sys.argv[1])['funnel']; assert f['applied_plus']==2 and f['document_pass_plus']==1, f" "$OUT" 2>/dev/null \
  && ok "stats funnel (withdrawn 분모 제외)" || bad "stats funnel" "$OUT"
has "stats 분포" "지원취소:       1건" "$("$T" stats)"

python3 - "$F" <<'PY'
import json,sys,datetime
p=sys.argv[1]; rows=[json.loads(l) for l in open(p,encoding='utf-8')]
old=(datetime.date.today()-datetime.timedelta(days=10)).isoformat()
for r in rows:
    if r['id']=='app-001': r['updated_at']=old
open(p,'w',encoding='utf-8').write('\n'.join(json.dumps(r,ensure_ascii=False) for r in rows)+'\n')
PY
OUT=$("$T" nudge 2>&1)
has "nudge 정체 감지" "삼성전자" "$OUT"
has "nudge 일수 표기" "일째" "$OUT"
hasnt "종결 항목은 nudge 제외" "카카오" "$OUT"
"$T" nudge --mark >/dev/null
has "nudge --mark 후 재출력 억제" "정체 항목 없음" "$("$T" nudge 2>&1)"
has "validate 통과" "PASS" "$("$T" validate 2>&1)"

# v1 골든 입력 — 읽기 정규화 / 마이그레이션
rm -rf "$JOBSTACK_STATE_DIR"; mkdir -p "$JOBSTACK_STATE_DIR/tracker"
cp "$REPO/test/golden/tracker/v1-compat/input.jsonl" "$F"
OUT=$("$T" list 2>&1)
has "v1 읽기 정규화 — 진행중 그룹" "진행중" "$OUT"
has "v1 읽기 정규화 — 서류전형→지원완료 표시" "지원완료" "$OUT"
has "v1 파일 미변경(읽기 전용)" "서류전형" "$(cat "$F")"
OUT=$("$T" migrate 2>&1)
has "migrate 승인 전 미리보기" "구버전 형식 5건" "$OUT"
has "migrate 미리보기는 파일 미변경" "서류전형" "$(cat "$F")"
"$T" migrate --yes >/dev/null
[ -f "$F.bak" ] && ok "migrate --yes 백업 생성" || bad "migrate 백업"
hasnt "migrate 후 한글 status 없음" "서류전형" "$(cat "$F")"
[ "$(rec app-005 max_stage)" = applied ] && [ "$(rec app-005 status)" = rejected ] && ok "migrate max_stage 폴백(불합격→applied)" || bad "migrate 폴백" "$(rec app-005 max_stage)"
has "migrate 후 validate" "PASS" "$("$T" validate 2>&1)"

echo '{"id":"app-009","company":"X","position":"Y","status":"면접대기","applied_at":"2026-01-01","deadline":"","updated_at":"2026-01-01","notes":""}' >> "$F"
has "알 수 없는 상태 list 표기" "(구버전 상태)" "$("$T" list 2>&1)"
"$T" validate >/dev/null 2>&1 && bad "알 수 없는 상태 validate 실패해야 함" || ok "알 수 없는 상태 validate 실패"

rm -rf "$WORK"
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] jobstack-tracker"; exit 0; } || { echo "[FAIL] jobstack-tracker"; exit 1; }
