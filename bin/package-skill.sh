#!/usr/bin/env bash
# package-skill.sh — 스킬을 claude.ai / Cowork 업로드용 zip 으로 묶는다 (U-18).
#
# 포함: <skill>/SKILL.md, <skill>/references/**, <skill>/scripts/preamble.sh
# 제외: bin/, templates/, docs/ — Cowork 에는 저장소가 없으므로 scripts/preamble.sh 는 bin/ 을 찾지 못해
#       최소 컨텍스트(PREAMBLE_FALLBACK=true)를 내고, 스킬은 상단 안내대로 상태 저장·스크립트 단계를 건너뛴다.
#
# 프론트매터: 업로드 경로(claude.ai·Skills API)는 name·description·license·compatibility·metadata·allowed-tools 만 받고
#       그 밖의 키가 있으면 거부한다(skill-creator 의 quick_validate.py 로 실측, 2026-11-10). 그래서 패키지의 SKILL.md 는
#       when_to_use 를 description 뒤에 합치고 argument-hint·model·effort 등 Claude Code 전용 키를 뺀다. 저장소의 SKILL.md 는 그대로다.
#
# 사용법: package-skill.sh <skill|all> [--out <dir>]     (기본 out: <repo>/dist/skills)
# 종료: 0 성공 · 1 인자/스킬 없음 · 2 참조 누락(SKILL.md 가 가리키는 references 파일이 패키지에 없음) · 3 zip 실패
#       · 4 프론트매터 정규화 실패(형식 오류, description 1024자 초과, 꺾쇠 포함)
set -u

SCRIPT_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${JOBSTACK_ROOT:-$(cd -P "$SCRIPT_DIR/.." && pwd)}"
OUT="$ROOT/dist/skills"

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "사용법: package-skill.sh <skill|all> [--out <dir>]" >&2; exit 1; }
shift
while [ $# -gt 0 ]; do
  case "$1" in
    --out)
      [ $# -ge 2 ] || { echo "옵션 --out 에 값이 필요합니다." >&2; exit 1; }
      OUT="$2"; shift 2 ;;
    *) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
  esac
done
mkdir -p "$OUT" || { echo "출력 디렉토리를 만들 수 없습니다: $OUT" >&2; exit 3; }

skill_list() {
  if [ "$TARGET" = all ]; then
    for d in "$ROOT"/*/; do d="${d%/}"; [ -f "$d/SKILL.md" ] && basename "$d"; done
  else
    echo "$TARGET"
  fi
}

# zip 은 있으면 쓰고, 없으면 python3 zipfile 로 대체한다.
make_zip() { # $1=작업 디렉토리(스킬 상위) $2=스킬명 $3=출력 zip
  if command -v zip >/dev/null 2>&1; then
    (cd "$1" && zip -qr "$3" "$2")
  else
    python3 - "$1" "$2" "$3" <<'PY'
import os, sys, zipfile
base, skill, out = sys.argv[1:4]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for root, _, files in os.walk(os.path.join(base, skill)):
        for f in sorted(files):
            p = os.path.join(root, f)
            z.write(p, os.path.relpath(p, base))
PY
  fi
}

# 업로드용 프론트매터 정규화 — 표준 라이브러리만 쓴다(PyYAML 없이 최상위 키 단위로 다룬다).
normalize_frontmatter() { # $1=원본 SKILL.md $2=출력 SKILL.md
  python3 - "$1" "$2" <<'PY'
import re, sys
src, dst = sys.argv[1:3]
text = open(src, encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---\n', text, re.DOTALL)
if not m:
    sys.exit('프론트매터(--- … ---)를 찾지 못했습니다')
body = text[m.end():]
ALLOWED = ['name', 'description', 'license', 'compatibility', 'allowed-tools', 'metadata']
blocks, order, cur = {}, [], None
for line in m.group(1).split('\n'):
    k = re.match(r'^([A-Za-z_][A-Za-z0-9_-]*):(.*)$', line)
    if k:
        cur = k.group(1)
        if cur in blocks:
            sys.exit(f'프론트매터 키 중복: {cur}')
        blocks[cur] = [line]; order.append(cur)
    elif cur is None:
        if line.strip():
            sys.exit(f'프론트매터 첫 줄이 키가 아닙니다: {line!r}')
    else:
        blocks[cur].append(line)

def scalar(key):
    """최상위 키의 문자열 값 — 블록 스칼라(| >)와 한 줄 값을 지원한다."""
    if key not in blocks:
        return ''
    head = blocks[key][0].split(':', 1)[1].strip()
    rest = blocks[key][1:]
    if re.fullmatch(r'[|>][+-]?', head):
        lines = [l for l in rest]
        indent = min((len(l) - len(l.lstrip(' ')) for l in lines if l.strip()), default=0)
        vals = [l[indent:] if l.strip() else '' for l in lines]
        return ('\n' if head[0] == '|' else ' ').join(vals).strip()
    if rest and any(l.strip() for l in rest):
        sys.exit(f'{key}: 한 줄 값 뒤에 이어지는 줄을 해석할 수 없습니다')
    if len(head) >= 2 and head[0] == head[-1] and head[0] in '"\'':
        head = head[1:-1]
    return head.strip()

for req in ('name', 'description'):
    if not scalar(req):
        sys.exit(f'필수 키 없음: {req}')
desc = scalar('description')
when = scalar('when_to_use')
if when:
    desc = desc + '\n' + when
if '<' in desc or '>' in desc:
    sys.exit('description 에 꺾쇠(< >)가 있습니다 — 업로드가 거부됩니다')
if len(desc) > 1024:
    sys.exit(f'description + when_to_use 가 {len(desc)}자입니다 — 업로드 상한 1024자')

out = ['---']
for key in ALLOWED:
    if key == 'description':
        out.append('description: |')
        out += ['  ' + l if l else '' for l in desc.split('\n')]
    elif key in blocks:
        out += blocks[key]
out.append('---')
open(dst, 'w', encoding='utf-8').write('\n'.join(out) + '\n' + body)
dropped = [k for k in order if k not in ALLOWED and k != 'when_to_use']
print('dropped=' + ','.join(dropped) + (' merged=when_to_use' if when else ''))
PY
}

RC=0
for skill in $(skill_list); do
  SRC="$ROOT/$skill"
  if [ ! -f "$SRC/SKILL.md" ]; then echo "[FAIL] $skill: SKILL.md 없음" >&2; RC=1; continue; fi
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/jobstack-pkg.XXXXXX")" || {
    echo "[FAIL] $skill: 임시 작업 디렉토리를 만들 수 없습니다." >&2
    RC=3
    continue
  }
  mkdir -p "$WORK/$skill"
  if ! NORM=$(normalize_frontmatter "$SRC/SKILL.md" "$WORK/$skill/SKILL.md" 2>&1); then
    echo "[FAIL] $skill: 프론트매터 정규화 실패 — $NORM" >&2; RC=4; rm -rf "$WORK"; continue
  fi
  [ -d "$SRC/references" ] && cp -R "$SRC/references" "$WORK/$skill/"
  if [ -d "$SRC/scripts" ]; then mkdir -p "$WORK/$skill/scripts"; cp "$SRC/scripts/preamble.sh" "$WORK/$skill/scripts/" 2>/dev/null || true; fi
  # 참조 무결성: SKILL.md 가 가리키는 references/·scripts/ 경로가 패키지 안에 있어야 한다
  MISSING=0
  for rel in $(grep -oE '\$\{?CLAUDE_SKILL_DIR\}?/[^ `"'"'"')>|,;]*' "$SRC/SKILL.md" | sed -E 's/^\$\{?CLAUDE_SKILL_DIR\}?\///; s/[.:]+$//' | sort -u); do
    [ -e "$WORK/$skill/$rel" ] || { echo "[FAIL] $skill: 패키지에 없는 참조 $rel" >&2; MISSING=1; }
  done
  if [ "$MISSING" = 1 ]; then RC=2; rm -rf "$WORK"; continue; fi
  ZIP="$OUT/$skill.zip"
  rm -f "$ZIP"
  if make_zip "$WORK" "$skill" "$ZIP"; then
    SIZE=$(wc -c < "$ZIP" | tr -d ' ')
    echo "$ZIP ($SIZE bytes)"
  else
    echo "[FAIL] $skill: zip 생성 실패" >&2; RC=3
  fi
  rm -rf "$WORK"
done
exit $RC
