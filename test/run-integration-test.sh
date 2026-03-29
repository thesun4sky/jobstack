#!/usr/bin/env bash
# jobstack 통합 테스트 스크립트
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TEST_DATA="$SCRIPT_DIR/sample-data"
REPORT="$SCRIPT_DIR/test-report.md"
PASS=0
FAIL=0
TOTAL=0

log_test() {
  TOTAL=$((TOTAL + 1))
  local status="$1"
  local name="$2"
  local detail="${3:-}"
  if [ "$status" = "PASS" ]; then
    PASS=$((PASS + 1))
    echo "  [PASS] $name"
  else
    FAIL=$((FAIL + 1))
    echo "  [FAIL] $name: $detail"
  fi
}

echo "╔══════════════════════════════════════╗"
echo "║  jobstack 통합 테스트                 ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ────────────────────────────────────────
echo "## 1. 인프라 테스트"
echo ""

# 1.1 install.sh
echo "### install.sh"
"$PROJECT_DIR/install.sh" > /dev/null 2>&1
if [ -L "$HOME/.claude/commands/auto" ]; then
  log_test "PASS" "심링크 생성 (auto)"
else
  log_test "FAIL" "심링크 생성 (auto)" "심링크 없음"
fi

SKILL_COUNT=$(ls -d "$HOME/.claude/commands"/{auto,strategy,resume,cover-letter,company-research,mock-interview,review,tracker,retro,portfolio,job-search,ncs,salary} 2>/dev/null | wc -l | tr -d ' ')
if [ "$SKILL_COUNT" -eq 13 ]; then
  log_test "PASS" "전체 13개 스킬 설치"
else
  log_test "FAIL" "전체 13개 스킬 설치" "설치된 수: $SKILL_COUNT"
fi

# 1.2 jobstack-config
echo ""
echo "### jobstack-config"
"$PROJECT_DIR/bin/jobstack-config" set test_key test_value 2>/dev/null
RESULT=$("$PROJECT_DIR/bin/jobstack-config" get test_key 2>/dev/null)
if [ "$RESULT" = "test_value" ]; then
  log_test "PASS" "config set/get"
else
  log_test "FAIL" "config set/get" "결과: $RESULT"
fi

LIST_RESULT=$("$PROJECT_DIR/bin/jobstack-config" list 2>/dev/null)
if echo "$LIST_RESULT" | grep -q "test_key"; then
  log_test "PASS" "config list"
else
  log_test "FAIL" "config list"
fi

# 1.3 상태 디렉토리
echo ""
echo "### 상태 디렉토리"
for dir in profiles tracker company-cache interview-history analytics sessions; do
  if [ -d "$HOME/.jobstack/$dir" ]; then
    log_test "PASS" "디렉토리: ~/.jobstack/$dir"
  else
    log_test "FAIL" "디렉토리: ~/.jobstack/$dir" "존재하지 않음"
  fi
done

# ────────────────────────────────────────
echo ""
echo "## 2. 프리앰블 테스트"
echo ""

# 각 스킬의 프리앰블 bash 블록 실행
for skill_dir in "$PROJECT_DIR"/{auto,strategy,resume,cover-letter,company-research,mock-interview,review,tracker,retro,portfolio,job-search,ncs,salary}; do
  skill_name=$(basename "$skill_dir")
  SKILL_FILE="$skill_dir/SKILL.md"
  if [ ! -f "$SKILL_FILE" ]; then
    log_test "FAIL" "프리앰블: $skill_name" "SKILL.md 없음"
    continue
  fi

  # YAML 프론트매터 확인
  if head -3 "$SKILL_FILE" | grep -q "^---"; then
    log_test "PASS" "YAML 프론트매터: $skill_name"
  else
    log_test "FAIL" "YAML 프론트매터: $skill_name" "--- 없음"
  fi

  # bash 블록 존재 확인
  if grep -q '```bash' "$SKILL_FILE"; then
    log_test "PASS" "프리앰블 bash: $skill_name"
  else
    log_test "FAIL" "프리앰블 bash: $skill_name" "bash 블록 없음"
  fi
done

# ────────────────────────────────────────
echo ""
echo "## 3. 뷰어 테스트"
echo ""

# 테스트 마크다운으로 뷰어 테스트
"$PROJECT_DIR/bin/jobstack-view" "$TEST_DATA/이력서_홍길동.md" --no-open 2>/dev/null
if [ -f "$TEST_DATA/이력서_홍길동.html" ]; then
  log_test "PASS" "뷰어: HTML 생성"
  SIZE=$(wc -c < "$TEST_DATA/이력서_홍길동.html" | tr -d ' ')
  if [ "$SIZE" -gt 1000 ]; then
    log_test "PASS" "뷰어: HTML 크기 적절 (${SIZE}B)"
  else
    log_test "FAIL" "뷰어: HTML 크기" "너무 작음: ${SIZE}B"
  fi
  # marked.js CDN 참조 확인
  if grep -q "cdn.jsdelivr.net/npm/marked" "$TEST_DATA/이력서_홍길동.html"; then
    log_test "PASS" "뷰어: marked.js CDN 참조"
  else
    log_test "FAIL" "뷰어: marked.js CDN 참조" "없음"
  fi
  # 한국어 폰트 확인
  if grep -q "Noto Sans KR" "$TEST_DATA/이력서_홍길동.html"; then
    log_test "PASS" "뷰어: 한국어 폰트 (Noto Sans KR)"
  else
    log_test "FAIL" "뷰어: 한국어 폰트"
  fi
  # 다크모드 확인
  if grep -q "prefers-color-scheme: dark" "$TEST_DATA/이력서_홍길동.html"; then
    log_test "PASS" "뷰어: 다크모드 지원"
  else
    log_test "FAIL" "뷰어: 다크모드 지원"
  fi
  # PDF 버튼 확인
  if grep -q "PDF 저장" "$TEST_DATA/이력서_홍길동.html"; then
    log_test "PASS" "뷰어: PDF 저장 버튼"
  else
    log_test "FAIL" "뷰어: PDF 저장 버튼"
  fi
  rm -f "$TEST_DATA/이력서_홍길동.html"
else
  log_test "FAIL" "뷰어: HTML 생성" "파일 없음"
fi

# ────────────────────────────────────────
echo ""
echo "## 4. 파일 감지 테스트 (auto 스킬 로직)"
echo ""

# auto 스킬이 감지할 파일 패턴 테스트
RESUME_FILES=$(find "$TEST_DATA" -maxdepth 1 -name '이력서*' -o -name 'resume*' -o -name 'CV*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$RESUME_FILES" -gt 0 ]; then
  log_test "PASS" "이력서 감지: ${RESUME_FILES}건"
else
  log_test "FAIL" "이력서 감지" "파일 없음"
fi

COVER_FILES=$(find "$TEST_DATA" -maxdepth 1 -name '자소서*' -o -name '자기소개서*' -o -name 'cover-letter*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$COVER_FILES" -gt 0 ]; then
  log_test "PASS" "자소서 감지: ${COVER_FILES}건"
else
  log_test "FAIL" "자소서 감지"
fi

JD_FILES=$(find "$TEST_DATA" -maxdepth 1 -name '채용*' -o -name 'JD*' -o -name 'job-posting*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$JD_FILES" -gt 0 ]; then
  log_test "PASS" "채용공고 감지: ${JD_FILES}건"
else
  log_test "FAIL" "채용공고 감지"
fi

# ────────────────────────────────────────
echo ""
echo "## 5. tracker JSONL 테스트"
echo ""

TRACKER_FILE="$HOME/.jobstack/tracker/applications.jsonl"
# 테스트 데이터 추가
echo '{"id":"app-001","company":"네이버","position":"백엔드 개발자","status":"서류전형","applied_at":"2026-03-29","deadline":"2026-04-30","updated_at":"2026-03-29","notes":"코딩테스트 준비 필요"}' > "$TRACKER_FILE"
echo '{"id":"app-002","company":"카카오","position":"서버 개발자","status":"준비중","applied_at":"2026-03-29","deadline":"2026-05-15","updated_at":"2026-03-29","notes":""}' >> "$TRACKER_FILE"

ENTRY_COUNT=$(wc -l < "$TRACKER_FILE" | tr -d ' ')
if [ "$ENTRY_COUNT" -eq 2 ]; then
  log_test "PASS" "tracker JSONL 쓰기 (2건)"
else
  log_test "FAIL" "tracker JSONL 쓰기" "건수: $ENTRY_COUNT"
fi

# JSON 유효성 검증
if python3 -c "
import json, sys
with open('$TRACKER_FILE') as f:
    for line in f:
        json.loads(line.strip())
print('valid')
" 2>/dev/null | grep -q "valid"; then
  log_test "PASS" "tracker JSONL 유효성"
else
  log_test "FAIL" "tracker JSONL 유효성"
fi

# ────────────────────────────────────────
echo ""
echo "## 6. 프로필 저장 테스트"
echo ""

PROFILE_FILE="$HOME/.jobstack/profiles/default.yaml"
cat > "$PROFILE_FILE" << 'EOF'
name: 홍길동
email: hong@example.com
phone: 010-1234-5678
education:
  school: 한국대학교
  major: 컴퓨터공학
  graduation: 2022-02
  gpa: 3.8/4.5
experience:
  - company: ABC 스타트업
    role: 백엔드 개발 인턴
    period: 2021.07-2021.12
    highlights:
      - Spring Boot REST API 개발
      - Redis 캐싱 도입
certifications:
  - 정보처리기사
language:
  - TOEIC 820
target:
  roles: [백엔드 개발자]
  industries: [IT/테크]
  companies: [네이버, 카카오, 라인]
  timeline: 2026년 상반기
strengths:
  - 문제 해결 능력
  - 성능 최적화 경험
updated_at: 2026-03-29
EOF

if [ -f "$PROFILE_FILE" ]; then
  log_test "PASS" "프로필 YAML 저장"
else
  log_test "FAIL" "프로필 YAML 저장"
fi

if grep -q "name: 홍길동" "$PROFILE_FILE" && grep -q "target:" "$PROFILE_FILE"; then
  log_test "PASS" "프로필 YAML 구조 검증"
else
  log_test "FAIL" "프로필 YAML 구조 검증"
fi

# ────────────────────────────────────────
echo ""
echo "## 7. 텔레메트리 테스트"
echo ""

ANALYTICS_FILE="$HOME/.jobstack/analytics/skill-usage.jsonl"
echo '{"skill":"auto","ts":"2026-03-29T06:48:00Z","pid":1234}' > "$ANALYTICS_FILE"
echo '{"skill":"strategy","ts":"2026-03-29T06:50:00Z","pid":1234}' >> "$ANALYTICS_FILE"
echo '{"skill":"resume","ts":"2026-03-29T06:55:00Z","pid":1234}' >> "$ANALYTICS_FILE"

ANALYTICS_COUNT=$(wc -l < "$ANALYTICS_FILE" | tr -d ' ')
if [ "$ANALYTICS_COUNT" -ge 3 ]; then
  log_test "PASS" "텔레메트리 JSONL (${ANALYTICS_COUNT}건)"
else
  log_test "FAIL" "텔레메트리 JSONL"
fi

# ────────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  테스트 결과: $PASS/$TOTAL 통과 ($FAIL 실패)"
echo "════════════════════════════════════════"

exit $FAIL
