#!/usr/bin/env bash
# 컨벤션 린트 — CLAUDE.md 컨벤션과 templates/guardrails.md §3·§6을 집행한다.
# 검사 대상: */SKILL.md, templates/*.md, ETHOS.md, CLAUDE.md, */references/**/*.md(①②만)
# 검사 3종:
#   ① AI 만능 표현 (다각적|포괄적|심층적|혁신적|체계적) — fail
#   ② 금지 표현 (합격 보장|무조건 통과|전문가가 직접 첨삭|AI 대체 불가) — fail
#   ③ 시장 수치 하드코딩 휴리스틱 (*/SKILL.md 한정) — 기본 fail (Council #1),
#      --warn 플래그로 경고만 출력으로 완화
#   ④ 검색어 예시의 고정 연도 (*/SKILL.md, templates/**/*.md, */references/**/*.md, agents/*.md) — fail
#      해가 바뀌면 낡은 검색을 하게 되므로 "[현재 연도]"·`CURRENT_YEAR` 로 쓴다. 검출하는 자리:
#        (a) 따옴표·백틱으로 감싼 구간 안의 연도 — 구간 단위로 본다("2026년"·"2026-2027" 포함)
#        (b) 검색 문맥 줄(WebSearch|검색어|검색 쿼리|쿼리 예시|site:)의 인용부호 없는 연도
#        (c) 펜스 코드블록 안의 단독 연도("2026년" 은 출력 예시로 보고 제외)
#        (d) 연도로 끝나는 목록 항목 (`- 대기업 신입 수시채용 비중 2026`)
#      제외: 날짜(2026-03-28, 2026.03, 2026/03), 표준 번호 뒤 연도(27001:2022),
#            출처 표기(기준|출처|조사|고시|보도|확인일 — 구간 안 또는 (b)(c)(d)는 줄 안),
#            검색 문맥이 아닌 줄의 사용자 입력 예시("예:" 가 있는 줄)
#      한계: 인용부호도 검색 문맥도 없는 본문 문장 속 연도는 보지 않는다(사실 서술과 구분할 수 없다).
# 예외 처리:
#   - '금지'·'만능'이 든 라인은 ①②에서 제외 (규칙 자체를 인용하는 라인)
#   - 펜스 코드블록(``` ... ```) 내부는 ③에서 제외 (샘플 출력)
#   - 같은 라인에 출처|기준|WebSearch|예:|예시|가중치|반영률|→ 가 있으면 ③에서 제외
#     (교정 예시 표·방법론 상수·목표치)
#   - test/lint-allowlist.txt: `파일경로부분::검사종류::라인정규식` 형식의 예외 목록 (검사종류: slop|banned|number|year)
# 사용법: lint-conventions.sh [--warn] [--self-test]

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
ALLOW="$SCRIPT_DIR/lint-allowlist.txt"

MODE="strict"
SELF_TEST=""
for arg in "$@"; do
  case "$arg" in
    --warn) MODE="warn" ;;
    --self-test) SELF_TEST="1" ;;
  esac
done

RE_SLOP='다각적|포괄적|심층적|혁신적|체계적'
RE_BANNED='합격 보장|무조건 통과|전문가가 직접 첨삭|AI 대체 불가'
RE_NUMBER='[0-9]+(\.[0-9]+)?%|[0-9][0-9,]*만원'
RE_NUM_EXEMPT='출처|기준|WebSearch|예:|예시|가중치|반영률|→'
RE_QUOTE_EXEMPT='금지|만능'
FAIL_COUNT=0
WARN_COUNT=0

is_allowed() { # $1=파일경로 $2=라인내용 $3=검사종류(slop|banned|number)
  # allowlist 형식: 파일경로부분::검사종류::라인정규식
  # 검사 종류를 분리해, 수치(number) 예외가 AI만능(slop)·금지(banned) 위반까지
  # 숨기는 것을 방지한다.
  local file="$1" content="$2" kind="$3" entry fsub ekind pat rest
  [ -f "$ALLOW" ] || return 1
  while IFS= read -r entry; do
    case "$entry" in ''|'#'*) continue ;; esac
    fsub="${entry%%::*}"
    rest="${entry#*::}"
    ekind="${rest%%::*}"
    pat="${rest#*::}"
    [ "$ekind" = "$kind" ] || continue
    if [[ "$file" == *"$fsub"* ]] && echo "$content" | grep -qE "$pat"; then
      return 0
    fi
  done < "$ALLOW"
  return 1
}

# 펜스 코드블록 밖의 라인만 "라인번호:내용"으로 출력
outside_fences() { # $1=file
  awk '
    /^[[:space:]]*```/ { fence = !fence; next }
    !fence { printf "%d:%s\n", NR, $0 }
  ' "$1"
}

scan_file() { # $1=file $2=check3여부(1|0)
  local file="$1" check3="$2" lineno content rest rel
  rel="${file#"$REPO"/}"
  while IFS= read -r rest; do
    lineno="${rest%%:*}"
    content="${rest#*:}"

    # ① AI 만능 표현 / ② 금지 표현 (규칙 인용 라인 제외)
    if ! echo "$content" | grep -qE "$RE_QUOTE_EXEMPT"; then
      if echo "$content" | grep -qE "$RE_SLOP" && ! is_allowed "$rel" "$content" slop; then
        echo "$rel:$lineno:AI만능표현:$(echo "$content" | grep -oE "$RE_SLOP" | head -1)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
      if echo "$content" | grep -qE "$RE_BANNED" && ! is_allowed "$rel" "$content" banned; then
        echo "$rel:$lineno:금지표현:$(echo "$content" | grep -oE "$RE_BANNED" | head -1)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    fi

    # ③ 시장 수치 하드코딩 (SKILL.md 한정)
    if [ "$check3" = "1" ] \
       && echo "$content" | grep -qE "$RE_NUMBER" \
       && ! echo "$content" | grep -qE "$RE_NUM_EXEMPT" \
       && ! is_allowed "$rel" "$content" number; then
      if [ "$MODE" = "warn" ]; then
        echo "$rel:$lineno:수치하드코딩(warn):$(echo "$content" | grep -oE "$RE_NUMBER" | head -1)"
        WARN_COUNT=$((WARN_COUNT + 1))
      else
        echo "$rel:$lineno:수치하드코딩:$(echo "$content" | grep -oE "$RE_NUMBER" | head -1)"
        FAIL_COUNT=$((FAIL_COUNT + 1))
      fi
    fi
  done < <(outside_fences "$file")
}

# ④ 판정기 — "상대경로<TAB>줄번호<TAB>연도<TAB>줄 내용" 을 출력한다.
scan_years() { # $1=루트
  python3 - "$1" <<'PY'
import glob, os, re, sys
root = sys.argv[1]
files = []
for pat in ('*/SKILL.md', 'templates/*.md', 'templates/*/*.md', 'agents/*.md'):
    files += glob.glob(os.path.join(root, pat))
for d in glob.glob(os.path.join(root, '*/references')):
    for dp, _, fs in os.walk(d):
        files += [os.path.join(dp, f) for f in fs if f.endswith('.md')]
DATE = re.compile(r'20[2-9]\d[-./](?:0[1-9]|1[0-2])(?!\d)(?:[-./][0-3]\d(?!\d))?')
YEAR = re.compile(r'(?<![\d:])(20[2-9]\d)(?!\d)')
YEAR_NOT_NYEON = re.compile(r'(?<![\d:])(20[2-9]\d)(?![\d년])')
SPAN = re.compile(r'`([^`]*)`|"([^"]*)"|“([^”]*)”|(?<![\w])\'([^\']{4,})\'')
EXEMPT = re.compile(r'기준|출처|조사|고시|보도|확인일')
SEARCH = re.compile(r'WebSearch|검색어|검색 쿼리|쿼리 예시|site:')
LIST_TAIL = re.compile(r'^\s*(?:>\s*)?[-*]\s.*?(?<![\d:])(20[2-9]\d)\s*`?\s*$')
for path in sorted(set(files)):
    rel = os.path.relpath(path, root)
    fence = False
    try:
        lines = open(path, encoding='utf-8').read().split('\n')
    except (OSError, UnicodeDecodeError):
        continue
    for no, raw in enumerate(lines, 1):
        if re.match(r'^\s*```', raw):
            fence = not fence
            continue
        if '20' not in raw:
            continue
        line = DATE.sub('DATE', raw)
        hit = None
        search_ctx = bool(SEARCH.search(line))
        user_example = ('예:' in line or '(예' in line) and not search_ctx
        if not user_example:
            for m in SPAN.finditer(line):                       # (a)
                span = next(g for g in m.groups() if g is not None)
                if EXEMPT.search(span):
                    continue
                y = YEAR.search(span)
                if y:
                    hit = y.group(1); break
        if hit is None and not EXEMPT.search(line):
            unq = SPAN.sub(' ', line)
            if search_ctx:                                      # (b)
                y = YEAR.search(unq)
                hit = y.group(1) if y else None
            if hit is None and fence:                           # (c)
                y = YEAR_NOT_NYEON.search(line)
                hit = y.group(1) if y else None
            if hit is None and not user_example:                # (d)
                y = LIST_TAIL.match(line)
                hit = y.group(1) if y else None
        if hit:
            print(f'{rel}\t{no}\t{hit}\t{raw}')
PY
}

run_scan() { # $1=루트 (self-test용 오버라이드)
  local root="$1" f
  for f in "$root"/*/SKILL.md; do
    [ -f "$f" ] && scan_file "$f" 1
  done
  for f in "$root"/templates/*.md "$root/ETHOS.md" "$root/CLAUDE.md"; do
    [ -f "$f" ] && scan_file "$f" 0
  done
  # 스킬 참조 자료(*/references/**/*.md — 분할된 정적 자료와 docs/ 복제본)도 ①② 대상 (v0.5.0 U-08).
  # 파일이 많아(150개+) 줄 단위 루프 대신 grep 한 번으로 훑는다(펜스 안·규칙 인용 줄은 제외).
  local hit rel lineno content year
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    f="${hit%%:*}"; rel="${f#$root/}"
    lineno="$(echo "$hit" | cut -d: -f2)"; content="$(echo "$hit" | cut -d: -f3-)"
    echo "$content" | grep -qE "$RE_QUOTE_EXEMPT" && continue
    if echo "$content" | grep -qE "$RE_SLOP" && ! is_allowed "$rel" "$content" slop; then
      echo "$rel:$lineno:AI만능표현:$(echo "$content" | grep -oE "$RE_SLOP" | head -1)"; FAIL_COUNT=$((FAIL_COUNT + 1))
    elif echo "$content" | grep -qE "$RE_BANNED" && ! is_allowed "$rel" "$content" banned; then
      echo "$rel:$lineno:금지표현:$(echo "$content" | grep -oE "$RE_BANNED" | head -1)"; FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  done < <(find "$root"/*/references -type f -name '*.md' 2>/dev/null | sort \
           | xargs -r awk 'FNR==1{fence=0} /^[[:space:]]*```/{fence=!fence; next} !fence{print FILENAME":"FNR":"$0}' 2>/dev/null \
           | grep -E "$RE_SLOP|$RE_BANNED" || true)

  # ④ 검색어 예시의 고정 연도 — 판정은 scan_years(파이썬)가 하고, 여기서는 allowlist 만 적용한다
  while IFS= read -r hit; do
    [ -n "$hit" ] || continue
    rel="$(echo "$hit" | cut -f1)"; lineno="$(echo "$hit" | cut -f2)"; year="$(echo "$hit" | cut -f3)"; content="$(echo "$hit" | cut -f4-)"
    is_allowed "$rel" "$content" year && continue
    echo "$rel:$lineno:고정연도검색어:$year"; FAIL_COUNT=$((FAIL_COUNT + 1))
  done < <(scan_years "$root")
}

if [ -n "$SELF_TEST" ]; then
  # 픽스처: 위반이 든 가짜 스킬로 검출 자체를 검증
  TMP=$(mktemp -d)
  mkdir -p "$TMP/fake-skill" "$TMP/salary" "$TMP/templates"
  cat > "$TMP/fake-skill/SKILL.md" <<'FIXTURE'
포괄적 분석을 제공합니다.
합격 보장을 약속합니다.
국내 기업의 도입률은 87.3%에 달합니다.
반영률 목표는 85%+ 입니다.
검색 쿼리: `대기업 신입 채용 동향 2031`
지난 분석은 2031-03-28 에 했고 2031년 상반기 목표입니다.
인용 형식: "(경총 500개사 조사, 2031 기준)"
`2033 상반기 공채` 를 찾는다.
WebSearch("삼성전자 신입 채용 2034년 하반기")
`네이버 채용 2035-2036 일정`
'대기업 수시채용 비중 2037'
> - 대기업 신입 수시채용 비중 2038
검색어: 대기업 신입 공채 2039 하반기
`[기업명] CEO 신년사 2040` (출처 병기)
`ISO 27001:2022` 인증 경험, 보안 표준은 2022 개정판
예: "OO대학교 컴퓨터공학과 2025 졸업"
`jobstack-tracker list` 는 2026 이후 `--since` 를 받는다
```
site:example.com "{직무}" 2032
"{기업명}" 신년사 2041
출력 예시: 2042년 상반기 · 기준일: 2042-04-01
```
FIXTURE
  # 유형 분리 검증: 'number' allowlist('성과급')에 걸리는 라인이라도
  # 그 라인의 slop 위반('다각적')은 여전히 검출돼야 한다.
  cat > "$TMP/salary/SKILL.md" <<'FIXTURE2'
성과급 제도는 다각적으로 운영됩니다.
FIXTURE2
  REPO_SAVE="$REPO"; REPO="$TMP"
  RESULT=$(run_scan "$TMP")
  REPO="$REPO_SAVE"
  rm -rf "$TMP"
  HITS=$(echo "$RESULT" | grep -c ':' || true)
  if echo "$RESULT" | grep -q 'AI만능표현' \
     && echo "$RESULT" | grep -q '금지표현' \
     && echo "$RESULT" | grep -q '수치하드코딩' \
     && [ "$(echo "$RESULT" | grep '고정연도검색어' | sed 's/.*://' | sort | tr '\n' ' ')" = "2031 2032 2033 2034 2035 2037 2038 2039 2040 2041 " ] \
     && ! echo "$RESULT" | grep -q '85%' \
     && echo "$RESULT" | grep -qE 'salary/SKILL.md:[0-9]+:AI만능표현'; then
    echo "[PASS] self-test — 4종 검출(고정 연도 검색어 10형태 검출 · 날짜·출처·표준번호·입력 예시·인접 구간 5형태 제외) + 반영률 예외 + 유형 분리(number 예외가 slop 위반 안 숨김) (${HITS}건 검출)"
    exit 0
  else
    echo "[FAIL] self-test — 기대 검출 불일치:"
    echo "$RESULT" | sed 's/^/  /'
    exit 1
  fi
fi

OUTPUT=$(run_scan "$REPO")
# 서브셸에서 카운터가 유실되므로 출력 기반으로 재집계
FAILS=$(echo "$OUTPUT" | grep -cE ':(AI만능표현|금지표현|수치하드코딩|고정연도검색어):' 2>/dev/null || true)
WARNS=$(echo "$OUTPUT" | grep -c ':수치하드코딩(warn):' 2>/dev/null || true)

if [ -n "$OUTPUT" ]; then
  echo "$OUTPUT" | sed 's/^/  /'
fi

if [ "${FAILS:-0}" -gt 0 ]; then
  echo "[FAIL] 컨벤션 위반 ${FAILS}건 (경고 ${WARNS:-0}건) — templates/guardrails.md §3·§6 참조"
  echo "  의도된 예외라면 test/lint-allowlist.txt에 '파일경로부분::검사종류::라인정규식' 형식으로 추가하세요"
  exit 1
fi
echo "[PASS] 컨벤션 린트 통과 (경고 ${WARNS:-0}건)"
exit 0
