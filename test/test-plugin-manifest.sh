#!/usr/bin/env bash
# 플러그인 매니페스트 린트.
#
# 검사 항목:
#   ① .claude-plugin/plugin.json 과 marketplace.json 이 유효한 JSON
#   ② plugin.json 의 name == "jobstack", version == VERSION 파일 내용
#   ③ plugin.json skills 배열의 각 항목 ./<dir> 에 SKILL.md 가 존재하고,
#      프론트매터 name: 이 <dir> 과 같음
#   ④ plugin.json agents 배열의 각 파일이 존재하고, 프론트매터에 name/description 있음
#   ⑤ 저장소의 */SKILL.md 를 가진 디렉토리 중 plugin.json skills 에 빠진 것이 없음
#   ⑥ marketplace.json: plugins[0].name == plugin.json name,
#      plugins[0].source == "./", owner.name 존재
#   ⑦ bin/package.json 유효한 JSON 이고 engines.node 있음

set -u
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"
FAIL=0

# JSON 검증 헬퍼
validate_json() {
  local file="$1"
  if ! python3 -c "import json; json.load(open('$file'))" 2>/dev/null; then
    return 1
  fi
  return 0
}

# YAML 프론트매터에서 YAML 키 값 추출
get_frontmatter_value() {
  local file="$1"
  local key="$2"
  sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//; s/['\"]//g"
}

# JSON 에서 값 추출
json_value() {
  local json="$1"
  local path="$2"
  python3 -c "
import json, sys
try:
    data = json.loads('''$json''')
    keys = '''$path'''.split('.')
    val = data
    for k in keys:
        if k.isdigit():
            val = val[int(k)]
        else:
            val = val.get(k)
    print(val if val is not None else '')
except:
    print('')
" 2>/dev/null
}

# ① plugin.json, marketplace.json JSON 검증
echo "① JSON 파일 검증..."
if ! validate_json "$REPO/.claude-plugin/plugin.json"; then
  echo "[FAIL] .claude-plugin/plugin.json 이 유효한 JSON 이 아닙니다"
  FAIL=$((FAIL+1))
fi
if ! validate_json "$REPO/.claude-plugin/marketplace.json"; then
  echo "[FAIL] .claude-plugin/marketplace.json 이 유효한 JSON 이 아닙니다"
  FAIL=$((FAIL+1))
fi

# ⑦ bin/package.json 검증
if ! validate_json "$REPO/bin/package.json"; then
  echo "[FAIL] bin/package.json 이 유효한 JSON 이 아닙니다"
  FAIL=$((FAIL+1))
else
  pkg_json=$(cat "$REPO/bin/package.json")
  if ! echo "$pkg_json" | grep -q '"engines"'; then
    echo "[FAIL] bin/package.json 에 engines 필드가 없습니다"
    FAIL=$((FAIL+1))
  fi
  if ! echo "$pkg_json" | grep -q '"node"'; then
    echo "[FAIL] bin/package.json 의 engines.node 이 없습니다"
    FAIL=$((FAIL+1))
  fi
fi

# 이후 검사를 위해 JSON 읽기
plugin_json=$(cat "$REPO/.claude-plugin/plugin.json")
marketplace_json=$(cat "$REPO/.claude-plugin/marketplace.json")

# ② plugin.json name 과 version 검증
pj_name=$(json_value "$plugin_json" "name")
pj_version=$(json_value "$plugin_json" "version")
version_file=$(tr -d ' \n' < "$REPO/VERSION")

if [ "$pj_name" != "jobstack" ]; then
  echo "[FAIL] plugin.json name 이 'jobstack' 이 아닙니다: '$pj_name'"
  FAIL=$((FAIL+1))
fi
if [ "$pj_version" != "$version_file" ]; then
  echo "[FAIL] plugin.json version ('$pj_version') 이 VERSION 파일 ('$version_file') 과 다릅니다"
  FAIL=$((FAIL+1))
fi

# ③ skills 배열 검증
echo "② 스킬 배열 검증..."
python3 << PYEOF
import json, os
plugin_file = os.path.join('$REPO', '.claude-plugin/plugin.json')
with open(plugin_file) as f:
    pj = json.load(f)

skills_in_json = []
for s in pj.get('skills', []):
    skill_dir = s.lstrip('./')
    skills_in_json.append(skill_dir)
    skill_file = os.path.join('$REPO', f"{skill_dir}/SKILL.md")
    if not os.path.exists(skill_file):
        print(f"[FAIL] 스킬 '{skill_dir}/SKILL.md' 이 없습니다")
        exit(1)

    # 프론트매터 name 확인
    with open(skill_file) as sf:
        lines = sf.readlines()
        if lines[0].strip() != '---':
            print(f"[FAIL] {skill_dir}/SKILL.md 프론트매터가 --- 로 시작하지 않습니다")
            exit(1)
        fm_end = -1
        for i in range(1, len(lines)):
            if lines[i].strip() == '---':
                fm_end = i
                break
        if fm_end == -1:
            print(f"[FAIL] {skill_dir}/SKILL.md 프론트매터가 닫혀 있지 않습니다")
            exit(1)

        # YAML 프론트매터에서 name 추출
        skill_name = None
        for i in range(1, fm_end):
            if lines[i].startswith('name:'):
                skill_name = lines[i].split(':', 1)[1].strip().strip('\'"')
                break

        if skill_name != skill_dir:
            print(f"[FAIL] {skill_dir}/SKILL.md 의 name ('{skill_name}') 이 디렉토리명 ('{skill_dir}') 과 다릅니다")
            exit(1)
PYEOF
if [ $? -ne 0 ]; then
  FAIL=$((FAIL+1))
fi

# ④ agents 배열 검증
echo "③ agents 배열 검증..."
python3 << PYEOF
import json, os
plugin_file = os.path.join('$REPO', '.claude-plugin/plugin.json')
with open(plugin_file) as f:
    pj = json.load(f)

for agent_path in pj.get('agents', []):
    agent_file = os.path.join('$REPO', agent_path)
    if not os.path.exists(agent_file):
        print(f"[FAIL] 에이전트 파일 '{agent_path}' 이 없습니다")
        exit(1)

    # 프론트매터 name, description 확인
    with open(agent_file) as af:
        lines = af.readlines()
        fm_start = -1
        fm_end = -1
        for i, line in enumerate(lines):
            if line.strip() == '---':
                if fm_start == -1:
                    fm_start = i
                elif fm_end == -1:
                    fm_end = i
                    break

        if fm_start == -1 or fm_end == -1:
            print(f"[FAIL] {agent_path} 프론트매터가 없습니다")
            exit(1)

        has_name = False
        has_desc = False
        for i in range(fm_start + 1, fm_end):
            if lines[i].startswith('name:'):
                has_name = True
            if lines[i].startswith('description:'):
                has_desc = True

        if not has_name:
            print(f"[FAIL] {agent_path} 프론트매터에 name 이 없습니다")
            exit(1)
        if not has_desc:
            print(f"[FAIL] {agent_path} 프론트매터에 description 이 없습니다")
            exit(1)
PYEOF
if [ $? -ne 0 ]; then
  FAIL=$((FAIL+1))
fi

# ⑤ 저장소의 모든 */SKILL.md 디렉토리가 plugin.json 에 있는지 확인
echo "④ 스킬 완전성 검증..."
python3 << PYEOF
import json, os, glob
plugin_file = os.path.join('$REPO', '.claude-plugin/plugin.json')
with open(plugin_file) as f:
    pj = json.load(f)

skills_in_json = set()
for s in pj.get('skills', []):
    skills_in_json.add(s.lstrip('./'))

# 저장소의 모든 */SKILL.md 찾기
skill_files = glob.glob(os.path.join('$REPO', '*/SKILL.md'))
dirs_with_skill = set()
for f in skill_files:
    d = os.path.dirname(f)
    skill_dir = os.path.relpath(d, '$REPO')
    dirs_with_skill.add(skill_dir)

missing = dirs_with_skill - skills_in_json
if missing:
    for m in sorted(missing):
        print(f"[FAIL] 스킬 '{m}' 이 plugin.json skills 배열에 빠져 있습니다")
    exit(1)
PYEOF
if [ $? -ne 0 ]; then
  FAIL=$((FAIL+1))
fi

# ⑥ marketplace.json 검증
echo "⑤ marketplace.json 검증..."
mj_name=$(json_value "$marketplace_json" "plugins.0.name")
mj_source=$(json_value "$marketplace_json" "plugins.0.source")
mj_owner=$(json_value "$marketplace_json" "owner.name")

if [ "$mj_name" != "$pj_name" ]; then
  echo "[FAIL] marketplace.json plugins[0].name ('$mj_name') 이 plugin.json name ('$pj_name') 과 다릅니다"
  FAIL=$((FAIL+1))
fi
if [ "$mj_source" != "./" ]; then
  echo "[FAIL] marketplace.json plugins[0].source 가 './' 이 아닙니다: '$mj_source'"
  FAIL=$((FAIL+1))
fi
if [ -z "$mj_owner" ]; then
  echo "[FAIL] marketplace.json owner.name 이 없습니다"
  FAIL=$((FAIL+1))
fi

if [ "$FAIL" -gt 0 ]; then
  echo "[FAIL] 플러그인 매니페스트 린트 ${FAIL}건"
  exit 1
fi
echo "[PASS] 플러그인 매니페스트가 유효합니다"
exit 0
