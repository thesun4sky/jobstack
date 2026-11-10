#!/usr/bin/env bash
# bin/jobstack-netpay 결정적 동작 테스트 — 법정 공제·최저임금 계산(가드레일 §3 예외).
#
# 법정 값은 bin/data/statutory-<연도>.json 에만 있고, 데이터가 없는 시점은 계산을 거부해야 한다.
# 계산 단언은 픽스처 데이터(JOBSTACK_STATUTORY_DIR)로 돌려 실제 요율이 바뀌어도 깨지지 않게 한다.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
N="$REPO/bin/jobstack-netpay"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }
jq_eq() { # jq_eq NAME JSON PYEXPR
  python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert $3, d" "$2" 2>/dev/null && ok "$1" || bad "$1" "$2"; }

WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
echo "## jobstack-netpay"

python3 -m py_compile "$N" >/dev/null 2>&1 && ok "python3 -m py_compile 통과" || bad "python3 -m py_compile 통과"
[ -x "$N" ] && ok "실행 권한(chmod +x)" || bad "실행 권한(chmod +x)"

# ── 저장소 데이터 파일 형식 — 모든 값에 출처·확인일이 있어야 한다 ─────────
for f in "$REPO"/bin/data/statutory-*.json; do
  python3 - "$f" <<'PY' 2>/dev/null && ok "$(basename "$f") 스키마(year·verified_at·source·url)" || bad "$(basename "$f") 스키마"
import json, re, sys, os
d = json.load(open(sys.argv[1], encoding='utf-8'))
assert str(d['year']) == re.search(r'statutory-(\d{4})\.json', os.path.basename(sys.argv[1])).group(1)
assert re.fullmatch(r'\d{4}-\d{2}-\d{2}', d['verified_at'])
for k in ('min_wage', 'pension', 'health', 'long_term_care', 'employment'):
    assert k in d
    v = d[k]
    if v is None: continue
    assert v['source'] and v['url'].startswith('https://')
for p in (d['pension'] or {}).get('base_income', []):
    assert p['from'] <= p['to'] and p['floor'] < p['ceiling'] and p['source']
PY
done

# ── 픽스처 데이터로 계산 단언 ─────────────────────────────────────────────
export JOBSTACK_STATUTORY_DIR="$WORK/data"; mkdir -p "$JOBSTACK_STATUTORY_DIR"
cat > "$JOBSTACK_STATUTORY_DIR/statutory-2030.json" <<'JSON'
{"year": 2030, "verified_at": "2030-01-02",
 "min_wage": {"hourly": 10000, "monthly_hours": 209, "source": "픽스처 최저임금", "url": "https://example.invalid/mw"},
 "pension": {"employee_rate": 0.05, "source": "픽스처 연금", "url": "https://example.invalid/p",
   "base_income": [{"from": "2030-01", "to": "2030-06", "floor": 400000, "ceiling": 6000000, "source": "픽스처 상하한", "url": "https://example.invalid/b"}]},
 "health": {"employee_rate": 0.035, "source": "픽스처 건보", "url": "https://example.invalid/h"},
 "long_term_care": {"employee_rate_of_income": 0.0045, "source": "픽스처 장기요양", "url": "https://example.invalid/l"},
 "employment": {"employee_rate": 0.009, "source": "픽스처 고용", "url": "https://example.invalid/e"}}
JSON
cat > "$JOBSTACK_STATUTORY_DIR/statutory-2031.json" <<'JSON'
{"year": 2031, "verified_at": "2030-12-01",
 "min_wage": {"hourly": 10500, "monthly_hours": 209, "source": "픽스처 최저임금 2031", "url": "https://example.invalid/mw"},
 "pension": null, "health": null, "long_term_care": null, "employment": null}
JSON

J=$("$N" calc --annual 42000000 --date 2030-03 --json 2>&1); RC=$?
[ $RC -eq 0 ] && ok "calc exit 0" || bad "calc exit 0" "rc=$RC $J"
jq_eq "월 급여 = 연봉 ÷ 12" "$J" "d['monthly_gross'] == 3500000"
jq_eq "국민연금 175,000" "$J" "d['deductions']['pension'] == 175000"
jq_eq "건강보험 122,500" "$J" "d['deductions']['health'] == 122500"
jq_eq "장기요양 15,750" "$J" "d['deductions']['long_term_care'] == 15750"
jq_eq "고용보험 31,500 (부동소수점 오차 없음)" "$J" "d['deductions']['employment'] == 31500"
jq_eq "합계·공제 후" "$J" "d['insurance_total'] == 344750 and d['after_insurance'] == 3155250"
jq_eq "소득세 미입력이면 net 은 null" "$J" "d['net'] is None and d['income_tax'] is None"
jq_eq "출처·확인일 포함" "$J" "d['verified_at'] == '2030-01-02' and len(d['sources']) == 5"

J=$("$N" calc --monthly 9000000 --date 2030-03 --json 2>&1)
jq_eq "기준소득월액 상한 적용" "$J" "d['pension_base'] == 6000000 and d['deductions']['pension'] == 300000"
J=$("$N" calc --monthly 300000 --date 2030-03 --json 2>&1)
jq_eq "기준소득월액 하한 적용" "$J" "d['pension_base'] == 400000 and d['deductions']['pension'] == 20000"
J=$("$N" calc --monthly 3123456 --date 2030-03 --json 2>&1)
jq_eq "기준소득월액 천원 미만 버림 · 10원 미만 버림" "$J" "d['pension_base'] == 3123000 and d['deductions']['pension'] == 156150 and d['deductions']['health'] == 109320"
J=$("$N" calc --monthly 3700000 --nontaxable 200000 --income-tax 100000 --date 2030-03 --json 2>&1)
jq_eq "비과세 제외 후 보험료 산정" "$J" "d['insurance_base'] == 3500000 and d['insurance_total'] == 344750"
jq_eq "소득세 입력 시 지방소득세 10%·실수령" "$J" "d['local_income_tax'] == 10000 and d['net'] == 3700000 - 344750 - 110000"

OUT=$("$N" calc --annual 42000000 --date 2030-03 2>&1)
has "표 출력에 미계산 안내" "간이세액표" "$OUT"
has "표 출력에 출처" "픽스처 연금" "$OUT"
has "표 출력에 한계 고지" "실제 고지액과 차이" "$OUT"

# ── 데이터 없는 시점은 계산 거부(exit 2) ─────────────────────────────────
OUT=$("$N" calc --annual 42000000 --date 2030-09 2>&1); RC=$?
[ $RC -eq 2 ] && ok "기준소득월액 기간 밖 exit 2" || bad "기준소득월액 기간 밖 exit 2" "rc=$RC $OUT"
OUT=$("$N" calc --annual 42000000 --date 2031-02 2>&1); RC=$?
[ $RC -eq 2 ] && ok "null 항목 연도 exit 2" || bad "null 항목 연도 exit 2" "rc=$RC $OUT"
has "null 항목 이름 안내" "health" "$OUT"
OUT=$("$N" calc --annual 42000000 --date 2040-01 2>&1); RC=$?
[ $RC -eq 2 ] && ok "데이터 파일 없는 연도 exit 2" || bad "데이터 파일 없는 연도 exit 2" "rc=$RC"
has "파일 없는 연도 안내" "공식 출처" "$OUT"
echo '{"year": 2032}' > "$JOBSTACK_STATUTORY_DIR/statutory-2032.json"
OUT=$("$N" calc --annual 42000000 --date 2032-01 2>&1); RC=$?
[ $RC -eq 2 ] && ok "verified_at 없는 데이터 거부" || bad "verified_at 없는 데이터 거부" "rc=$RC"

# ── 최저임금 ─────────────────────────────────────────────────────────────
OUT=$("$N" minwage --monthly 2090000 --date 2030-01 2>&1); RC=$?
[ $RC -eq 0 ] && ok "minwage 경계값(정확히 최저) exit 0" || bad "minwage 경계값 exit 0" "rc=$RC $OUT"
OUT=$("$N" minwage --monthly 2089999 --date 2030-01 2>&1); RC=$?
[ $RC -eq 3 ] && ok "minwage 미달 exit 3" || bad "minwage 미달 exit 3" "rc=$RC"
has "minwage 미달 문구" "최저임금 미달" "$OUT"
J=$("$N" minwage --hourly 10500 --date 2031-05 --json 2>&1); RC=$?
[ $RC -eq 0 ] && ok "minwage 는 보험 항목이 null 인 연도에도 동작" || bad "minwage null 연도" "rc=$RC $J"
jq_eq "minwage --json 필드" "$J" "d['min_hourly'] == 10500 and d['min_monthly'] == 2194500 and d['below_minimum'] is False"
J=$("$N" minwage --monthly 1000000 --hours 100 --date 2030-01 --json 2>&1); RC=$?
[ $RC -eq 0 ] && ok "minwage --hours 반영" || bad "minwage --hours 반영" "rc=$RC $J"

# ── 입력 오류(exit 1) ────────────────────────────────────────────────────
for args in "calc --annual 0 --date 2030-03" "calc --monthly -5 --date 2030-03" "calc --annual 42000000 --date 2030-13" \
            "calc --annual 42000000 --date 203003" "calc --monthly 100000 --nontaxable 100000 --date 2030-03" \
            "minwage --hourly 0 --date 2030-01"; do
  # shellcheck disable=SC2086
  "$N" $args >/dev/null 2>&1; RC=$?
  [ $RC -eq 1 ] && ok "입력 오류 exit 1: $args" || bad "입력 오류 exit 1: $args" "rc=$RC"
done
"$N" calc --annual 1 --monthly 1 >/dev/null 2>&1; [ $? -eq 2 ] && ok "--annual·--monthly 동시 지정 거부" || bad "--annual·--monthly 동시 지정 거부"
"$N" >/dev/null 2>&1; [ $? -eq 1 ] && ok "하위 명령 없음 exit 1" || bad "하위 명령 없음 exit 1"

# ── sources ──────────────────────────────────────────────────────────────
OUT=$("$N" sources --date 2031-01 2>&1)
has "sources 미확정 표기" "미확정" "$OUT"
has "sources 출처" "픽스처 최저임금 2031" "$OUT"

# ── 저장소 실데이터 스모크(값 단언 없음 — 요율 갱신에 깨지지 않게) ────────
unset JOBSTACK_STATUTORY_DIR
OUT=$("$N" sources --date 2026-11 2>&1); RC=$?
[ $RC -eq 0 ] && ok "실데이터 sources 2026 exit 0" || bad "실데이터 sources 2026" "rc=$RC $OUT"
J=$("$N" calc --annual 36000000 --date 2026-11 --json 2>&1); RC=$?
[ $RC -eq 0 ] && ok "실데이터 calc 2026-11 exit 0" || bad "실데이터 calc 2026-11" "rc=$RC $J"
jq_eq "실데이터 합계 = 항목 합" "$J" "sum(d['deductions'].values()) == d['insurance_total'] and 0 < d['insurance_total'] < d['monthly_gross']"

echo "결과: $PASS 통과, $FAIL 실패"
[ $FAIL -eq 0 ]
