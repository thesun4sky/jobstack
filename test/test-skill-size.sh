#!/usr/bin/env bash
# 스킬 크기 린트.
#
# 검사 항목:
#   ① 각 스킬의 줄 수 ≤ ${SKILL_MAX_LINES:-300}
#   ② 프론트매터 description 길이 ≤ ${SKILL_DESC_MAX:-1024} 자
#   ③ name + description 합산 ≤ ${SKILL_HEAD_BUDGET:-1100} 자
#   ④ (--frontmatter 플래그) argument-hint/when_to_use 최상위 필수,
#      preamble-tier/version/benefits-from 최상위 금지 (metadata 아래는 허용)

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

SKILL_MAX_LINES="${SKILL_MAX_LINES:-300}"
SKILL_DESC_MAX="${SKILL_DESC_MAX:-1024}"
SKILL_HEAD_BUDGET="${SKILL_HEAD_BUDGET:-1100}"
CHECK_FRONTMATTER=0

if [ "${1:-}" = "--frontmatter" ]; then
  CHECK_FRONTMATTER=1
fi

FAIL=0
TOTAL=0

python3 << PYEOF
import os, sys, re, glob

repo = '$REPO'
max_lines = $SKILL_MAX_LINES
max_desc = $SKILL_DESC_MAX
max_head_budget = $SKILL_HEAD_BUDGET
check_frontmatter = $CHECK_FRONTMATTER

# 모든 */SKILL.md 찾기
skill_files = sorted(glob.glob(os.path.join(repo, '*/SKILL.md')))

fail_count = 0
total_count = len(skill_files)

for skill_file in skill_files:
    skill_dir = os.path.dirname(skill_file)
    skill_name = os.path.basename(skill_dir)

    with open(skill_file, 'r', encoding='utf-8') as f:
        content = f.read()
        lines = content.split('\n')

    line_count = len(lines)

    # ① 줄 수 검사
    if line_count > max_lines:
        print(f"[FAIL] {skill_name}: {line_count}줄 (제한: {max_lines}줄)")
        fail_count += 1
        continue

    # 프론트매터 추출 (--- 사이의 YAML)
    if lines[0].strip() != '---':
        print(f"[FAIL] {skill_name}: 프론트매터가 --- 로 시작하지 않습니다")
        fail_count += 1
        continue

    fm_end = -1
    for i in range(1, len(lines)):
        if lines[i].strip() == '---':
            fm_end = i
            break

    if fm_end == -1:
        print(f"[FAIL] {skill_name}: 프론트매터가 닫혀 있지 않습니다")
        fail_count += 1
        continue

    frontmatter_lines = lines[1:fm_end]

    # YAML 프론트매터 파싱
    yaml_data = {}
    i = 0
    while i < len(frontmatter_lines):
        line = frontmatter_lines[i]

        # 키: 값 형식
        if ':' in line and not line.startswith(' '):
            parts = line.split(':', 1)
            key = parts[0].strip()
            value = parts[1].strip() if len(parts) > 1 else ''

            # 블록 스칼라 (|, >) 처리
            if value in ('|', '>'):
                block_lines = []
                i += 1
                # 들여쓰기된 줄을 모두 수집
                while i < len(frontmatter_lines):
                    if frontmatter_lines[i] and not frontmatter_lines[i][0].isspace():
                        break
                    if frontmatter_lines[i].strip():
                        block_lines.append(frontmatter_lines[i].strip())
                    i += 1
                yaml_data[key] = '\n'.join(block_lines)
                i -= 1
            elif value.startswith('['):
                # 배열은 무시 (이 린트에서는 필요 없음)
                pass
            else:
                # 스칼라 값 (따옴표 제거)
                yaml_data[key] = value.strip('\'"')

        i += 1

    name_val = yaml_data.get('name', '')
    description_val = yaml_data.get('description', '')

    # ② description 길이 검사
    desc_len = len(description_val)
    if desc_len > max_desc:
        print(f"[FAIL] {skill_name}: description {desc_len}자 (제한: {max_desc}자)")
        fail_count += 1
        continue

    # ③ name + description 합산 검사
    head_len = len(name_val) + len(description_val)
    if head_len > max_head_budget:
        print(f"[FAIL] {skill_name}: name+description {head_len}자 (제한: {max_head_budget}자)")
        fail_count += 1
        continue

    # ④ --frontmatter 플래그 검사
    if check_frontmatter:
        has_argument_hint = 'argument-hint' in yaml_data
        has_when_to_use = 'when_to_use' in yaml_data

        has_preamble_tier = 'preamble-tier' in [k for k, v in yaml_data.items() if not k.startswith('metadata.')]
        has_version = 'version' in [k for k, v in yaml_data.items() if not k.startswith('metadata.')]
        has_benefits = 'benefits-from' in [k for k, v in yaml_data.items() if not k.startswith('metadata.')]

        # 원문 재검사: metadata 아래 허용
        has_top_level_preamble = False
        has_top_level_version = False
        has_top_level_benefits = False

        for line in frontmatter_lines:
            if line.startswith('preamble-tier:'):
                has_top_level_preamble = True
            if line.startswith('version:'):
                has_top_level_version = True
            if line.startswith('benefits-from:'):
                has_top_level_benefits = True

        if not has_argument_hint:
            print(f"[FAIL] {skill_name}: argument-hint 이 프론트매터에 없습니다")
            fail_count += 1
            continue
        if not has_when_to_use:
            print(f"[FAIL] {skill_name}: when_to_use 이 프론트매터에 없습니다")
            fail_count += 1
            continue
        if has_top_level_preamble:
            print(f"[FAIL] {skill_name}: preamble-tier 이 최상위 레벨에 있습니다 (metadata 아래로 옮기세요)")
            fail_count += 1
            continue
        if has_top_level_version:
            print(f"[FAIL] {skill_name}: version 이 최상위 레벨에 있습니다 (metadata 아래로 옮기세요)")
            fail_count += 1
            continue
        if has_top_level_benefits:
            print(f"[FAIL] {skill_name}: benefits-from 이 최상위 레벨에 있습니다 (metadata 아래로 옮기세요)")
            fail_count += 1
            continue

if fail_count > 0:
    print(f"\n[FAIL] 총 {total_count}개 스킬 · 초과 {fail_count}개")
    sys.exit(1)
else:
    print(f"[PASS] 총 {total_count}개 스킬 · 모두 크기 기준을 만족합니다")
    sys.exit(0)
PYEOF
