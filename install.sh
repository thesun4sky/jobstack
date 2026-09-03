#!/usr/bin/env bash
# jobstack installer
# Usage: cd jobstack && ./install.sh
#   or:  ./install.sh --prefix               (adds jobstack- prefix to skill names)
#   or:  ./install.sh --with-insane-search   (also builds bin/.is-venv for is-fetch.py)
#
# v0.4.0: 스킬은 Claude Code 표준 위치 ~/.claude/skills/ 에 심링크한다(이전 ~/.claude/commands/ 는
# 파일 단위 레거시 경로). 이 저장소가 만든 옛 commands/ 심링크는 정리한다.
# 플러그인 설치(`/plugin marketplace add thesun4sky/jobstack`)는 v0.5.0 부터 지원한다.
set -euo pipefail

PREFIX=""
WITH_INSANE_SEARCH="0"
for arg in "$@"; do
  case "$arg" in
    --prefix) PREFIX="jobstack-" ;;
    --with-insane-search) WITH_INSANE_SEARCH="1" ;;
  esac
done

SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"
LEGACY_DIR="$HOME/.claude/commands"
AGENTS_DIR="$HOME/.claude/agents"
STATE_DIR="${JOBSTACK_STATE_DIR:-$HOME/.jobstack}"

echo "╔══════════════════════════════════════╗"
echo "║  jobstack 설치                        ║"
echo "║  한국 취업 통합 엑셀러레이터            ║"
echo "╚══════════════════════════════════════╝"
echo ""

# 1. 상태 디렉토리 생성
echo "[1/4] 상태 디렉토리 생성..."
mkdir -p "$STATE_DIR"/{profiles,tracker,company-cache,interview-history,analytics,sessions,defense-maps,job-cache}
echo "  → $STATE_DIR"

# 2. 스킬 설치 (심링크)
echo "[2/4] 스킬 설치 ($SKILLS_DIR)..."
mkdir -p "$SKILLS_DIR"

SKILL_DIRS=(auto strategy company-research resume cover-letter portfolio mock-interview job-search ncs salary tracker review retro experience-bank career-history scout-profile)

skill_source() { # 저장소 루트 배치와 skills/ 배치 둘 다 지원
  if [ -d "$SCRIPT_DIR/skills/$1" ]; then echo "$SCRIPT_DIR/skills/$1"; else echo "$SCRIPT_DIR/$1"; fi
}

link_skill() { # $1=link name $2=source dir
  local target="$SKILLS_DIR/$1"
  [ -L "$target" ] && rm "$target"
  [ -d "$target" ] && rm -rf "$target"
  ln -s "$2" "$target"
}

remove_legacy() { # $1=link name — 이 저장소를 가리키는 옛 commands/ 심링크만 제거
  local legacy="$LEGACY_DIR/$1"
  if [ -L "$legacy" ]; then
    case "$(readlink "$legacy")" in
      "$SCRIPT_DIR"/*) rm "$legacy"; echo "  ✓ 레거시 심링크 정리: $legacy" ;;
    esac
  fi
}

for skill in "${SKILL_DIRS[@]}"; do
  skill_path="$(skill_source "$skill")"
  if [ -d "$skill_path" ] && [ -f "$skill_path/SKILL.md" ]; then
    link_name="${PREFIX}${skill}"
    link_skill "$link_name" "$skill_path"
    remove_legacy "$link_name"
    echo "  → /$link_name"

    # 언더스코어 alias — 하이픈 명령은 봇(Telegram)에서 탭이 안 되고,
    # README·스킬 본문이 사용자 노출 명령을 언더스코어로 안내하므로,
    # CLI(Claude Code)에서도 /cover_letter 형태가 동작하도록 alias 심링크를 함께 만든다.
    if [[ "$skill" == *-* ]]; then
      alias_name="${PREFIX}${skill//-/_}"
      link_skill "$alias_name" "$skill_path"
      remove_legacy "$alias_name"
      echo "  → /$alias_name (alias)"
    fi
  fi
done

# 3. 서브에이전트 정의 (agents/*.md 가 있을 때만 — v0.5.0 researcher 등)
echo "[3/4] 서브에이전트·스크립트 설정..."
if [ -d "$SCRIPT_DIR/agents" ] && ls "$SCRIPT_DIR"/agents/*.md >/dev/null 2>&1; then
  mkdir -p "$AGENTS_DIR"
  for agent in "$SCRIPT_DIR"/agents/*.md; do
    name="$(basename "$agent")"
    [ -L "$AGENTS_DIR/$name" ] && rm "$AGENTS_DIR/$name"
    ln -s "$agent" "$AGENTS_DIR/$name"
    echo "  → agent: ${name%.md}"
  done
fi
chmod +x "$SCRIPT_DIR/bin/"* 2>/dev/null || true
for d in "$SCRIPT_DIR"/*/scripts "$SCRIPT_DIR"/skills/*/scripts; do
  [ -d "$d" ] && chmod +x "$d"/*.sh 2>/dev/null || true
done
echo "  → bin/, scripts/ 실행 권한"

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

  # >=3.10 인터프리터 선택: JOBSTACK_PYTHON override → python3.15..3.10 → python3(버전검사).
  _py_ok() { "$1" -c 'import sys; raise SystemExit(0 if sys.version_info[:2] >= (3,10) else 1)' >/dev/null 2>&1; }
  IS_PYTHON=""
  # JOBSTACK_PYTHON 이 '명시적으로' 지정됐는데 없거나 <3.10 이면, 조용히 폴백하지 않고 즉시 에러
  # ('강제 지정' 계약 준수, 리뷰 반영).
  if [ -n "${JOBSTACK_PYTHON:-}" ]; then
    if command -v "$JOBSTACK_PYTHON" >/dev/null 2>&1 && _py_ok "$JOBSTACK_PYTHON"; then
      IS_PYTHON="$JOBSTACK_PYTHON"
    else
      echo "ERROR: JOBSTACK_PYTHON='$JOBSTACK_PYTHON' 이 없거나 Python >=3.10 이 아닙니다 ($("$JOBSTACK_PYTHON" --version 2>&1 || echo 'not found'))." >&2
      exit 1
    fi
  else
    for _cand in python3.15 python3.14 python3.13 python3.12 python3.11 python3.10 python3; do
      if command -v "$_cand" >/dev/null 2>&1 && _py_ok "$_cand"; then IS_PYTHON="$_cand"; break; fi
    done
  fi
  if [ -z "$IS_PYTHON" ]; then
    echo "ERROR: curl_cffi 는 Python >=3.10 이 필요합니다. python3.10+ 를 설치하거나 JOBSTACK_PYTHON 으로 지정하세요 (현재 python3: $(python3 --version 2>&1 || echo 'not found'))." >&2
    exit 1
  fi
  echo "  → 인터프리터: $IS_PYTHON ($("$IS_PYTHON" --version 2>&1))"
  "$IS_PYTHON" -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --no-cache-dir --upgrade pip >/dev/null
  "$VENV_DIR/bin/pip" install --no-cache-dir "curl_cffi>=0.16,<0.17"
  echo "  → $VENV_DIR (curl_cffi)"
else
  echo "[4/4] insane-search 어댑터: 건너뜀 (--with-insane-search 로 설치)"
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
echo "  /company_research  — 기업분석"
echo "  /resume            — 이력서 작성/첨삭"
echo "  /cover_letter      — 자기소개서 작성/첨삭"
echo "  /mock_interview    — 모의면접"
echo "  /review            — 통합 서류 리뷰"
echo "  /tracker           — 지원 현황 관리 (CLI)"
echo ""
echo "선택 의존성: job_search 는 Node 22+ (Playwright 자동 설치), 문서 내보내기는 pandoc,"
echo "차단 사이트 수집은 --with-insane-search (Python 3.10+)."
echo "전체 목록: /auto 실행 후 안내를 따라주세요."
