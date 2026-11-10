#!/usr/bin/env bash
# release.sh — 릴리스 태그와 GitHub 릴리스를 만든다(.github/workflows/release.yml 이 호출).
#
# 사용법: release.sh <버전> [--dry-run] [--summary "<태그 메시지 요약>"]
#   <버전>  1.2.3 형식(앞의 v 는 붙이지 않는다). 태그는 v<버전>.
#   --dry-run  검사와 릴리스 노트 추출만 하고 태그·릴리스는 만들지 않는다(로컬 확인·테스트용).
# 검사: VERSION·.claude-plugin/plugin.json·bin/package.json 이 모두 <버전> 인가,
#       CHANGELOG.md 에 "## [<버전>]" 절이 있고 비어 있지 않은가, 태그가 이미 있지 않은가.
# 릴리스 노트: CHANGELOG.md 의 해당 절 본문. RELEASE_NOTES_FILE 로 경로 지정(기본: 임시 파일).
# 실제 실행에는 git push 권한과 gh CLI(GH_TOKEN)가 필요하다 — 워크플로우의 contents: write.
# 종료: 0 성공 · 1 인자 오류 · 2 검사 실패 · 3 태그·릴리스 생성 실패
set -u
ROOT="${JOBSTACK_ROOT:-$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
VERSION=""; DRY=0; SUMMARY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=1; shift ;;
    --summary) [ $# -ge 2 ] || { echo "옵션 --summary 에 값이 필요합니다." >&2; exit 1; }; SUMMARY="$2"; shift 2 ;;
    -*) echo "알 수 없는 옵션: $1" >&2; exit 1 ;;
    *) [ -z "$VERSION" ] || { echo "버전은 하나만 지정합니다." >&2; exit 1; }; VERSION="$1"; shift ;;
  esac
done
case "$VERSION" in
  ''|v*) echo "사용법: release.sh <버전> [--dry-run] [--summary \"…\"]   (예: release.sh 1.1.1 — v 는 붙이지 않습니다)" >&2; exit 1 ;;
esac
echo "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' || { echo "버전 형식이 올바르지 않습니다: $VERSION (예: 1.2.3)" >&2; exit 1; }
TAG="v$VERSION"
fail() { echo "[FAIL] $1" >&2; exit 2; }

cd "$ROOT" || fail "저장소 루트로 이동할 수 없습니다: $ROOT"
[ "$(tr -d ' \n' < VERSION 2>/dev/null)" = "$VERSION" ] || fail "VERSION 파일이 $VERSION 이 아닙니다"
for f in .claude-plugin/plugin.json bin/package.json; do
  grep -qE "\"version\"[[:space:]]*:[[:space:]]*\"$VERSION\"" "$f" 2>/dev/null || fail "$f 의 version 이 $VERSION 이 아닙니다"
done

NOTES="${RELEASE_NOTES_FILE:-$(mktemp "${TMPDIR:-/tmp}/jobstack-release-notes.XXXXXX")}"
awk -v v="$VERSION" '
  index($0, "## [" v "]") == 1 { on = 1; next }
  on && /^## \[/               { exit }
  on                           { print }
' CHANGELOG.md > "$NOTES"
grep -q '[^[:space:]]' "$NOTES" || fail "CHANGELOG.md 에 '## [$VERSION]' 절이 없거나 비어 있습니다"
grep -q "^## \[$VERSION\] - [0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}" CHANGELOG.md || fail "CHANGELOG.md 의 [$VERSION] 제목에 날짜(YYYY-MM-DD)가 없습니다"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 \
   || git ls-remote --exit-code --tags origin "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "태그 $TAG 가 이미 있습니다"
fi

MSG="jobstack $VERSION"; [ -n "$SUMMARY" ] && MSG="$MSG -- $SUMMARY"
echo "버전: $VERSION · 태그: $TAG · 대상: $(git rev-parse --short HEAD) · 릴리스 노트: $(grep -c '' "$NOTES")줄 ($NOTES)"
if [ "$DRY" = 1 ]; then echo "[dry-run] 검사 통과 — 태그·릴리스는 만들지 않았습니다. 태그 메시지: $MSG"; exit 0; fi

git tag -a "$TAG" -m "$MSG" || { echo "[FAIL] 태그 생성 실패" >&2; exit 3; }
git push origin "refs/tags/$TAG" || { echo "[FAIL] 태그 푸시 실패" >&2; git tag -d "$TAG" >/dev/null 2>&1; exit 3; }
gh release create "$TAG" --verify-tag --title "$TAG" --notes-file "$NOTES" || { echo "[FAIL] GitHub 릴리스 생성 실패(태그 $TAG 는 푸시됨)" >&2; exit 3; }
echo "릴리스 $TAG 를 만들었습니다."
