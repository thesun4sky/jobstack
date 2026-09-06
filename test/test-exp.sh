#!/usr/bin/env bash
# bin/jobstack-exp.mjs 결정적 동작 테스트 (docs/experience-card-schema.md 규칙).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
E="$REPO/bin/jobstack-exp.mjs"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
has() { grep -q -- "$2" <<<"$3" && ok "$1" || bad "$1" "$3"; }       # has NAME PATTERN TEXT
hasnt() { grep -q -- "$2" <<<"$3" && bad "$1" "$3" || ok "$1"; }

echo "## jobstack-exp"

node --check "$E" >/dev/null 2>&1 && ok "node --check 통과" || bad "node --check 통과"
[ -x "$E" ] && ok "실행 권한(chmod +x)" || bad "실행 권한(chmod +x)"

WORK=$(mktemp -d)
export JOBSTACK_STATE_DIR="$WORK/state"
F="$JOBSTACK_STATE_DIR/profiles/experiences.yaml"
TODAY_COMPACT=$(TZ=Asia/Seoul date +%Y%m%d)

# ── add — 기본 성공 경로 ──────────────────────────────────────────────────────
OUT=$("$E" add --title "결제 API 지연 개선" --problem "응답이 350ms 이상 걸림" --role "캐싱 설계 전담" \
             --action "Redis 캐싱 도입" --change "350ms -> 15ms 단축" --numbers "350ms -> 15ms" \
             --tags "백엔드,Node.js" 2>&1)
RC=$?
[ $RC -eq 0 ] && ok "add 정상 종료(exit 0)" || bad "add 정상 종료" "rc=$RC"
has "add 성공 시 id 출력" "추가됨: exp-${TODAY_COMPACT}-01" "$OUT"
has "add 성공 시 경로 출력" "경로: $F" "$OUT"
[ -f "$F" ] && ok "파일 부재 시 자동 생성" || bad "파일 자동 생성"

# 같은 날 두 번째 카드 -> NN 증가(01 -> 02), 파일 재덤프 없이 append
OUT2=$("$E" add --title "카드2" --problem p2 --role r2 --action a2 --change c2 2>&1)
has "같은 날짜 2번째 카드 id NN 증가" "exp-${TODAY_COMPACT}-02" "$OUT2"
has "기존 카드1 값 유지(재덤프 아님, append)" "결제 API 지연 개선" "$(cat "$F")"

has "numbers 미지정 시 빈 문자열로 저장" 'numbers: ""' "$(cat "$F")"

# ai_usage 3플래그 동시 지정 -> 저장됨
OUT3=$("$E" add --title "AI 협업 카드" --problem p3 --role r3 --action a3 --change c3 \
              --ai-usage-tool "Claude Code" --ai-usage-task "리팩터링 검토" --ai-usage-effect "리뷰 시간 2h -> 40m" 2>&1)
has "ai-usage 3플래그 add 성공" "추가됨: exp-${TODAY_COMPACT}-03" "$OUT3"
has "ai_usage.tool 저장" "tool: Claude Code" "$(cat "$F")"
has "ai_usage.effect 저장" "2h -> 40m" "$(cat "$F")"

# ai_usage 부분 지정은 add 단계에서 거부(스키마 위반 방지)
OUT4=$("$E" add --title t --problem p --role r --action a --change c --ai-usage-tool onlytool 2>&1); RC=$?
[ $RC -eq 1 ] && has "ai-usage 부분 지정은 add 오류" "함께 지정" "$OUT4" || bad "ai-usage 부분 지정 exit 1" "rc=$RC"

# 필수 인자 누락
OUT5=$("$E" add --title onlytitle 2>&1); RC=$?
[ $RC -eq 1 ] && has "필수 인자 누락 오류(exit 1)" "필수 인자 누락" "$OUT5" || bad "필수 인자 누락 exit 1" "rc=$RC"

# --json 입력 경로 (개별 플래그 없이 전량 JSON, tags 포함)
OUT6=$("$E" add --json '{"title":"JSON 카드","problem":"p4","role":"r4","action":"a4","change":"[수치 확인 필요]","numbers":"[수치 확인 필요]","tags":["기획","PM"]}' 2>&1)
has "json 입력 add 성공" "추가됨: exp-${TODAY_COMPACT}-04" "$OUT6"
has "json 입력 job_link_tags 저장" "- 기획" "$(cat "$F")"
has "[수치 확인 필요] placeholder 그대로 저장(날조 없음)" '\[수치 확인 필요\]' "$(cat "$F")"

# ── list ──────────────────────────────────────────────────────────────────
LIST_OUT=$("$E" list 2>&1)
has "list 요약 헤더" "경험뱅크 요약" "$LIST_OUT"
has "list 기준일 KST 표기" "기준일: 20" "$LIST_OUT"
has "list 카드 수 집계" "카드 4장" "$LIST_OUT"
has "list 수치 O 판정" " O " "$LIST_OUT"
has "list 수치 X 판정(카드2, numbers 없음)" " X " "$LIST_OUT"
has "list 수치 △ 판정([수치 확인 필요])" " △ " "$LIST_OUT"
# AI 열: ai_usage 를 준 카드3 행에만 O 가 찍히고(수치는 X), 다른 행엔 안 찍혀야 한다
AI_ROW=$(grep 'AI 협업 카드' <<<"$LIST_OUT")
echo "$AI_ROW" | grep -qE 'X +O' && ok "list AI 열 O(ai_usage 있는 카드)" || bad "list AI 열 O(ai_usage 있는 카드)" "$AI_ROW"
has "list 수치 보강 필요 집계(카드2·3·4)" "수치 보강 필요 3장" "$LIST_OUT"

LIST_JSON=$("$E" list --json 2>&1)
CHECK=$(node -e "
const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
const ok = d.total === 4 && d.needs_numbers === 3 && d.cards.length === 4
  && d.cards[2].ai_usage_present === true && d.cards[1].numbers_verdict === 'X'
  && d.cards[3].numbers_verdict === '△';
console.log(ok ? 'OK' : 'MISMATCH:' + JSON.stringify(d));
" <<<"$LIST_JSON")
[ "$CHECK" = "OK" ] && ok "list --json 구조·판정 일치" || bad "list --json 구조·판정 일치" "$CHECK"

# ── show ──────────────────────────────────────────────────────────────────
ID1="exp-${TODAY_COMPACT}-01"
SHOW_OUT=$("$E" show "$ID1" 2>&1)
has "show 카드 YAML — id" "id: $ID1" "$SHOW_OUT"
has "show 카드 YAML — title" "title: 결제 API 지연 개선" "$SHOW_OUT"

OUT_MISS=$("$E" show exp-nonexistent 2>&1); RC=$?
[ $RC -eq 1 ] && has "show 없는 id 오류(exit 1)" "찾을 수 없습니다" "$OUT_MISS" || bad "show 없는 id exit 1" "rc=$RC"

OUT_NOID=$("$E" show 2>&1); RC=$?
[ $RC -eq 1 ] && ok "show id 미지정 오류(exit 1)" || bad "show id 미지정 exit 1" "rc=$RC"

# ── update — 필드 수정 + 주석 보존 ───────────────────────────────────────────
printf '\n# 사용자 메모 — update 이후에도 남아야 함\n' >> "$F"
UPD_OUT=$("$E" update "$ID1" --title "결제 API 지연 개선(수정)" --numbers "350ms -> 12ms" 2>&1)
has "update 성공 메시지" "수정됨: $ID1" "$UPD_OUT"
has "update 후 title 반영" "결제 API 지연 개선(수정)" "$(cat "$F")"
has "update 후 numbers 반영" "350ms -> 12ms" "$(cat "$F")"
has "update 후 주석 보존" "# 사용자 메모 — update 이후에도 남아야 함" "$(cat "$F")"
has "update 안 한 카드2 는 그대로" "카드2" "$(cat "$F")"

# tags 갱신
"$E" update "$ID1" --tags "백엔드,인프라" >/dev/null 2>&1
has "update --tags 반영" "인프라" "$(cat "$F")"

# ai_usage 없는 카드(카드2)에 부분 update -> 갱신 후 task/effect 가 비므로 add 와 동일하게
# 거부(exit 1)해야 한다(리뷰 반영 — 이전엔 null->map 승격을 허용해 validate 만 통과하는
# 스키마 위반 파일을 만들 수 있었다). 파일은 변경되지 않아야 한다(die 는 atomicWrite 이전에 발생).
ID2="exp-${TODAY_COMPACT}-02"
BEFORE_ID2=$(cat "$F")
PARTIAL_OUT=$("$E" update "$ID2" --ai-usage-tool "Claude Code" 2>&1); RC=$?
[ $RC -eq 1 ] && has "ai_usage 없는 카드의 부분 update 는 거부(exit 1)" "채워져 있어야" "$PARTIAL_OUT" \
  || bad "ai_usage 부분 update 거부(exit 1)" "rc=$RC out=$PARTIAL_OUT"
[ "$(cat "$F")" = "$BEFORE_ID2" ] && ok "거부된 부분 update 는 파일 미변경" || bad "거부된 부분 update 파일 미변경" "파일이 변경됨"
VALIDATE_UNCHANGED=$("$E" validate 2>&1); RC=$?
[ $RC -eq 0 ] && has "거부 후에도 파일은 여전히 유효(validate 통과)" "PASS" "$VALIDATE_UNCHANGED" \
  || bad "거부 후 validate 통과해야 함" "rc=$RC out=$VALIDATE_UNCHANGED"

# 세 플래그를 한 번에 지정하면(= add 와 동일 조건) update 로도 성공
"$E" update "$ID2" --ai-usage-tool "Claude Code" --ai-usage-task "코드리뷰" --ai-usage-effect "40분 단축" >/dev/null 2>&1
has "ai_usage 3플래그 동시 update 성공" "tool: Claude Code" "$(cat "$F")"
VALIDATE_FULL=$("$E" validate 2>&1); RC=$?
[ $RC -eq 0 ] && has "ai_usage 3필드 완성 후 validate 통과" "PASS" "$VALIDATE_FULL" || bad "ai_usage 완성 후 validate" "rc=$RC out=$VALIDATE_FULL"

# 이미 완전한 ai_usage 가 있는 카드는 한 필드만 갱신해도 허용 — 나머지 필드가 그대로 남아
# 갱신 후에도 세 값이 모두 채워져 있기 때문(요구사항의 명시적 예외).
"$E" update "$ID2" --ai-usage-tool "Cursor" >/dev/null 2>&1
has "완전한 ai_usage 의 일부 필드만 갱신은 허용" "tool: Cursor" "$(cat "$F")"
has "일부 필드만 갱신해도 나머지 필드는 유지" "코드리뷰" "$(cat "$F")"
VALIDATE_AFTER_PARTIAL=$("$E" validate 2>&1); RC=$?
[ $RC -eq 0 ] && has "완전한 ai_usage 의 부분 갱신 후에도 validate 통과" "PASS" "$VALIDATE_AFTER_PARTIAL" \
  || bad "완전한 ai_usage 부분 갱신 후 validate" "rc=$RC out=$VALIDATE_AFTER_PARTIAL"

OUT_UPD_MISS=$("$E" update exp-nonexistent --title x 2>&1); RC=$?
[ $RC -eq 1 ] && has "update 없는 id 오류(exit 1)" "찾을 수 없습니다" "$OUT_UPD_MISS" || bad "update 없는 id exit 1" "rc=$RC"

OUT_UPD_NOFIELD=$("$E" update "$ID1" 2>&1); RC=$?
[ $RC -eq 1 ] && has "update 필드 미지정 오류(exit 1)" "최소 1개" "$OUT_UPD_NOFIELD" || bad "update 필드미지정 exit 1" "rc=$RC"

# ── apply — 입사 후 적용(STAR-R 의 R) 회사당 1건 upsert ─────────────────────
APPLY_OUT=$("$E" apply "$ID1" --company "토스" --position "백엔드" \
  --plan "결제 응답 지연 과제에 Redis 캐싱 설계 경험을 적용해 p95 지연 원인 분석부터 맡는다" \
  --basis "핵심 키워드: 결제 안정성" --source "company-cache/토스-2026-09-06.md" 2>&1); RC=$?
[ $RC -eq 0 ] && has "apply 정상 종료 + 저장 메시지" "적용 저장됨: $ID1" "$APPLY_OUT" || bad "apply 정상 종료" "rc=$RC out=$APPLY_OUT"
has "apply 신규 표시" "(신규)" "$APPLY_OUT"
has "apply_plans.company 저장" "company: 토스" "$(cat "$F")"
has "apply_plans.basis 원문 저장" "핵심 키워드: 결제 안정성" "$(cat "$F")"
has "apply 후 주석 보존" "# 사용자 메모 — update 이후에도 남아야 함" "$(cat "$F")"

# 같은 회사(공백·대소문자 정규화 등치)는 교체 — 항목 수는 그대로, 새 plan 만 남는다
"$E" apply "$ID1" --company " 토스" --plan "새 계획" --basis "b2" --source "s2" >/dev/null 2>&1
COMPANY_LINES=$(grep -c 'company: ' "$F")
[ "$COMPANY_LINES" -eq 1 ] && ok "같은 회사 재-apply 는 교체(항목 1건 유지)" || bad "같은 회사 재-apply 교체" "company 줄 수=$COMPANY_LINES"
has "교체 후 새 plan 저장" "새 계획" "$(cat "$F")"
hasnt "교체 후 이전 plan 제거" "p95 지연 원인 분석부터" "$(cat "$F")"
REPL_OUT=$("$E" apply "$ID1" --company "토스" --plan "새 계획2" --basis "b3" --source "s3" 2>&1)
has "교체 시 (교체) 표시" "(교체)" "$REPL_OUT"

# 다른 회사는 추가
"$E" apply "$ID1" --company "네이버" --plan "n-plan" --basis "n-basis" --source "n-source" >/dev/null 2>&1
COMPANY_LINES=$(grep -c 'company: ' "$F")
[ "$COMPANY_LINES" -eq 2 ] && ok "다른 회사 apply 는 추가(항목 2건)" || bad "다른 회사 apply 추가" "company 줄 수=$COMPANY_LINES"

# 근거·출처 누락은 거부(exit 1) + 파일 미변경
BEFORE_APPLY=$(cat "$F")
MISS_OUT=$("$E" apply "$ID1" --company "카카오" --plan "x" 2>&1); RC=$?
[ $RC -eq 1 ] && has "apply --basis/--source 누락 거부(exit 1)" "basis" "$MISS_OUT" || bad "apply 누락 거부 exit 1" "rc=$RC out=$MISS_OUT"
[ "$(cat "$F")" = "$BEFORE_APPLY" ] && ok "거부된 apply 는 파일 미변경" || bad "거부된 apply 파일 미변경" "파일이 변경됨"
BLANK_OUT=$("$E" apply "$ID1" --company "카카오" --plan "x" --basis "   " --source "s" 2>&1); RC=$?
[ $RC -eq 1 ] && ok "apply --basis 공백만은 누락 취급(exit 1)" || bad "apply basis 공백 거부" "rc=$RC out=$BLANK_OUT"
NOID_OUT=$("$E" apply exp-nonexistent --company c --plan p --basis b --source s 2>&1); RC=$?
[ $RC -eq 1 ] && has "apply 없는 id 오류(exit 1)" "찾을 수 없습니다" "$NOID_OUT" || bad "apply 없는 id exit 1" "rc=$RC"

# list — 적용 열·푸터·회사 필터
LIST_APPLY=$("$E" list 2>&1)
has "list 헤더에 적용 열" "적용" "$LIST_APPLY"
ROW1=$(grep "$ID1" <<<"$LIST_APPLY")
echo "$ROW1" | grep -qE 'O +- +2' && ok "list 적용 열에 항목 수(2)" || bad "list 적용 열 항목 수" "$ROW1"
has "list 푸터 입사 후 적용 집계" "입사 후 적용 1장" "$LIST_APPLY"
FILTERED=$("$E" list --company "토 스" 2>&1)
has "list --company 정규화 매칭(공백 무시)" "$ID1" "$FILTERED"
hasnt "list --company 는 항목 없는 카드 제외" "$ID2" "$FILTERED"
has "list --company 필터 표시" "회사 필터: 토 스" "$FILTERED"
FILTER_JSON=$("$E" list --json --company 네이버 2>&1)
CHECK2=$(node -e "
const d = JSON.parse(require('fs').readFileSync(0,'utf8'));
const ok = d.company_filter === '네이버' && d.cards.length === 1 && d.cards[0].apply_plans_count === 2
  && d.cards[0].matched_apply_plan && d.cards[0].matched_apply_plan.company === '네이버' && d.with_apply_plans === 1;
console.log(ok ? 'OK' : 'MISMATCH:' + JSON.stringify(d));
" <<<"$FILTER_JSON")
[ "$CHECK2" = "OK" ] && ok "list --json --company 구조(apply_plans_count·matched_apply_plan)" || bad "list --json --company 구조" "$CHECK2"
hasnt "list 표에는 json 키가 새지 않음" "apply_plans_count" "$LIST_APPLY"

# ── validate — 스키마 위반 파일 ───────────────────────────────────────────────
BADFILE="$WORK/bad.yaml"
cat > "$BADFILE" <<'YAML'
- id: exp-bad-id
  title: t
  problem: p
  role: r
  action: a
  change: c
  created_at: "2026-07-01T00:00:00Z"
- id: exp-20260701-01
  title: t2
  problem: p2
  role: r2
  action: a2
  change: c2
  created_at: "not-a-date"
  ai_usage: {tool: "only-tool"}
- id: exp-20260701-01
  title: dup
  problem: p3
  role: r3
  action: a3
  change: c3
  created_at: "2026-07-01T00:00:00Z"
- id: exp-20260701-02
  title: missing-fields
- id: exp-20260701-03
  title: bad-apply
  problem: p
  role: r
  action: a
  change: c
  created_at: "2026-07-01T00:00:00Z"
  apply_plans:
    - company: "토스"
      plan: "p"
      basis: ""
      source: "s"
      created_at: "2026-07-01T00:00:00Z"
    - company: "토 스"
      plan: "p2"
      basis: "b"
      source: "s"
      created_at: "not-a-date"
YAML
BAD_OUT=$("$E" validate "$BADFILE" 2>&1); RC=$?
[ $RC -eq 1 ] && ok "위반 파일 validate exit 1" || bad "위반 파일 validate exit 1" "rc=$RC"
has "validate: id 형식 오류 검출" "id 형식 오류" "$BAD_OUT"
has "validate: created_at 형식 오류 검출" "created_at 형식 오류" "$BAD_OUT"
has "validate: id 중복 검출" "id 중복" "$BAD_OUT"
has "validate: ai_usage 불완전 객체 검출" "ai_usage" "$BAD_OUT"
has "validate: 필수 필드 누락 검출" "필수 필드 누락" "$BAD_OUT"
has "validate: apply_plans basis 공백 검출" "apply_plans\[0\] basis 가 비어 있습니다" "$BAD_OUT"
has "validate: apply_plans 회사 중복(정규화) 검출" "회사 중복" "$BAD_OUT"
has "validate: apply_plans created_at 형식 오류 검출" "apply_plans\[1\] created_at 형식 오류" "$BAD_OUT"

# 최상위가 리스트가 아닌 파일
TOPFILE="$WORK/top.yaml"
echo 'not_a_list: true' > "$TOPFILE"
TOP_OUT=$("$E" validate "$TOPFILE" 2>&1); RC=$?
[ $RC -eq 1 ] && has "최상위 비-리스트 검출" "리스트가 아닙니다" "$TOP_OUT" || bad "최상위 비-리스트 검출" "rc=$RC"

# 빈 파일/부재 상태 -> PASS 0장 (validate 는 상태 디렉토리를 새로 만들지 않는다)
EMPTY_STATE="$WORK/empty-state"
EMPTY_OUT=$(JOBSTACK_STATE_DIR="$EMPTY_STATE" "$E" validate 2>&1); RC=$?
[ $RC -eq 0 ] && has "파일 부재 시 validate PASS 카드 0장" "카드 0장" "$EMPTY_OUT" || bad "파일 부재 validate" "rc=$RC out=$EMPTY_OUT"
[ ! -e "$EMPTY_STATE" ] && ok "validate 는 상태 디렉토리를 생성하지 않음" || bad "validate 가 디렉토리를 생성함(부작용)"

# 우리 스크립트가 만든 정상 파일은 항상 validate 통과
FINAL_VALIDATE=$("$E" validate 2>&1); RC=$?
[ $RC -eq 0 ] && has "정상 파일 최종 validate 통과" "PASS" "$FINAL_VALIDATE" || bad "정상 파일 validate 통과" "rc=$RC out=$FINAL_VALIDATE"

# ── append 롤백 — 손상된 기존 파일에 add 시도 시 원본 미변경 + exit 1 ────────────
CORRUPT_STATE="$WORK/corrupt-state"
mkdir -p "$CORRUPT_STATE/profiles"
CORRUPT_FILE="$CORRUPT_STATE/profiles/experiences.yaml"
printf '%s\n' '- id: exp-1' '  title: [broken' > "$CORRUPT_FILE"
BEFORE=$(cat "$CORRUPT_FILE")
CORRUPT_OUT=$(JOBSTACK_STATE_DIR="$CORRUPT_STATE" "$E" add --title t --problem p --role r --action a --change c 2>&1); RC=$?
AFTER=$(cat "$CORRUPT_FILE")
[ $RC -eq 1 ] && ok "손상 파일에 add 시도 시 exit 1" || bad "손상 파일 add exit 1" "rc=$RC"
[ "$BEFORE" = "$AFTER" ] && ok "손상 파일 add 실패 시 원본 미변경(롤백)" || bad "손상 파일 롤백" "파일이 변경됨: $AFTER"

# ── 기타 ─────────────────────────────────────────────────────────────────
HELP_OUT=$("$E" --help 2>&1); RC=$?
[ $RC -eq 0 ] && has "--help 는 exit 0" "사용법" "$HELP_OUT" || bad "--help exit 0" "rc=$RC"

NOARG_OUT=$("$E" 2>&1); RC=$?
[ $RC -eq 1 ] && has "인자 없이 실행 시 사용법 안내(exit 1)" "사용법" "$NOARG_OUT" || bad "인자 없음 exit 1" "rc=$RC"

BOGUS_OUT=$("$E" bogus-command 2>&1); RC=$?
[ $RC -eq 1 ] && has "알 수 없는 명령 오류(exit 1)" "알 수 없는 명령" "$BOGUS_OUT" || bad "알 수 없는 명령 exit 1" "rc=$RC"

# 한글 라벨 출력에 영문 상태 키가 새지 않는지 — list 표는 O/△/X 판정 기호와 한글 라벨만 노출해야 한다
# (numbers_verdict/ai_usage_present 같은 JSON 내부 키 이름이 사람이 보는 표에 그대로 노출되면 실패)
hasnt "list 사람이 보는 표에 JSON 내부 키 노출 없음(numbers_verdict)" "numbers_verdict" "$LIST_OUT"
hasnt "list 사람이 보는 표에 JSON 내부 키 노출 없음(ai_usage_present)" "ai_usage_present" "$LIST_OUT"

# 상태 디렉토리 밖에는 쓰지 않는다 — add/update 는 항상 JOBSTACK_STATE_DIR 안의 고정 경로에만 쓴다
has "add 결과 경로가 상태 디렉토리 내부" "$JOBSTACK_STATE_DIR/profiles/experiences.yaml" "$OUT"

# 동시 add 20건 → 카드 20장(PR #17 리뷰 반영: 잠금 없는 읽기-수정-쓰기는 lost update — 3장만 남던 재현)
PSTATE="$WORK/state-parallel"
for i in $(seq 1 20); do
  JOBSTACK_STATE_DIR="$PSTATE" "$E" add --title "동시$i" --problem p --role r --action a --change c >/dev/null 2>&1 &
done
wait
PCOUNT=$(grep -c '^- id:' "$PSTATE/profiles/experiences.yaml" 2>/dev/null || echo 0)
[ "$PCOUNT" -eq 20 ] && ok "동시 add 20건 → 카드 20장(잠금)" || bad "동시 add 유실" "count=$PCOUNT"
PUNIQ=$(grep '^- id:' "$PSTATE/profiles/experiences.yaml" 2>/dev/null | sort -u | wc -l | tr -d ' ')
[ "$PUNIQ" -eq 20 ] && ok "동시 add 20건 → id 20개 모두 고유" || bad "동시 add id 중복" "unique=$PUNIQ"
[ ! -e "$PSTATE/profiles/experiences.yaml.lock" ] && ok "완료 후 잠금 파일 정리" || bad "잠금 파일 잔존" "$PSTATE/profiles/experiences.yaml.lock"

rm -rf "$WORK"
echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ] && { echo "[PASS] jobstack-exp"; exit 0; } || { echo "[FAIL] jobstack-exp"; exit 1; }
