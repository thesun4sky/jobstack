#!/usr/bin/env bash
# 전 스킬의 프리앰블(scripts/preamble.sh → bin/jobstack-preamble)을 격리 실행하고
# 실행 컨텍스트 불변식과 부수효과(상태 디렉토리·env.sh·텔레메트리·세션 정리)를 검증한다.
#
# v0.4.0 부터 프리앰블은 SKILL.md 안의 bash 블록이 아니라 동적 주입 라인
#   !`bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" <skill> "${CLAUDE_SESSION_ID}"`
# 이므로, 이 테스트는 (1) SKILL.md 에 그 라인이 있는지, (2) 옛 인라인 프리앰블이 남아 있지 않은지,
# (3) 스크립트 실행 결과를 검사한다. CLAUDE_SKILL_DIR 는 실경로가 아니라 **심링크 경로**로 주입해
# 심링크 설치(검토 보고서 D-1)를 재현한다.

set -u
# 실경로(-P)로 잡는다(PR #17 리뷰 반영): 프리앰블은 JS_BIN 을 실경로로 출력하므로, macOS 의
# /tmp → /private/tmp 처럼 심링크 아래에서 실행하면 논리 경로 기대값과 어긋나 실패했다.
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
REPO="$(cd -P "$SCRIPT_DIR/.." && pwd)"
SKILLS="auto strategy tracker review retro portfolio ncs salary job-search cover-letter mock-interview resume company-research experience-bank career-history scout-profile"
PASS=0
FAIL=0
FAILED_LIST=()

skill_dir() { # 루트 배치와 skills/ 배치 둘 다 지원
  if [ -d "$REPO/skills/$1" ]; then echo "$REPO/skills/$1"; else echo "$REPO/$1"; fi
}

old_timestamp() { # 13시간 전 (GNU date → BSD date 폴백), touch -t 형식
  date -u -d '-13 hours' +%Y%m%d%H%M 2>/dev/null || date -u -v-13H +%Y%m%d%H%M
}

for s in $SKILLS; do
  DIR="$(skill_dir "$s")"
  SKILL_FILE="$DIR/SKILL.md"
  [ -f "$SKILL_FILE" ] || { echo "[SKIP] $s — file missing"; continue; }
  errors=()

  # (a) SKILL.md 계약: 동적 주입 라인 존재, 가드레일 주입 존재, 옛 인라인 프리앰블 부재
  # v0.5.0: 세 번째 인자 "${CLAUDE_PLUGIN_DATA:-}" (플러그인 데이터 디렉토리) 가 붙는다
  grep -qF '!`bash "${CLAUDE_SKILL_DIR}/scripts/preamble.sh" '"$s"' "${CLAUDE_SESSION_ID}" "${CLAUDE_PLUGIN_DATA:-}"`' "$SKILL_FILE" \
    || errors+=("missing !\`preamble.sh $s\` injection line")
  grep -qF '"${CLAUDE_SKILL_DIR}/references/guardrails.md"' "$SKILL_FILE" \
    || errors+=("missing guardrails.md injection")
  grep -q '^# ─── jobstack 프리앰블' "$SKILL_FILE" && errors+=("legacy inline preamble still present")
  grep -q 'CLAUDE_SKILL_DIR}\?/\.\./' "$SKILL_FILE" && errors+=("'\${CLAUDE_SKILL_DIR}/../' reference remains (breaks under symlink install)")

  [ -x "$DIR/scripts/preamble.sh" ] || errors+=("scripts/preamble.sh missing or not executable")

  # (b) 격리 실행 — 심링크 경로로 CLAUDE_SKILL_DIR 주입
  WORK=$(mktemp -d "${TMPDIR:-/tmp}/jobstack-test.XXXXXX")
  STATE="$WORK/state"
  mkdir -p "$WORK/skills" "$STATE/sessions"
  ln -s "$DIR" "$WORK/skills/$s"
  echo old > "$STATE/sessions/stale-session"
  touch -t "$(old_timestamp)" "$STATE/sessions/stale-session"

  OUTPUT=$(
    cd "$WORK" && \
    JOBSTACK_STATE_DIR="$STATE" CLAUDE_SKILL_DIR="$WORK/skills/$s" JOBSTACK_NPM_AUTO_INSTALL=0 \
    bash "$WORK/skills/$s/scripts/preamble.sh" "$s" "test-session-$$" 2>&1
  )
  EXIT=$?
  [ $EXIT -eq 0 ] || errors+=("exit=$EXIT")

  echo "$OUTPUT" | grep -qE "^PROACTIVE=(true|false)$" || errors+=("PROACTIVE not true|false")
  echo "$OUTPUT" | grep -qE "^ACTIVE_SESSIONS=[0-9]+$" || errors+=("missing ACTIVE_SESSIONS")
  echo "$OUTPUT" | grep -q "^SKILL_NAME=$s\$" || errors+=("missing SKILL_NAME=$s")
  echo "$OUTPUT" | grep -q "^JOBSTACK_RUNTIME=cli$" || errors+=("JOBSTACK_RUNTIME should be cli")
  echo "$OUTPUT" | grep -q "^JS_BIN=$REPO/bin$" || errors+=("JS_BIN not resolved to repo bin through symlink: $(echo "$OUTPUT" | grep '^JS_BIN=' | head -1)")
  echo "$OUTPUT" | grep -q "^JS_STATE=$STATE$" || errors+=("JS_STATE not the injected state dir")
  echo "$OUTPUT" | grep -q "^TODAY_KST=[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}$" || errors+=("missing TODAY_KST")
  echo "$OUTPUT" | grep -q "PREAMBLE_FALLBACK=true" && errors+=("fallback path taken — bin/jobstack-preamble not found")
  case "$s" in
    job-search|company-research|salary)
      echo "$OUTPUT" | grep -qE "^BROWSER_SCRAPER_AVAILABLE=(true|false)$" || errors+=("missing BROWSER_SCRAPER_AVAILABLE")
      echo "$OUTPUT" | grep -qE "^IS_FETCH_AVAILABLE=(true|false)$" || errors+=("missing IS_FETCH_AVAILABLE")
      ;;
  esac

  # (c) 부수효과: 상태 디렉토리, env.sh, 텔레메트리, 세션 파일·stale 정리
  for d in analytics profiles tracker company-cache interview-history sessions defense-maps job-cache; do
    [ -d "$STATE/$d" ] || errors+=("missing dir: $d")
  done
  if [ -f "$STATE/env.sh" ]; then
    # JOBSTACK_STATE_DIR 는 export 되어야 한다 — bin 스크립트(Node·Python)가 이 값만 보므로(PR #18 리뷰)
    ENV_CHECK=$(env -u JOBSTACK_STATE_DIR bash -c ". '$STATE/env.sh' && echo \"\$_JS_STATE|\$_JS_BIN|\$TODAY|\$JOBSTACK_RUNTIME|\$JOBSTACK_STATE_DIR|\$(printenv JOBSTACK_STATE_DIR)\"" 2>&1)
    [ "$ENV_CHECK" = "$STATE|$REPO/bin|$(TZ=Asia/Seoul date +%Y-%m-%d)|cli|$STATE|$STATE" ] || errors+=("env.sh values wrong: $ENV_CHECK")
  else
    errors+=("env.sh not written")
  fi
  grep -q "\"skill\":\"$s\"" "$STATE/analytics/skill-usage.jsonl" 2>/dev/null || errors+=("telemetry entry missing")
  grep -q "\"session\":\"test-session-$$\"" "$STATE/analytics/skill-usage.jsonl" 2>/dev/null || errors+=("telemetry session field missing")
  [ -e "$STATE/sessions/stale-session" ] && errors+=("stale session file not swept")
  [ -e "$STATE/sessions/test-session-$$" ] || errors+=("session file not created")

  # (d) 봇 런타임 판정
  BOT_OUT=$(JOBSTACK_STATE_DIR="$STATE" CLAUDE_SKILL_DIR="$WORK/skills/$s" JOBCLAW_RUN_ID="run-1" JOBSTACK_NPM_AUTO_INSTALL=0 \
            bash "$WORK/skills/$s/scripts/preamble.sh" "$s" 2>&1)
  echo "$BOT_OUT" | grep -q "^JOBSTACK_RUNTIME=bot$" || errors+=("JOBCLAW_RUN_ID did not switch runtime to bot")

  rm -rf "$WORK"

  if [ ${#errors[@]} -eq 0 ]; then
    PASS=$((PASS+1))
    printf "[PASS] %-18s  %s\n" "$s" "$(echo "$OUTPUT" | grep -E '^(ACTIVE_SESSIONS|JOBSTACK_RUNTIME)=' | tr '\n' ' ')"
  else
    FAIL=$((FAIL+1))
    FAILED_LIST+=("$s")
    printf "[FAIL] %-18s  errors: %s\n" "$s" "${errors[*]}"
    echo "  ---- output (last 12 lines) ----"
    echo "$OUTPUT" | tail -12 | sed 's/^/    /'
    echo "  --------------------------------"
  fi
done

# (e) 폴백 경로: bin/ 이 없는 복사본 설치에서도 최소 컨텍스트를 낸다
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jobstack-test.XXXXXX")
mkdir -p "$WORK/lonely/scripts"
cp "$REPO/templates/skill-preamble.sh" "$WORK/lonely/scripts/preamble.sh"
FB=$(cd "$WORK" && HOME="$WORK/home" JOBSTACK_STATE_DIR="$WORK/state" bash "$WORK/lonely/scripts/preamble.sh" lonely 2>&1)
if echo "$FB" | grep -q "^PREAMBLE_FALLBACK=true$" && echo "$FB" | grep -q "^SKILL_NAME=lonely$" && echo "$FB" | grep -qE "^PROACTIVE=(true|false)$"; then
  PASS=$((PASS+1)); echo "[PASS] fallback (no bin/)"
else
  FAIL=$((FAIL+1)); FAILED_LIST+=("fallback"); echo "[FAIL] fallback (no bin/)"; echo "$FB" | tail -8 | sed 's/^/    /'
fi
rm -rf "$WORK"

# (f) 상태 디렉토리를 만들 수 없어도 exit 0 이고 STATE_WRITE_FAILED=true 마커를 낸다 (리뷰 반영)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jobstack-test.XXXXXX")
touch "$WORK/notdir"
WF=$(JOBSTACK_STATE_DIR="$WORK/notdir/state" bash "$REPO/bin/jobstack-preamble" auto 2>/dev/null); WF_RC=$?
if [ "$WF_RC" -eq 0 ] && echo "$WF" | grep -q "^STATE_WRITE_FAILED=true$" && echo "$WF" | grep -q "^주의: 상태 디렉토리"; then
  PASS=$((PASS+1)); echo "[PASS] unwritable state dir → exit 0 + STATE_WRITE_FAILED=true"
else
  FAIL=$((FAIL+1)); FAILED_LIST+=("unwritable-state"); echo "[FAIL] unwritable state dir (rc=$WF_RC)"; echo "$WF" | tail -8 | sed 's/^/    /'
fi
rm -rf "$WORK"

# (g) 플러그인 설치: PLUGIN_DATA/node/node_modules 가 있으면 bin/node_modules 심링크를 만들고 env.sh 에 JOBSTACK_PLUGIN_DATA 를 적는다 (U-07)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jobstack-test.XXXXXX")
mkdir -p "$WORK/plug/bin" "$WORK/pdata/node/node_modules/playwright" "$WORK/state"
cp "$REPO/bin/jobstack-preamble" "$REPO/bin/package.json" "$WORK/plug/bin/" && touch "$WORK/plug/bin/fetch-jobs.mjs"
PG=$(JOBSTACK_STATE_DIR="$WORK/state" JOBSTACK_NPM_AUTO_INSTALL=0 bash "$WORK/plug/bin/jobstack-preamble" job-search "" "$WORK/pdata" 2>/dev/null)
if [ -L "$WORK/plug/bin/node_modules" ] && echo "$PG" | grep -q "^BROWSER_SCRAPER_AVAILABLE=true$" && grep -q "^JOBSTACK_PLUGIN_DATA=" "$WORK/state/env.sh"; then
  PASS=$((PASS+1)); echo "[PASS] plugin data dir → bin/node_modules symlink + JOBSTACK_PLUGIN_DATA"
else
  FAIL=$((FAIL+1)); FAILED_LIST+=("plugin-data"); echo "[FAIL] plugin data dir"; echo "$PG" | tail -8 | sed 's/^/    /'
fi
rm -rf "$WORK"

echo
echo "===================="
echo "PASS: $PASS / FAIL: $FAIL"
if [ $FAIL -eq 0 ]; then
  echo "ALL GREEN"
  exit 0
else
  echo "FAILED: ${FAILED_LIST[*]}"
  exit 1
fi
