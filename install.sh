#!/usr/bin/env bash
# jobstack installer
# Usage: cd jobstack && ./install.sh
#   or:  ./install.sh --prefix  (adds jobstack- prefix to skill names)
set -euo pipefail

PREFIX=""
[ "${1:-}" = "--prefix" ] && PREFIX="jobstack-"

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
mkdir -p "$STATE_DIR"/{profiles,tracker,company-cache,interview-history,analytics,sessions}
echo "  → $STATE_DIR"

# 2. 스킬 설치 (심링크)
echo "[2/3] 스킬 설치..."
mkdir -p "$SKILLS_DIR"

SKILL_DIRS=(auto strategy company-research resume cover-letter portfolio mock-interview job-search ncs salary tracker review retro)

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
  fi
done

# 3. bin 스크립트 권한
echo "[3/3] 스크립트 권한 설정..."
chmod +x "$SCRIPT_DIR/bin/"*

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
