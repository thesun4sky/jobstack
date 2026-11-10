#!/usr/bin/env bash
# bin/release.sh 의 검사·릴리스 노트 추출을 --dry-run 으로 검증한다(태그·릴리스는 만들지 않는다).
set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
R="$REPO/bin/release.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "  [PASS] $1"; }
bad() { FAIL=$((FAIL+1)); echo "  [FAIL] $1: ${2:-}"; }
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
echo "## release"

[ -x "$R" ] && bash -n "$R" && ok "실행 권한·문법" || bad "실행 권한·문법"

# 픽스처 저장소 — 태그 유무 검사가 git 을 쓰므로 실제 git 저장소로 만든다
F="$WORK/repo"; mkdir -p "$F/.claude-plugin" "$F/bin"
( cd "$F" && git init -q && git config user.email t@example.invalid && git config user.name t )
echo "2.3.4" > "$F/VERSION"
printf '{\n  "name": "jobstack",\n  "version": "2.3.4"\n}\n' > "$F/.claude-plugin/plugin.json"
printf '{\n  "name": "x",\n  "version": "2.3.4"\n}\n' > "$F/bin/package.json"
printf '# Changelog\n\n## [2.3.4] - 2030-01-02\n\n요약 줄\n\n### Fixed\n- 고친 것 A\n\n## [2.3.3] - 2029-12-01\n\n### Fixed\n- 이전 릴리스 항목\n' > "$F/CHANGELOG.md"
( cd "$F" && git add -A && git commit -qm init )
run() { JOBSTACK_ROOT="$F" RELEASE_NOTES_FILE="$WORK/notes.md" bash "$R" "$@" 2>&1; }

OUT=$(run 2.3.4 --dry-run --summary "요약"); RC=$?
[ $RC -eq 0 ] && ok "정상 dry-run exit 0" || bad "정상 dry-run" "rc=$RC $OUT"
grep -q 'jobstack 2.3.4 -- 요약' <<<"$OUT" && ok "태그 메시지에 요약 반영" || bad "태그 메시지" "$OUT"
grep -q '고친 것 A' "$WORK/notes.md" && ! grep -q '이전 릴리스 항목\|## \[' "$WORK/notes.md" \
  && ok "릴리스 노트 = 해당 절만(다음 절·제목 줄 제외)" || bad "릴리스 노트 추출" "$(cat "$WORK/notes.md")"
( cd "$F" && [ -z "$(git tag -l)" ] ) && ok "dry-run 은 태그를 만들지 않음" || bad "dry-run 이 태그를 만듦"

for args in "" "v2.3.4 --dry-run" "2.3 --dry-run" "2.3.4 --nope" "2.3.4 2.3.5 --dry-run" "2.3.4 --summary"; do
  # shellcheck disable=SC2086
  run $args >/dev/null; RC=$?
  [ $RC -eq 1 ] && ok "인자 오류 exit 1: '$args'" || bad "인자 오류 exit 1: '$args'" "rc=$RC"
done

run 2.3.5 --dry-run >/dev/null; [ $? -eq 2 ] && ok "VERSION 불일치 exit 2" || bad "VERSION 불일치"
sed -i.bak 's/"version": "2.3.4"/"version": "2.3.0"/' "$F/.claude-plugin/plugin.json"
OUT=$(run 2.3.4 --dry-run); RC=$?
[ $RC -eq 2 ] && grep -q 'plugin.json' <<<"$OUT" && ok "plugin.json 불일치 exit 2" || bad "plugin.json 불일치" "rc=$RC $OUT"
mv "$F/.claude-plugin/plugin.json.bak" "$F/.claude-plugin/plugin.json"
cp "$F/CHANGELOG.md" "$WORK/cl.bak"
printf '# Changelog\n\n## [Unreleased]\n\n- 아직 확정 전\n\n## [2.3.3] - 2029-12-01\n' > "$F/CHANGELOG.md"
run 2.3.4 --dry-run >/dev/null; [ $? -eq 2 ] && ok "CHANGELOG 절 없음 exit 2" || bad "CHANGELOG 절 없음"
printf '# Changelog\n\n## [2.3.4]\n\n- 날짜 없는 제목\n' > "$F/CHANGELOG.md"
run 2.3.4 --dry-run >/dev/null; [ $? -eq 2 ] && ok "CHANGELOG 제목에 날짜 없음 exit 2" || bad "날짜 없음"
cp "$WORK/cl.bak" "$F/CHANGELOG.md"
( cd "$F" && git tag v2.3.4 )
OUT=$(run 2.3.4 --dry-run); RC=$?
[ $RC -eq 2 ] && grep -q '이미 있습니다' <<<"$OUT" && ok "이미 있는 태그 exit 2" || bad "이미 있는 태그" "rc=$RC $OUT"

# 저장소 실데이터: 현재 VERSION 의 CHANGELOG 절·버전 파일 정합(릴리스 준비 상태 점검)
V=$(tr -d ' \n' < "$REPO/VERSION")
grep -q "^## \[$V\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" "$REPO/CHANGELOG.md" && ok "CHANGELOG 에 현재 VERSION($V) 절 존재" || bad "CHANGELOG 에 [$V] 절 없음"
grep -q "\"version\": \"$V\"" "$REPO/bin/package.json" && ok "bin/package.json 버전 == VERSION" || bad "bin/package.json 버전 불일치"
python3 - "$REPO/.github/workflows/release.yml" <<'PY' 2>/dev/null && ok "release.yml — 수동 실행 전용·contents: write·release.sh 호출" || bad "release.yml 구성"
import sys
t = open(sys.argv[1], encoding='utf-8').read()
assert 'workflow_dispatch' in t and 'contents: write' in t and 'bin/release.sh' in t and "refs/heads/main" in t
assert '\n  push:' not in t and 'pull_request' not in t
PY

echo "PASS: $PASS / FAIL: $FAIL"
[ "$FAIL" -eq 0 ]
