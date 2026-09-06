#!/usr/bin/env bash
# bin/jobstack-defense-map.mjs 결정적 동작 테스트 (docs/defense-map-schema.md 규칙).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
DM="$REPO/bin/jobstack-defense-map.mjs"
EXAMPLE="$REPO/templates/defense-map-example.yaml"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }       # has NAME PATTERN TEXT
hasnt() { grep -q -- "$2" <<<"$3" && bad "$1" "$3" || ok "$1"; }

echo "## jobstack-defense-map"

node --check "$DM" >/dev/null 2>&1 && ok "node --check 통과" || bad "node --check 통과"
[ -x "$DM" ] && ok "실행 권한(chmod +x)" || bad "실행 권한(chmod +x)"
[ -f "$EXAMPLE" ] && ok "픽스처 존재(templates/defense-map-example.yaml)" || bad "픽스처 존재"

WORK=$(mktemp -d)
export JOBSTACK_STATE_DIR="$WORK/state"
DM_DIR="$JOBSTACK_STATE_DIR/defense-maps"
TODAY_COMPACT=$(TZ=Asia/Seoul date +%Y%m%d)

# ── add: --from 예시 픽스처 (cover-letter, entry 2개 -> 경고만, 저장은 됨) ────────────
ADD_OUT=$("$DM" add --company "네이버" --position "백엔드 개발자" --source-skill cover-letter \
                    --document-ref "자소서_test.md" --from "$EXAMPLE" 2>"$WORK/stderr1"); RC=$?
STDERR1=$(cat "$WORK/stderr1")
[ $RC -eq 0 ] && ok "add --from 정상 종료(exit 0)" || bad "add --from 정상 종료" "rc=$RC stderr=$STDERR1"
FILE1="$ADD_OUT"
has "add 성공 시 stdout 은 경로" "$DM_DIR/네이버_백엔드-개발자_${TODAY_COMPACT}.yaml" "$ADD_OUT"
[ -f "$FILE1" ] && ok "add --from 파일 생성됨" || bad "add --from 파일 생성" "path=$FILE1"
has "cover-letter entry<5 는 경고만(exit 0 유지)" "미끼 5개 배치" "$STDERR1"
has "회사/직무 공백->하이픈 정규화(파일 내용)" "position: 백엔드-개발자" "$(cat "$FILE1")"
has "schema_version 1" "schema_version: 1" "$(cat "$FILE1")"
has "created_at 은 KST(+09:00) 표기" '+09:00' "$(cat "$FILE1")"
has "--from 기존 entry id(dm-001) 보존" "id: dm-001" "$(cat "$FILE1")"
has "--from 기존 entry id(dm-002) 보존" "id: dm-002" "$(cat "$FILE1")"

# ── add: 같은 회사/직무 같은 날 재산출 -> _2 접미 ──────────────────────────────────
ADD_OUT2=$("$DM" add --company "네이버" --position "백엔드 개발자" --source-skill review \
                     --document-ref "ref2" \
                     --entries-json '[{"sentence":"s1","location":"L1","bait_type":"수치","questions":[{"q":"Q1","intent":"I1","difficulty":"normal"},{"q":"Q2","intent":"I2","difficulty":"hard"}]},{"sentence":"s2","location":"L2","bait_type":"성과","questions":[{"q":"Q3","intent":"I3","difficulty":"mild"},{"q":"Q4","intent":"I4","difficulty":"normal"}]}]' 2>/dev/null)
FILE2="$ADD_OUT2"
has "같은 날 재산출 시 _2 접미 파일명" "_${TODAY_COMPACT}_2.yaml" "$FILE2"
[ "$FILE1" != "$FILE2" ] && ok "_2 파일은 원본과 다른 경로" || bad "_2 파일 경로 충돌"
has "entries-json 의 id 없는 entry 는 dm-001 부터 자동 부여" "id: dm-001" "$(cat "$FILE2")"
has "defense_status 미지정 시 unprepared 기본값" "defense_status: unprepared" "$(cat "$FILE2")"
has "answer_hint 미지정 시 null 기본값(추정 작성 금지)" "answer_hint: null" "$(cat "$FILE2")"

# ── add: --entries-json 순수 배열이 아니라 --from 이 { entries: [...] } 래핑도 허용 ────
PLAIN_ARR="$WORK/plain-entries.yaml"
cat > "$PLAIN_ARR" <<'YAML'
- sentence: "순수 배열 입력"
  location: "L"
  bait_type: 기술선택
  questions:
    - q: "Q1"
      intent: "I1"
      difficulty: mild
    - q: "Q2"
      intent: "I2"
      difficulty: normal
YAML
ADD_OUT3=$("$DM" add --company "카카오" --position "서버개발자" --source-skill career-history --document-ref r --from "$PLAIN_ARR" 2>/dev/null)
FILE3="$ADD_OUT3"
[ -f "$FILE3" ] && ok "--from 순수 배열(entries 래핑 없음)도 허용" || bad "--from 순수 배열" "path=$FILE3"

# ── add: 오류 경로 ───────────────────────────────────────────────────────────
OUT_NOSRC=$("$DM" add --company X --position Y --source-skill bogus --document-ref r --entries-json '[]' 2>&1); RC=$?
[ $RC -eq 1 ] && has "잘못된 source-skill 오류" "source-skill" "$OUT_NOSRC" || bad "잘못된 source-skill exit 1" "rc=$RC"

OUT_EMPTY=$("$DM" add --company X --position Y --source-skill review --document-ref r --entries-json '[]' 2>&1); RC=$?
[ $RC -eq 1 ] && has "entries 0개는 오류(빈 파일)" "entries 는 1개 이상" "$OUT_EMPTY" || bad "entries 0개 exit 1" "rc=$RC"

OUT_BADBAIT=$("$DM" add --company X --position Y --source-skill review --document-ref r \
  --entries-json '[{"sentence":"s","location":"l","bait_type":"이상한값","questions":[{"q":"a","intent":"b","difficulty":"mild"},{"q":"c","intent":"d","difficulty":"mild"}]}]' 2>&1); RC=$?
[ $RC -eq 1 ] && has "잘못된 bait_type 오류" "bait_type 값이 올바르지 않습니다" "$OUT_BADBAIT" || bad "잘못된 bait_type exit 1" "rc=$RC"

OUT_BADDIFF=$("$DM" add --company X --position Y --source-skill review --document-ref r \
  --entries-json '[{"sentence":"s","location":"l","bait_type":"수치","questions":[{"q":"a","intent":"b","difficulty":"impossible"},{"q":"c","intent":"d","difficulty":"mild"}]}]' 2>&1); RC=$?
[ $RC -eq 1 ] && has "잘못된 difficulty 오류" "difficulty 값이 올바르지 않습니다" "$OUT_BADDIFF" || bad "잘못된 difficulty exit 1" "rc=$RC"

OUT_1Q=$("$DM" add --company X --position Y --source-skill review --document-ref r \
  --entries-json '[{"sentence":"s","location":"l","bait_type":"수치","questions":[{"q":"a","intent":"b","difficulty":"mild"}]}]' 2>&1); RC=$?
[ $RC -eq 1 ] && has "questions 1개는 오류(2개 미만)" "questions 는 2개 이상" "$OUT_1Q" || bad "questions 1개 exit 1" "rc=$RC"

OUT_BADSTATUS=$("$DM" add --company X --position Y --source-skill review --document-ref r \
  --entries-json '[{"sentence":"s","location":"l","bait_type":"수치","defense_status":"불명","questions":[{"q":"a","intent":"b","difficulty":"mild"},{"q":"c","intent":"d","difficulty":"mild"}]}]' 2>&1); RC=$?
[ $RC -eq 1 ] && has "잘못된 defense_status 오류" "defense_status 값이 올바르지 않습니다" "$OUT_BADSTATUS" || bad "잘못된 defense_status exit 1" "rc=$RC"

OUT_NOENTRIES=$("$DM" add --company X --position Y --source-skill review --document-ref r 2>&1); RC=$?
[ $RC -eq 1 ] && has "entries 입력 미지정 오류" "entries-json 또는 --from" "$OUT_NOENTRIES" || bad "entries 미지정 exit 1" "rc=$RC"

# 위 오류 경로들이 실제로 아무 파일도 만들지 않았는지(빈 디렉토리 오염 없음)
BOGUS_FILES=$(find "$DM_DIR" -name 'X_Y_*.yaml' 2>/dev/null | wc -l | tr -d ' ')
[ "$BOGUS_FILES" -eq 0 ] && ok "검증 실패 시 파일을 쓰지 않음" || bad "검증 실패 시 파일 미생성" "생성된 파일 ${BOGUS_FILES}개"

# ── list ────────────────────────────────────────────────────────────────────
LIST_OUT=$("$DM" list 2>&1)
has "list 헤더" "defense-map 목록" "$LIST_OUT"
has "list 에 네이버 포함" "네이버" "$LIST_OUT"
has "list 에 카카오 포함" "카카오" "$LIST_OUT"
has "list 준비율 표기" "준비율 0/2 (0%)" "$LIST_OUT"

# 회사명 느슨 매칭 — 저장값은 하이픈("삼성-SDS")인데 검색은 공백/무공백 모두 허용해야 함
"$DM" add --company "삼성 SDS" --position "데이터엔지니어" --source-skill review --document-ref r \
  --entries-json '[{"sentence":"s","location":"l","bait_type":"수치","questions":[{"q":"a","intent":"b","difficulty":"mild"},{"q":"c","intent":"d","difficulty":"mild"}]}]' >/dev/null 2>&1
has "느슨 매칭(공백 포함 검색)" "삼성" "$("$DM" list --company "삼성 SDS" 2>&1)"
has "느슨 매칭(공백 없는 검색)" "삼성" "$("$DM" list --company "삼성sds" 2>&1)"
NOMATCH_OUT=$("$DM" list --company "존재하지않는회사" 2>&1)
has "매칭 없으면 안내 메시지" "없습니다" "$NOMATCH_OUT"

LIST_JSON=$("$DM" list --json 2>&1)
CHECK=$(node -e "
const rows = JSON.parse(require('fs').readFileSync(0,'utf8'));
const ok = Array.isArray(rows) && rows.length >= 4 && rows.every(r => typeof r.ready_ratio === 'string' && r.ready_ratio.includes('%'));
console.log(ok ? 'OK' : 'MISMATCH:' + JSON.stringify(rows));
" <<<"$LIST_JSON")
[ "$CHECK" = "OK" ] && ok "list --json 구조" || bad "list --json 구조" "$CHECK"

# ── show — 우선순위(weak/unprepared 먼저) + 잘림 ────────────────────────────────
"$DM" add --company "쇼우테스트" --position "직무" --source-skill review --document-ref r \
  --entries-json '[
    {"sentence":"레디문장","location":"L","bait_type":"수치","defense_status":"ready","questions":[{"q":"RQ1","intent":"I","difficulty":"mild"},{"q":"RQ2","intent":"I","difficulty":"mild"}]},
    {"sentence":"위크문장","location":"L","bait_type":"성과","defense_status":"weak","questions":[{"q":"WQ1","intent":"I","difficulty":"mild"},{"q":"WQ2","intent":"I","difficulty":"mild"}]},
    {"sentence":"언프리페어드문장","location":"L","bait_type":"역할범위","defense_status":"unprepared","questions":[{"q":"UQ1","intent":"I","difficulty":"mild"},{"q":"UQ2","intent":"I","difficulty":"mild"}]}
  ]' >/dev/null 2>&1

SHOW_ALL=$("$DM" show --company 쇼우테스트 --all 2>&1)
FIRST_LINE=$(echo "$SHOW_ALL" | sed -n '1p')
SECOND_LINE=$(echo "$SHOW_ALL" | sed -n '2p')
THIRD_LINE=$(echo "$SHOW_ALL" | sed -n '3p')
has "show 우선순위 1번째: unprepared" "언프리페어드문장" "$FIRST_LINE"
has "show 우선순위 2번째: weak" "위크문장" "$SECOND_LINE"
has "show 우선순위 3번째: ready(마지막)" "레디문장" "$THIRD_LINE"
has "show 압축 라인 포맷([id|bait_type|status] 문장 — Q1 / Q2)" '\[dm-...\|역할범위\|unprepared\] 언프리페어드문장 — UQ1 / UQ2' "$FIRST_LINE"

# --max-chars: 매우 작은 상한 -> 전량 생략 + 트레일러
TINY_OUT=$("$DM" show --company 쇼우테스트 --max-chars 1 2>&1)
has "max-chars 매우 작으면 전량 생략 트레일러" "… (3개 생략)" "$TINY_OUT"
hasnt "생략 시 entry 문장 자체는 출력 안 함" "언프리페어드문장" "$TINY_OUT"

# --max-chars: 1번째 줄만 정확히 들어가는 상한 -> 1개 표시 + 2개 생략(우선순위 반영해 unprepared 만 남음)
FIRST_LEN=$(printf '%s' "$FIRST_LINE" | wc -m | tr -d ' ')
PARTIAL_OUT=$("$DM" show --company 쇼우테스트 --max-chars "$FIRST_LEN" 2>&1)
has "잘림 상한에 딱 맞는 1번째 줄은 표시" "언프리페어드문장" "$PARTIAL_OUT"
hasnt "우선순위 밀린 2번째(weak) 는 생략됨" "위크문장" "$PARTIAL_OUT"
has "부분 생략 트레일러(2개 생략)" "… (2개 생략)" "$PARTIAL_OUT"

# --all 은 상한 무시
ALL_LEN=$(printf '%s' "$SHOW_ALL" | wc -m | tr -d ' ')
[ "$ALL_LEN" -gt "$FIRST_LEN" ] && has "--all 은 max-chars 무시하고 전량 출력" "레디문장" "$SHOW_ALL" || bad "--all 전량 출력"

# --file 로 특정 파일 직접 지정
SHOW_BY_FILE=$("$DM" show --file "$FILE1" --all 2>&1)
has "show --file 지정 파일 사용" "350ms에서 15ms" "$SHOW_BY_FILE"

SHOW_NOMATCH=$("$DM" show --company "없는회사이름진짜로" 2>&1); RC=$?
[ $RC -eq 1 ] && has "show 매칭 파일 없으면 오류" "찾지 못했습니다" "$SHOW_NOMATCH" || bad "show 매칭 없음 exit 1" "rc=$RC"

# ── set-status — 정상/오류/주석 보존 ────────────────────────────────────────────
KAKAO_FILE=$(ls "$DM_DIR"/카카오_*.yaml | head -1)
# set-status 대상 파일에 주석을 심어 보존 여부 확인
printf '\n# 검토자 메모 — set-status 이후에도 남아야 함\n' >> "$KAKAO_FILE"
SET_OUT=$("$DM" set-status "$KAKAO_FILE" dm-001 ready 2>&1); RC=$?
[ $RC -eq 0 ] && ok "set-status(file) 정상 종료" || bad "set-status(file) 정상 종료" "rc=$RC"
has "set-status 확인 메시지에 한글 라벨 포함" "방어 준비됨" "$SET_OUT"
has "set-status 확인 메시지에 원문 키도 병기" "(ready)" "$SET_OUT"
has "set-status 후 defense_status 반영" "defense_status: ready" "$(cat "$KAKAO_FILE")"
has "set-status 후 주석 보존" "# 검토자 메모 — set-status 이후에도 남아야 함" "$(cat "$KAKAO_FILE")"

# --company 경유 (최신 파일 자동 선택)
SET_OUT2=$("$DM" set-status --company 카카오 dm-001 weak 2>&1); RC=$?
[ $RC -eq 0 ] && has "set-status(--company) 정상 종료" "답변 불충분" "$SET_OUT2" || bad "set-status(--company)" "rc=$RC"

OUT_BADENTRY=$("$DM" set-status "$KAKAO_FILE" dm-999 ready 2>&1); RC=$?
[ $RC -eq 1 ] && has "없는 entry-id 오류" "찾을 수 없습니다" "$OUT_BADENTRY" || bad "없는 entry-id exit 1" "rc=$RC"

OUT_BADSTATUSARG=$("$DM" set-status "$KAKAO_FILE" dm-001 bogus 2>&1); RC=$?
[ $RC -eq 1 ] && has "잘못된 status 인자 오류" "ready|weak|unprepared" "$OUT_BADSTATUSARG" || bad "잘못된 status 인자 exit 1" "rc=$RC"

OUTSIDE_TARGET="$WORK/outside.yaml"
cp "$KAKAO_FILE" "$OUTSIDE_TARGET"
OUT_OUTSIDE=$("$DM" set-status "$OUTSIDE_TARGET" dm-001 ready 2>&1); RC=$?
[ $RC -eq 1 ] && has "상태 디렉토리 밖 파일은 쓰기 거부" "상태 디렉토리 밖" "$OUT_OUTSIDE" || bad "상태 디렉토리 밖 거부 exit 1" "rc=$RC"

# ── stats — 분수/퍼센트 표기 ──────────────────────────────────────────────────
"$DM" add --company "스탯테스트" --position "직무" --source-skill review --document-ref r \
  --entries-json '[
    {"sentence":"e1","location":"L","bait_type":"수치","defense_status":"ready","questions":[{"q":"a","intent":"i","difficulty":"mild"},{"q":"b","intent":"i","difficulty":"mild"}]},
    {"sentence":"e2","location":"L","bait_type":"수치","defense_status":"ready","questions":[{"q":"a","intent":"i","difficulty":"mild"},{"q":"b","intent":"i","difficulty":"mild"}]},
    {"sentence":"e3","location":"L","bait_type":"수치","defense_status":"weak","questions":[{"q":"a","intent":"i","difficulty":"mild"},{"q":"b","intent":"i","difficulty":"mild"}]}
  ]' >/dev/null 2>&1
STATS_OUT=$("$DM" stats --company 스탯테스트 2>&1)
has "stats 분수 표기(2/3)" "2/3" "$STATS_OUT"
has "stats 퍼센트 반올림 표기(67%, 소수 없이)" "2/3 (67%)" "$STATS_OUT"
STATS_JSON=$("$DM" stats --company 스탯테스트 --json 2>&1)
has "stats --json ratio 필드" '"ratio": "2/3 (67%)"' "$STATS_JSON"

# ── validate ────────────────────────────────────────────────────────────────
VALID_OUT=$("$DM" validate "$FILE3" 2>&1); RC=$?
[ $RC -eq 0 ] && has "정상 파일 validate 통과" "PASS" "$VALID_OUT" || bad "정상 파일 validate" "rc=$RC out=$VALID_OUT"

EXAMPLE_VALIDATE=$("$DM" validate "$EXAMPLE" 2>&1); RC=$?
[ $RC -eq 0 ] && has "예시 픽스처 자체도 validate 통과(경고만)" "PASS" "$EXAMPLE_VALIDATE" || bad "예시 픽스처 validate" "rc=$RC out=$EXAMPLE_VALIDATE"
has "예시 픽스처는 cover-letter entry<5 경고 표시" "미끼 5개 배치" "$EXAMPLE_VALIDATE"

OUT_NOFILEARG=$("$DM" validate 2>&1); RC=$?
[ $RC -eq 1 ] && has "validate 파일 인자 없으면 오류" "file 을 지정" "$OUT_NOFILEARG" || bad "validate 인자없음 exit 1" "rc=$RC"

OUT_MISSING=$("$DM" validate "$WORK/no-such-file.yaml" 2>&1); RC=$?
[ $RC -eq 1 ] && has "validate 없는 파일 오류" "파일이 없습니다" "$OUT_MISSING" || bad "validate 없는 파일 exit 1" "rc=$RC"

EMPTYFILE="$WORK/empty.yaml"
: > "$EMPTYFILE"
OUT_EMPTYFILE=$("$DM" validate "$EMPTYFILE" 2>&1); RC=$?
[ $RC -eq 1 ] && ok "validate 빈 파일 오류(exit 1)" || bad "validate 빈 파일 exit 1" "rc=$RC out=$OUT_EMPTYFILE"

DUPFILE="$WORK/dup.yaml"
cat > "$DUPFILE" <<'YAML'
schema_version: 1
source_skill: review
created_at: "2026-07-03T18:30:00+09:00"
company: 테스트
position: 포지션
document_ref: ref
entries:
  - id: dm-001
    sentence: s1
    location: L1
    bait_type: 수치
    questions:
      - q: Q1
        intent: I1
        difficulty: normal
      - q: Q2
        intent: I2
        difficulty: hard
    answer_hint: null
    defense_status: ready
  - id: dm-001
    sentence: s2
    location: L2
    bait_type: 성과
    questions:
      - q: Q3
        intent: I3
        difficulty: mild
      - q: Q4
        intent: I4
        difficulty: normal
    answer_hint: null
    defense_status: weak
YAML
DUP_OUT=$("$DM" validate "$DUPFILE" 2>&1); RC=$?
[ $RC -eq 1 ] && has "validate entry id 중복 검출" "id 중복" "$DUP_OUT" || bad "validate id 중복 exit 1" "rc=$RC"

# ── 기타 ─────────────────────────────────────────────────────────────────
HELP_OUT=$("$DM" --help 2>&1); RC=$?
[ $RC -eq 0 ] && has "--help 는 exit 0" "사용법" "$HELP_OUT" || bad "--help exit 0" "rc=$RC"

NOARG_OUT=$("$DM" 2>&1); RC=$?
[ $RC -eq 1 ] && has "인자 없이 실행 시 사용법 안내(exit 1)" "사용법" "$NOARG_OUT" || bad "인자 없음 exit 1" "rc=$RC"

BOGUS_OUT=$("$DM" bogus-command 2>&1); RC=$?
[ $RC -eq 1 ] && has "알 수 없는 명령 오류(exit 1)" "알 수 없는 명령" "$BOGUS_OUT" || bad "알 수 없는 명령 exit 1" "rc=$RC"

# 한글 라벨 출력에 영문 상태 키가 새지 않는지 — list/stats 는 순수 집계만 보여줘야 하고
# (defense_status 원문 키는 show 의 계약된 압축 포맷에서만 노출되는 게 맞다)
hasnt "list 사람이 보는 출력에 defense_status 원문 키 노출 없음(ready)" "|ready|" "$LIST_OUT"
hasnt "stats 사람이 보는 출력에 defense_status 원문 키 노출 없음" "|ready|" "$STATS_OUT"
hasnt "stats 사람이 보는 출력에 defense_status 원문 키 노출 없음(unprepared)" "unprepared" "$STATS_OUT"

# 상태 디렉토리 밖에는 쓰지 않는다 — add 결과 경로가 항상 defense-maps/ 안쪽인지
has "add 결과 경로가 상태 디렉토리 내부(defense-maps/)" "$DM_DIR/" "$FILE3"

rm -rf "$WORK"
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] jobstack-defense-map"; exit 0; } || { echo "[FAIL] jobstack-defense-map"; exit 1; }
