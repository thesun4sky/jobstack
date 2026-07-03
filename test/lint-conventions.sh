#!/usr/bin/env bash
# 컨벤션 린트 — CLAUDE.md 컨벤션과 templates/guardrails.md §3·§6을 집행한다.
# 검사 대상: */SKILL.md, templates/*.md, ETHOS.md, CLAUDE.md
# 검사 3종:
#   ① AI 만능 표현 (다각적|포괄적|심층적|혁신적|체계적) — fail
#   ② 금지 표현 (합격 보장|무조건 통과|전문가가 직접 첨삭|AI 대체 불가) — fail
#   ③ 시장 수치 하드코딩 휴리스틱 (*/SKILL.md 한정) — 기본 fail (Council #1),
#      --warn 플래그로 경고만 출력으로 완화
# 예외 처리:
#   - '금지'·'만능'이 든 라인은 ①②에서 제외 (규칙 자체를 인용하는 라인)
#   - 펜스 코드블록(``` ... ```) 내부는 ③에서 제외 (샘플 출력)
#   - 같은 라인에 출처|기준|WebSearch|예:|예시|가중치|반영률|→ 가 있으면 ③에서 제외
#     (교정 예시 표·방법론 상수·목표치)
#   - test/lint-allowlist.txt: `파일경로부분::라인정규식` 형식의 예외 목록
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

run_scan() { # $1=루트 (self-test용 오버라이드)
  local root="$1" f
  for f in "$root"/*/SKILL.md; do
    [ -f "$f" ] && scan_file "$f" 1
  done
  for f in "$root"/templates/*.md "$root/ETHOS.md" "$root/CLAUDE.md"; do
    [ -f "$f" ] && scan_file "$f" 0
  done
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
     && ! echo "$RESULT" | grep -q '85%' \
     && echo "$RESULT" | grep -qE 'salary/SKILL.md:[0-9]+:AI만능표현'; then
    echo "[PASS] self-test — 3종 검출 + 반영률 예외 + 유형 분리(number 예외가 slop 위반 안 숨김) (${HITS}건 검출)"
    exit 0
  else
    echo "[FAIL] self-test — 기대 검출 불일치:"
    echo "$RESULT" | sed 's/^/  /'
    exit 1
  fi
fi

OUTPUT=$(run_scan "$REPO")
# 서브셸에서 카운터가 유실되므로 출력 기반으로 재집계
FAILS=$(echo "$OUTPUT" | grep -cE ':(AI만능표현|금지표현|수치하드코딩):' 2>/dev/null || true)
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
