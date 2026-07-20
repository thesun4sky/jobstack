#!/usr/bin/env bash
# jobstack installer
# Usage: cd jobstack && ./install.sh
#   or:  ./install.sh --prefix               (adds jobstack- prefix to skill names)
#   or:  ./install.sh --with-insane-search   (also builds bin/.is-venv for is-fetch.py)
set -euo pipefail

PREFIX=""
WITH_INSANE_SEARCH="0"
for arg in "$@"; do
  case "$arg" in
    --prefix) PREFIX="jobstack-" ;;
    --with-insane-search) WITH_INSANE_SEARCH="1" ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/commands"
STATE_DIR="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"

echo "╔══════════════════════════════════════╗"
echo "║  jobstack 설치                        ║"
echo "║  한국 취업 통합 엑셀러레이터            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# 1. 상태 디렉토리 생성
echo "[1/3] 상태 디렉토리 생성..."
mkdir -p "$STATE_DIR"/{profiles,tracker,company-cache,interview-history,analytics,sessions,defense-maps,job-cache}
echo "  → $STATE_DIR"

# 2. 스킬 설치 (심링크)
echo "[2/3] 스킬 설치..."
mkdir -p "$SKILLS_DIR"

SKILL_DIRS=(auto strategy company-research resume cover-letter portfolio mock-interview job-search ncs salary tracker review retro experience-bank career-history scout-profile)

for skill in "${SKILL_DIRS[@]}"; do
  skill_path="$SCRIPT_DIR/$skill"
  if [ -d "$skill_path" ] && [ -f "$skill_path/SKILL.md" ]; then
    link_name="${PREFIX}${skill}"
    target="$SKILLS_DIR/$link_name"
    # 기존 심링크/디렉토리 제거
    [ -L "$target" ] && rm "$target"
    [ -d "$target" ] && rm -rf "$target"
    ln -s "$skill_path" "$target"
    echo "  → /$link_name"

    # 언더스코어 alias — 하이픈 명령은 봇(Telegram)에서 탭이 안 되고,
    # README·스킬 본문이 사용자 노출 명령을 언더스코어로 안내하므로,
    # CLI(Claude Code)에서도 /cover_letter 형태가 동작하도록 alias 심링크를 함께 만든다.
    if [[ "$skill" == *-* ]]; then
      alias_name="${PREFIX}${skill//-/_}"
      alias_target="$SKILLS_DIR/$alias_name"
      [ -L "$alias_target" ] && rm "$alias_target"
      [ -d "$alias_target" ] && rm -rf "$alias_target"
      ln -s "$skill_path" "$alias_target"
      echo "  → /$alias_name (alias)"
    fi
  fi
done

# 3. bin 스크립트 권한
echo "[3/3] 스크립트 권한 설정..."
chmod +x "$SCRIPT_DIR/bin/"*

# 4. insane-search 어댑터 venv (opt-in) — bin/is-fetch.py 가 쓰는 curl_cffi 를
#    격리 venv 에 설치한다. 시스템 pip 직접 설치는 PEP 668(externally-managed)로
#    막히므로 venv 필수(실행계획 §1-3). 실패는 그대로 종료(set -e) — silent 금지.
#    플래그 없으면 이 단계는 건너뛰고 현행 동작 그대로.
#    ⚠️ curl_cffi>=0.15 는 Python >=3.10 필요 — macOS 기본 python3(3.9) 등에서 venv 는
#    만들어져도 pip 설치가 실패한다(리뷰 반영). >=3.10 인터프리터를 탐색하고, 못 찾으면
#    명확한 에러로 종료한다. JOBSTACK_PYTHON 으로 강제 지정 가능.
if [ "$WITH_INSANE_SEARCH" = "1" ]; then
  echo "[4/4] insane-search 어댑터 venv 설치 (curl_cffi)..."
  VENV_DIR="$SCRIPT_DIR/bin/.is-venv"

  # >=3.10 인터프리터 선택: JOBSTACK_PYTHON override → python3.13..3.10 → python3(버전검사).
  _py_ok() { "$1" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,10) else 1)' >/dev/null 2>&1; }
  IS_PYTHON=""
  for _cand in "${JOBSTACK_PYTHON:-}" python3.13 python3.12 python3.11 python3.10 python3; do
    [ -n "$_cand" ] || continue
    if command -v "$_cand" >/dev/null 2>&1 && _py_ok "$_cand"; then IS_PYTHON="$_cand"; break; fi
  done
  if [ -z "$IS_PYTHON" ]; then
    echo "ERROR: curl_cffi 는 Python >=3.10 이 필요합니다. python3.10+ 를 설치하거나 JOBSTACK_PYTHON 으로 지정하세요 (현재 python3: $(python3 --version 2>&1))." >&2
    exit 1
  fi
  echo "  → 인터프리터: $IS_PYTHON ($("$IS_PYTHON" --version 2>&1))"
  "$IS_PYTHON" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --no-cache-dir --upgrade pip >/dev/null
  "$VENV_DIR/bin/pip" install --no-cache-dir "curl_cffi>=0.15,<0.16"
  echo "  → $VENV_DIR (curl_cffi)"
fi

echo ""
echo "설치 완료!"
echo ""
echo "사용법:"
echo "  Claude Code에서 /auto 를 입력하면 자동으로 시작됩니다."
echo ""
echo "주요 스킬:"
echo "  /auto              — 파일 자동 감지 + 단계별 가이드"
echo "  /strategy          — 취업전략 수립"
echo "  /company-research  — 기업분석"
echo "  /resume            — 이력서 작성/첨삭"
echo "  /cover-letter      — 자기소개서 작성/첨삭"
echo "  /mock-interview    — 모의면접"
echo "  /review            — 통합 서류 리뷰"
echo "  /tracker           — 지원 현황 관리"
echo ""
echo "전체 목록: /auto 실행 후 안내를 따라주세요."
