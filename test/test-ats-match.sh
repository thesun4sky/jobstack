#!/usr/bin/env bash
# bin/jobstack-ats-match 결정적 동작 테스트 (U-09).
#
# 이력서 Phase 4(ATS 매칭률)·자소서 Phase 9(반영률)·company-research Phase 4(역량매칭도)가
# 그대로 신뢰할 수 있도록, 매칭률·등급 계산이 결정적인지·단어 경계/한글 정규화/별칭 규칙이
# 소스(bin/jobstack-ats-match 상단 docstring)대로 동작하는지 픽스처로 검증한다.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
A="$REPO/bin/jobstack-ats-match"
FIX="$REPO/test/sample-data/ats"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }       # has NAME PATTERN TEXT
hasnt() { grep -q -- "$2" <<<"$3" && bad "$1" "$3" || ok "$1"; }

WORK=$(mktemp -d)
export JOBSTACK_STATE_DIR="$WORK/state"   # 이 스크립트는 상태를 읽지 않지만, 격리 관례를 맞춘다
trap 'rm -rf "$WORK"' EXIT

echo "## jobstack-ats-match"

python3 -m py_compile "$A" >/dev/null 2>&1 && ok "python3 -m py_compile 통과" || bad "python3 -m py_compile 통과"
[ -x "$A" ] && ok "실행 권한(chmod +x)" || bad "실행 권한(chmod +x)"

# ── 결정적 계산: 같은 입력 두 번 → 같은 출력 ──────────────────────────────
OUT1=$("$A" --keywords "$FIX/keywords-main.txt" --doc "$FIX/resume-main.md" 2>&1)
OUT2=$("$A" --keywords "$FIX/keywords-main.txt" --doc "$FIX/resume-main.md" 2>&1)
[ "$OUT1" = "$OUT2" ] && ok "결정적 계산(텍스트) — 동일 입력 두 번 → 동일 출력" || bad "결정적 계산(텍스트)" "diff 있음"
J1=$("$A" --keywords "$FIX/keywords-main.txt" --doc "$FIX/resume-main.md" --json 2>&1)
J2=$("$A" --keywords "$FIX/keywords-main.txt" --doc "$FIX/resume-main.md" --json 2>&1)
[ "$J1" = "$J2" ] && ok "결정적 계산(JSON) — 동일 입력 두 번 → 동일 출력" || bad "결정적 계산(JSON)" "diff 있음"

OUT=$OUT1; RC=0
"$A" --keywords "$FIX/keywords-main.txt" --doc "$FIX/resume-main.md" >/dev/null 2>&1; RC=$?
[ $RC -eq 0 ] && ok "정상 입력 exit 0" || bad "정상 입력 exit 0" "rc=$RC"

# ── 필수/우대 그룹별 매칭·전체 매칭률·등급 ──────────────────────────────
has "필수 그룹 매칭 수(3/5, 60%)" "필수: 3/5 (60%)" "$OUT"
has "우대 그룹 매칭 수(3/4, 75%)" "우대: 3/4 (75%)" "$OUT"
has "전체 매칭률(6/9, 67%)" "매칭률: 6/9 (67%)" "$OUT"
has "등급 B 판정" "등급 B" "$OUT"

# ── 누락 키워드 목록 ────────────────────────────────────────────────────
has "미반영 키워드 목록(Java, AWS, Go)" "미반영: Java, AWS, Go" "$OUT"
hasnt "매칭된 키워드는 미반영 목록에 없음(Python)" "미반영:.*Python" "$OUT"

# ── 별칭 매칭 — 1·2번째 별칭은 없고 3번째로만 매칭되어도 표시 ─────────────
has "별칭 매칭 — 한글 별칭(스프링)으로 매칭 표시" "6행 (스프링)" "$OUT"
has "별칭 매칭 — 영문 별칭(k8s)으로 매칭 표시" "10행 (k8s)" "$OUT"
has "정확 매칭(Docker)엔 별칭 표기 없음" "11행$" "$OUT"

# ── JSON 유효성 + 필드 검증 ─────────────────────────────────────────────
python3 -c "import json,sys; json.loads(sys.argv[1])" "$J1" 2>/dev/null \
  && ok "--json 출력이 유효한 JSON" || bad "--json 출력이 유효한 JSON" "$J1"
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
assert d['total'] == 9 and d['matched'] == 6 and d['rate'] == 67 and d['grade'] == 'B', d
assert d['groups']['필수'] == {'total': 5, 'matched': 3, 'rate': 60}, d['groups']
assert d['groups']['우대'] == {'total': 4, 'matched': 3, 'rate': 75}, d['groups']
items = {i['keyword']: i for i in d['items']}
assert items['Python']['matched'] is True and items['Python']['line'] == 4
assert items['Java']['matched'] is False and items['Java']['line'] is None and items['Java']['matched_by'] is None
assert items['Spring Boot']['matched_by'] == '스프링' and items['Spring Boot']['aliases'] == ['Spring', '스프링']
assert items['Kubernetes']['matched_by'] == 'k8s'
assert items['AWS']['matched'] is False
assert set(items) == {'Python','Java','Spring Boot','AWS','데이터 분석','Kubernetes','Docker','Go','GraphQL'}
" "$J1" 2>/dev/null && ok "JSON 필드 값 검증(total/matched/rate/grade/groups/items)" || bad "JSON 필드 값 검증" "$J1"

# ── ASCII 단어 경계 — java 가 javascript 에 매칭되지 않음 ────────────────
OUT=$("$A" --keywords "$FIX/keywords-java.txt" --doc "$FIX/resume-javascript-only.md" 2>&1)
has "단어 경계 — JavaScript 만 있으면 Java 는 미매칭" "매칭률: 0/1 (0%)" "$OUT"
has "단어 경계 — 미매칭 등급 C" "등급 C" "$OUT"
OUT=$("$A" --keywords "$FIX/keywords-java.txt" --doc "$FIX/resume-java-standalone.md" 2>&1)
has "단어 경계 — Java 가 단독으로 있으면 매칭" "매칭률: 1/1 (100%)" "$OUT"

# ── 한글 정규화 부분일치 — 공백/하이픈 무시 ───────────────────────────────
OUT=$("$A" --keywords "$FIX/keywords-korean-hyphen.txt" --doc "$FIX/resume-korean-hyphen.md" 2>&1)
has "한글 정규화 — '데이터 분석' = '데이터-분석'" "매칭률: 1/1 (100%)" "$OUT"

# ── 등급 경계 A(80%)/B(60%)/C(40%) ───────────────────────────────────────
OUT=$("$A" --keywords "$FIX/keywords-grade5.txt" --doc "$FIX/resume-grade-a.md" 2>&1)
has "등급 경계 — 4/5=80% → A" "매칭률: 4/5 (80%) → 등급 A" "$OUT"
OUT=$("$A" --keywords "$FIX/keywords-grade5.txt" --doc "$FIX/resume-grade-b.md" 2>&1)
has "등급 경계 — 3/5=60% → B" "매칭률: 3/5 (60%) → 등급 B" "$OUT"
OUT=$("$A" --keywords "$FIX/keywords-grade5.txt" --doc "$FIX/resume-grade-c.md" 2>&1)
has "등급 경계 — 2/5=40% → C" "매칭률: 2/5 (40%) → 등급 C" "$OUT"

# ── 기술명 특수문자(C++/C#/Node.js)는 문자 그대로 비교 ────────────────────
J=$("$A" --keywords "$FIX/keywords-symbols.txt" --doc "$FIX/resume-symbols.md" --json 2>&1)
python3 -c "
import json, sys
d = json.loads(sys.argv[1])
items = {i['keyword']: i['matched'] for i in d['items']}
assert items == {'C++': True, 'C#': True, 'Node.js': True}, items
" "$J" 2>/dev/null && ok "특수문자 기술명(C++/C#/Node.js) 리터럴 매칭" || bad "특수문자 기술명 매칭" "$J"

# ── 대소문자 무시 ─────────────────────────────────────────────────────
OUT=$("$A" --keywords "$FIX/keywords-case.txt" --doc "$FIX/resume-case-lower.md" 2>&1)
has "대소문자 무시 — PYTHON 키워드가 소문자 python 에 매칭" "매칭률: 1/1 (100%)" "$OUT"

# ── stdin(-) 입력 지원 ──────────────────────────────────────────────────
OUT=$(cat "$FIX/keywords-java.txt" | "$A" --keywords - --doc "$FIX/resume-java-standalone.md" 2>&1)
has "--keywords - 로 stdin 입력 지원" "매칭률: 1/1 (100%)" "$OUT"

# ── 오류 처리 — 빈 키워드 파일 (stdout/stderr 분리: 2>&1 >/dev/null 로 stderr만 캡처) ──
ERR=$("$A" --keywords "$FIX/keywords-empty.txt" --doc "$FIX/resume-main.md" 2>&1 >/dev/null); RC=$?
[ $RC -ne 0 ] && ok "빈 키워드 파일 → exit≠0" || bad "빈 키워드 파일 → exit≠0" "rc=$RC"
has "빈 키워드 파일 오류 메시지" "키워드가 없습니다" "$ERR"

printf '# 필수\n# 우대\n' > "$WORK/headers-only.txt"
"$A" --keywords "$WORK/headers-only.txt" --doc "$FIX/resume-main.md" >/dev/null 2>&1; RC=$?
[ $RC -ne 0 ] && ok "구분 헤더만 있고 키워드 없는 파일 → exit≠0" || bad "헤더만 있는 키워드 파일 → exit≠0" "rc=$RC"

# ── 오류 처리 — 존재하지 않는 파일 ─────────────────────────────────────
ERR=$("$A" --keywords "$FIX/keywords-main.txt" --doc "$WORK/nope.md" 2>&1 >/dev/null); RC=$?
[ $RC -ne 0 ] && ok "존재하지 않는 --doc → exit≠0" || bad "존재하지 않는 --doc → exit≠0" "rc=$RC"
has "존재하지 않는 --doc 오류 메시지" "파일을 읽을 수 없습니다" "$ERR"

ERR=$("$A" --keywords "$WORK/nope.txt" --doc "$FIX/resume-main.md" 2>&1 >/dev/null); RC=$?
[ $RC -ne 0 ] && ok "존재하지 않는 --keywords → exit≠0" || bad "존재하지 않는 --keywords → exit≠0" "rc=$RC"
has "존재하지 않는 --keywords 오류 메시지" "파일을 읽을 수 없습니다" "$ERR"

echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] jobstack-ats-match"; exit 0; } || { echo "[FAIL] jobstack-ats-match"; exit 1; }
