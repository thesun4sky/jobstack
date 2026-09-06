#!/usr/bin/env bash
# bin/jobstack-retro-stats 결정적 동작 테스트 (U-09, retro/SKILL.md §Phase 5 프론트매터 형식).
#
# retro 스킬 Phase 3.3(누적 패턴 분석)이 Grep 으로 어림잡던 태그 집계·단계별 교차표·추세를
# 이 스크립트가 표준 라이브러리만으로 결정적으로 계산하는지 픽스처로 검증한다.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
R="$REPO/bin/jobstack-retro-stats"
FIX="$REPO/test/sample-data/retro"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }       # has NAME PATTERN TEXT
hasnt() { grep -q -- "$2" <<<"$3" && bad "$1" "$3" || ok "$1"; }

WORK=$(mktemp -d)
export JOBSTACK_STATE_DIR="$WORK/state"
D="$JOBSTACK_STATE_DIR/interview-history"
trap 'rm -rf "$WORK"' EXIT

echo "## jobstack-retro-stats"

python3 -m py_compile "$R" >/dev/null 2>&1 && ok "python3 -m py_compile 통과" || bad "python3 -m py_compile 통과"
[ -x "$R" ] && ok "실행 권한(chmod +x)" || bad "실행 권한(chmod +x)"

# ── 파일 0건 처리 — 디렉토리는 있지만 retro-*.md 없음 ────────────────────
mkdir -p "$D"
OUT=$("$R" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "0건(빈 디렉토리) exit 0" || bad "0건(빈 디렉토리) exit 0" "rc=$RC"
has "0건(빈 디렉토리) 안내 문구" "회고 파일 없음" "$OUT"
has "0건(빈 디렉토리) 건수 표기" "0건" "$OUT"
J=$("$R" --json 2>&1)
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d == {'count': 0, 'tag_counts': {}, 'stage_tag': {}, 'unknown_tags': {}, 'trend': None, 'retros': []}, d
" "$J" 2>/dev/null && ok "0건 --json 필드(count/trend 등 전부 공백)" || bad "0건 --json 필드" "$J"

# ── 파일 0건 처리 — interview-history 디렉토리 자체가 없음 ────────────────
rm -rf "$D"
OUT=$("$R" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "0건(디렉토리 부재) exit 0" || bad "0건(디렉토리 부재) exit 0" "rc=$RC"
has "0건(디렉토리 부재) 안내 문구" "회고 파일 없음" "$OUT"

# ── main 픽스처를 격리 상태 디렉토리의 올바른 위치에 배치 ────────────────
mkdir -p "$D"
cp "$FIX"/main/*.md "$D/"
PHYSICAL=$(ls "$D"/retro-*.md | wc -l | tr -d ' ')
[ "$PHYSICAL" = 5 ] && ok "픽스처 준비 — retro-*.md 물리 파일 5개(프론트매터 없는 1개 포함)" || bad "픽스처 준비" "physical=$PHYSICAL"

# ── 결정적 계산 — 동일 입력 두 번 → 동일 출력 (옵션 없이 기본 경로 사용) ──
OUT1=$("$R" 2>&1)
OUT2=$("$R" 2>&1)
[ "$OUT1" = "$OUT2" ] && ok "결정적 계산(텍스트) — 동일 입력 두 번 → 동일 출력" || bad "결정적 계산(텍스트)" "diff 있음"
J1=$("$R" --json 2>&1)
J2=$("$R" --json 2>&1)
[ "$J1" = "$J2" ] && ok "결정적 계산(JSON) — 동일 입력 두 번 → 동일 출력" || bad "결정적 계산(JSON)" "diff 있음"

OUT=$OUT1
# ── 기본 경로(JOBSTACK_STATE_DIR/interview-history) 자동 인식 + 프론트매터 없는 파일 제외 ──
has "기본 경로 자동 인식 + 프론트매터 없는 파일 제외(물리 5개 중 4건 집계)" "회고 누적 통계 — 4건" "$OUT"

# ── 태그 집계 ─────────────────────────────────────────────────────────
has "태그 집계 — 기업연구부족 2건" "기업연구부족.*2건" "$OUT"
has "태그 집계 — 꼬리질문대응 2건" "꼬리질문대응.*2건" "$OUT"
has "태그 집계 — 수치화부족 1건" "수치화부족.*1건" "$OUT"
has "태그 집계 — 컬처핏 1건" "컬처핏.*1건" "$OUT"
hasnt "고정 8태그만 있을 땐 '정리 필요' 라벨 없음" "정리 필요" "$OUT"

# ── 단계 × 태그 교차표 ────────────────────────────────────────────────
has "단계×태그 — 서류: 기업연구부족 1" "서류: 기업연구부족 1" "$OUT"
has "단계×태그 — 1차면접: 꼬리질문대응 2 포함" "1차면접:.*꼬리질문대응 2" "$OUT"
has "단계×태그 — 1차면접: 수치화부족 1 포함(블록 리스트 프론트매터 파싱)" "1차면접:.*수치화부족 1" "$OUT"
has "단계×태그 — 2차면접: 컬처핏 1" "2차면접: 컬처핏 1" "$OUT"

# ── 추세(trend) ───────────────────────────────────────────────────────
has "추세 — 최근 3건 평균 1.7개 vs 이전 평균 1.0개" "추세: 최근 3건 평균 약점 1.7개 vs 이전 평균 1.0개" "$OUT"

# ── 최근 회고 — 날짜 오름차순 정렬 ────────────────────────────────────
has "최근 회고 — 삼성전자(최초) 표시" "2026-06-01  삼성전자" "$OUT"
has "최근 회고 — 라인(최신) 표시" "2026-07-20  라인" "$OUT"
L1=$(grep -n "2026-06-01  삼성전자" <<<"$OUT" | head -1 | cut -d: -f1)
L2=$(grep -n "2026-07-20  라인" <<<"$OUT" | head -1 | cut -d: -f1)
if [ -n "$L1" ] && [ -n "$L2" ] && [ "$L1" -lt "$L2" ]; then
  ok "최근 회고 — 날짜 오름차순(삼성전자 → 라인 순)"
else
  bad "최근 회고 — 날짜 오름차순" "L1=$L1 L2=$L2"
fi

# ── 4건(≥3)이면 소표본 경고 없음 ──────────────────────────────────────
hasnt "4건일 땐 소표본 경고 없음" "3건 미만" "$OUT"

# ── JSON 필드 값 정밀 검증 ────────────────────────────────────────────
python3 -c "import json,sys; json.loads(sys.argv[1])" "$J1" 2>/dev/null \
  && ok "--json 출력이 유효한 JSON" || bad "--json 출력이 유효한 JSON" "$J1"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['count'] == 4, d['count']
assert d['tag_counts'] == {'기업연구부족': 2, '꼬리질문대응': 2, '수치화부족': 1, '컬처핏': 1}, d['tag_counts']
assert d['stage_tag']['서류'] == {'기업연구부족': 1}
assert d['stage_tag']['1차면접'] == {'꼬리질문대응': 2, '기업연구부족': 1, '수치화부족': 1}
assert d['stage_tag']['2차면접'] == {'컬처핏': 1}
assert d['unknown_tags'] == {}, d['unknown_tags']
assert d['trend'] == {'recent_avg_tags': 1.7, 'earlier_avg_tags': 1.0}, d['trend']
companies = [r['company'] for r in d['retros']]
assert companies == ['삼성전자', '카카오', '네이버', '라인'], companies
naver = [r for r in d['retros'] if r['company'] == '네이버'][0]
assert naver['weakness_tags'] == ['꼬리질문대응', '수치화부족'], naver
" "$J1" 2>/dev/null && ok "JSON 필드 값 검증(tag_counts/stage_tag/trend/retros 정렬)" || bad "JSON 필드 값 검증" "$J1"

# ── --dir 옵션 — edge-cases 픽스처(고정 태그 밖·문자열 태그·stage 미기재) ──
OUT=$("$R" --dir "$FIX/edge-cases" 2>&1); RC=$?
[ $RC -eq 0 ] && ok "--dir 옵션 지정 exit 0" || bad "--dir 옵션 지정 exit 0" "rc=$RC"
has "--dir 옵션 — 2건 집계" "회고 누적 통계 — 2건" "$OUT"

has "고정 8태그 밖 태그 — 정리 필요 라벨 표시" "자신감부족.*정리 필요" "$OUT"
has "고정 8태그 밖이 아닌 태그는 라벨 없이 표시(기업연구부족)" "기업연구부족.*1건" "$OUT"
has "stage 없는 항목 — (미기재) 그룹으로 집계" "(미기재): 근거부족 1" "$OUT"
hasnt "2건(<4)일 땐 추세 출력 없음" "추세:" "$OUT"
has "2건(<3)일 땐 소표본 경고 노출" "3건 미만" "$OUT"

J=$("$R" --dir "$FIX/edge-cases" --json 2>&1)
python3 -c "import json,sys; json.loads(sys.argv[1])" "$J" 2>/dev/null \
  && ok "--dir + --json 조합 시에도 유효한 JSON" || bad "--dir + --json 조합" "$J"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['unknown_tags'] == {'자신감부족': 1}, d['unknown_tags']
assert d['trend'] is None
sb = [r for r in d['retros'] if r['company'] == '스타트업B'][0]
assert sb['weakness_tags'] == ['근거부족'], sb  # 단일 문자열 → 리스트 정규화
assert sb['stage'] == '', sb
assert d['stage_tag']['(미기재)'] == {'근거부족': 1}
" "$J" 2>/dev/null && ok "weakness_tags 단일 문자열 → 리스트 정규화(JSON)" || bad "weakness_tags 리스트 정규화" "$J"

echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] jobstack-retro-stats"; exit 0; } || { echo "[FAIL] jobstack-retro-stats"; exit 1; }
