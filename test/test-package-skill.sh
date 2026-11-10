#!/usr/bin/env bash
# test-package-skill.sh — claude.ai/Cowork 업로드 패키지(U-18) 검증.
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
BIN="${JOBSTACK_PACKAGE_BIN:-$REPO/bin/package-skill.sh}"
PASS=0; FAIL=0
ok() { PASS=$((PASS+1)); echo "  [PASS] $1"; }
ng() { FAIL=$((FAIL+1)); echo "  [FAIL] $1"; }
WORK=$(mktemp -d "${TMPDIR:-/tmp}/jobstack-pkgtest.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

list_zip() { python3 -c "import sys,zipfile; print('\n'.join(zipfile.ZipFile(sys.argv[1]).namelist()))" "$1"; }

echo "## package-skill"
# 1. 단일 스킬
if OUTP=$(bash "$BIN" auto --out "$WORK/out" 2>&1) && [ -f "$WORK/out/auto.zip" ]; then ok "auto.zip 생성"; else ng "auto.zip 생성: $OUTP"; fi
NAMES=$(list_zip "$WORK/out/auto.zip" 2>/dev/null || true)
echo "$NAMES" | grep -q '^auto/SKILL.md$' && ok "SKILL.md 포함" || ng "SKILL.md 누락"
echo "$NAMES" | grep -q '^auto/references/guardrails.md$' && ok "references/guardrails.md 포함" || ng "guardrails 누락"
echo "$NAMES" | grep -q '^auto/scripts/preamble.sh$' && ok "scripts/preamble.sh 포함" || ng "preamble.sh 누락"
echo "$NAMES" | grep -q '^auto/references/cases.md$' && ok "스킬 소유 references 포함" || ng "스킬 소유 references 누락"
echo "$NAMES" | grep -qE '^auto/(bin|templates|docs)/' && ng "bin/templates/docs 가 섞임" || ok "bin/templates/docs 제외"

# 2. 전체 스킬
if bash "$BIN" all --out "$WORK/all" >/dev/null 2>&1; then
  N=$(ls "$WORK/all"/*.zip 2>/dev/null | wc -l | tr -d ' ')
  [ "$N" -ge 16 ] && ok "all → zip ${N}개" || ng "all → zip ${N}개(16 미만)"
else ng "all 실행 실패"; fi

# 3. 없는 스킬 → exit 1
bash "$BIN" no-such-skill --out "$WORK/x" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 1 ] && ok "없는 스킬 exit 1" || ng "없는 스킬 exit $RC"

# 4. 참조 누락 → exit 2 (가짜 저장소)
mkdir -p "$WORK/fake/broken/scripts" "$WORK/fake/bin"
cp "$BIN" "$WORK/fake/bin/package-skill.sh"
printf -- '---\nname: broken\ndescription: 참조 누락 픽스처\n---\n`${CLAUDE_SKILL_DIR}/references/missing.md` 를 Read\n' > "$WORK/fake/broken/SKILL.md"
touch "$WORK/fake/broken/scripts/preamble.sh"
JOBSTACK_ROOT="$WORK/fake" bash "$WORK/fake/bin/package-skill.sh" broken --out "$WORK/fake/out" >/dev/null 2>&1; RC=$?
[ "$RC" -eq 2 ] && ok "참조 누락 exit 2" || ng "참조 누락 exit $RC"

# 5. 폴백 컨텍스트: 패키지만 풀어놓은 환경에서 preamble.sh 가 PREAMBLE_FALLBACK=true 를 낸다
mkdir -p "$WORK/unpacked" && (cd "$WORK/unpacked" && python3 -c "import zipfile; zipfile.ZipFile('$WORK/out/auto.zip').extractall('.')")
FB=$(cd "$WORK/unpacked" && HOME="$WORK/home" JOBSTACK_STATE_DIR="$WORK/state" bash auto/scripts/preamble.sh auto 2>/dev/null)
echo "$FB" | grep -q '^PREAMBLE_FALLBACK=true$' && ok "패키지 단독 실행 → 폴백 컨텍스트" || ng "폴백 컨텍스트 없음"

# 6. --out 값 누락(마지막 인자) → exit 1 (무한 루프 방지: timeout 으로 감싸 판정)
if command -v timeout >/dev/null 2>&1; then
  timeout 5 bash "$BIN" auto --out >/dev/null 2>&1; RC=$?
else
  bash "$BIN" auto --out >/dev/null 2>&1; RC=$?
fi
if [ "$RC" -eq 1 ]; then
  ok "--out 값 누락 → exit 1"
elif [ "$RC" -eq 124 ]; then
  ng "--out 값 누락: timeout(무한 루프로 추정)"
else
  ng "--out 값 누락 exit $RC"
fi

# ── 업로드용 프론트매터 정규화 (N-05) ─────────────────────────────────────
# 업로드 경로는 name·description·license·compatibility·metadata·allowed-tools 만 받는다.
FM_OUT=$(python3 - "$WORK/all" "$REPO" <<'PY' 2>&1
import os, re, sys, zipfile
out, repo = sys.argv[1:3]
ALLOWED = {'name', 'description', 'license', 'compatibility', 'metadata', 'allowed-tools'}
bad, n = [], 0
def split(text):
    m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
    return (m.group(1), text[m.end():]) if m else (None, None)
for z in sorted(f for f in os.listdir(out) if f.endswith('.zip')):
    skill = z[:-4]; n += 1
    fm, body = split(zipfile.ZipFile(os.path.join(out, z)).read(f'{skill}/SKILL.md').decode('utf-8'))
    sfm, sbody = split(open(os.path.join(repo, skill, 'SKILL.md'), encoding='utf-8').read())
    if fm is None:
        bad.append(f'{skill}: 프론트매터 없음'); continue
    keys = re.findall(r'^([A-Za-z_][A-Za-z0-9_-]*):', fm, re.M)
    extra = sorted(set(keys) - ALLOWED)
    if extra: bad.append(f'{skill}: 허용되지 않는 키 {extra}')
    if len(keys) != len(set(keys)): bad.append(f'{skill}: 키 중복')
    if 'name' not in keys or 'description' not in keys: bad.append(f'{skill}: name/description 누락')
    if not re.search(rf'^name: {re.escape(skill)}$', fm, re.M): bad.append(f'{skill}: name 불일치')
    d = re.search(r'^description: \|\n((?:(?:  .*)?\n?)+?)(?=^[A-Za-z_]|\Z)', fm + '\n', re.M)
    desc = '\n'.join(l[2:] for l in d.group(1).rstrip('\n').split('\n')) if d else ''
    if not desc: bad.append(f'{skill}: description 비어 있음')
    if len(desc) > 1024: bad.append(f'{skill}: description {len(desc)}자')
    if '<' in desc or '>' in desc: bad.append(f'{skill}: description 에 꺾쇠')
    # when_to_use 가 버려지지 않고 description 에 합쳐졌는지 — 원본 when_to_use 첫 줄이 들어 있어야 한다
    w = re.search(r'^when_to_use: \|\n  (.+)$', sfm, re.M)
    if w and w.group(1).strip() not in desc: bad.append(f'{skill}: when_to_use 가 description 에 합쳐지지 않음')
    for k in ('allowed-tools', 'metadata'):
        if re.search(rf'^{k}:', sfm, re.M) and not re.search(rf'^{k}:', fm, re.M): bad.append(f'{skill}: {k} 유실')
    if body != sbody: bad.append(f'{skill}: 본문이 원본과 다름')
print(f'checked={n}')
print('\n'.join(bad))
sys.exit(1 if bad or n < 16 else 0)
PY
); FM_RC=$?
[ "$FM_RC" -eq 0 ] && ok "16개 zip 프론트매터 — 허용 키만·when_to_use 병합·본문 보존" || ng "프론트매터 정규화: $FM_OUT"
grep -q '^when_to_use:' "$REPO/resume/SKILL.md" && grep -q '^argument-hint:' "$REPO/resume/SKILL.md" \
  && ok "저장소 SKILL.md 는 Claude Code 전용 키를 그대로 유지" || ng "저장소 SKILL.md 의 when_to_use·argument-hint 가 사라짐"

# 정규화 실패 → exit 4 (description + when_to_use 1024자 초과, 꺾쇠)
mkdir -p "$WORK/fmroot/longdesc/references" "$WORK/fmroot/angle/references"
{ printf -- '---\nname: longdesc\ndescription: |\n  짧은 설명\nwhen_to_use: |\n  '; head -c 1100 /dev/zero | tr '\0' 'a'; printf '\n---\n\n본문\n'; } > "$WORK/fmroot/longdesc/SKILL.md"
printf -- '---\nname: angle\ndescription: |\n  <회사명> 을 넣는다\n---\n\n본문\n' > "$WORK/fmroot/angle/SKILL.md"
for fx in longdesc angle; do
  JOBSTACK_ROOT="$WORK/fmroot" bash "$BIN" "$fx" --out "$WORK/fmout" >/dev/null 2>&1; RC=$?
  [ "$RC" -eq 4 ] && [ ! -f "$WORK/fmout/$fx.zip" ] && ok "정규화 실패($fx) → exit 4, zip 미생성" || ng "정규화 실패($fx) exit $RC"
done

echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
