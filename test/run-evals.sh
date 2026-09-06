#!/usr/bin/env bash
# jobstack 스킬 eval 러너 (U-16 초안 — docs/evals.md 참조).
#
# evals/<skill>/evals.json 의 케이스를 격리 HOME(mktemp)에 install.sh 로 심링크 설치한 뒤
# `claude -p --output-format stream-json --verbose --model <model> --max-turns N "<prompt>"`
# 로 실제 실행하고, 스트림에서 tool_use(Bash 명령·Read 경로)와 최종 텍스트를 추출해
# expectations(must_contain/must_not_contain/must_call/must_read/must_output)를 결정적으로 판정한다.
# grader:"llm" 케이스는 `claude -p --model haiku` 로 채점 프롬프트를 한 번 더 호출해
# 판정에 병합한다. should_trigger 배열은 --trigger 모드로 별도 실행한다(비용 발생 — 아래 안내 참조).
#
# claude CLI 가 없거나 --dry-run 이면 케이스와 실행될 명령만 나열하고 exit 0 한다(과금 없음).
# 파이프 파싱은 표준 라이브러리 json 만 쓰는 python3 인라인 스크립트로 한다(run-golden.sh 관례와 동일).
#
# 사용법:
#   run-evals.sh [--tier gate|periodic|e2e] [--skill <name>] [--model <model>] [--dry-run]
#   run-evals.sh --trigger [--skill <name>] [--model <model>] [--dry-run]
#
# 환경변수:
#   REPO        jobstack 저장소 경로. 기본값은 이 스크립트의 상위 디렉토리(실저장소에 통합됐을 때
#               test/run-evals.sh 기준 자동 해석)이지만, evals/ 를 스크립트와 나란히 둔 채 다른 위치의
#               저장소(스크래치 사본 등)를 대상으로 돌릴 때는 REPO=/path/to/jobstack 로 지정한다.
#   EVALS_DIR   evals.json 이 있는 디렉토리. 기본값은 이 스크립트와 나란한 ../evals (REPO 와 무관 —
#               eval 케이스 정의는 하네스와 함께 다니고, REPO 는 "무엇을 테스트하는가"만 가리킨다).
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVALS_DIR="${EVALS_DIR:-$SCRIPT_DIR/../evals}"
REPO="${REPO:-$(cd "$SCRIPT_DIR/.." && pwd)}"
REPORT_MD="$SCRIPT_DIR/eval-report.md"
REPORT_JSON="$SCRIPT_DIR/eval-report.json"
TRIGGER_REPORT_MD="$SCRIPT_DIR/eval-trigger-report.md"
TRIGGER_REPORT_JSON="$SCRIPT_DIR/eval-trigger-report.json"

TIER=""
SKILL_FILTER=""
MODEL="sonnet"
JUDGE_MODEL="${EVAL_JUDGE_MODEL:-haiku}"  # grader: llm 채점 모델 — Haiku 4.5 은퇴(2026-10-15) 전 재확인
DRY_RUN=0
TRIGGER_MODE=0

usage() {
  cat <<'EOF'
사용법: run-evals.sh [옵션]

  --tier gate|periodic|e2e   지정한 tier 케이스만 실행/나열 (기본: 전체)
  --skill <name>             지정한 스킬만 실행/나열, 예: tracker (기본: 전체 5개)
  --model <model>            claude -p 에 넘길 모델 (기본: sonnet)
  --dry-run                  실행 없이 케이스와 실행될 명령만 출력하고 exit 0 (과금 없음)
  --trigger                  cases 대신 should_trigger 배열로 트리거 정확도만 측정
                              (스킬당 8~10건 × claude -p --max-turns 1 — 비용 발생, 아래 안내 참조)
  -h, --help                 이 도움말

환경변수:
  REPO        jobstack 저장소 경로 (기본: 이 스크립트의 상위 디렉토리)
  EVALS_DIR   evals.json 이 있는 디렉토리 (기본: 이 스크립트와 나란한 ../evals)

claude CLI 를 찾지 못하거나 --dry-run 이면 실제 실행 없이 케이스·명령만 나열하고 exit 0 한다.
3계층(gate/periodic/e2e) 설명·비용 추정 방식·케이스 추가 규칙은 docs/evals.md 를 참조하라.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tier)
      TIER="${2:-}"
      case "$TIER" in gate|periodic|e2e) ;; *) echo "[오류] --tier 는 gate|periodic|e2e 중 하나여야 합니다: '$TIER'" >&2; exit 1 ;; esac
      shift 2 ;;
    --judge-model)
      [ $# -ge 2 ] || { echo "옵션 --judge-model 에 값이 필요합니다." >&2; exit 1; }
      JUDGE_MODEL="$2"; shift 2 ;;
    --skill)
      [ $# -ge 2 ] || { echo "[오류] --skill 에 값이 필요합니다." >&2; exit 1; }
      SKILL_FILTER="$2"; shift 2 ;;
    --model)
      [ $# -ge 2 ] || { echo "[오류] --model 에 값이 필요합니다." >&2; exit 1; }
      MODEL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --trigger) TRIGGER_MODE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[오류] 알 수 없는 인자: $1" >&2; usage; exit 1 ;;
  esac
done

# ── claude CLI 가용성 → 나열 전용(LISTING_ONLY) 여부 결정 ──────────────────────────
HAVE_CLAUDE=0
command -v claude >/dev/null 2>&1 && HAVE_CLAUDE=1
LISTING_ONLY=0
if [ "$DRY_RUN" -eq 1 ] || [ "$HAVE_CLAUDE" -eq 0 ]; then
  LISTING_ONLY=1
  if [ "$HAVE_CLAUDE" -eq 0 ] && [ "$DRY_RUN" -eq 0 ]; then
    echo "[안내] claude CLI 를 찾지 못해 dry-run 으로 전환합니다 (케이스·명령 나열만 수행, exit 0)."
  fi
fi

# ── claude -p 호출 타임아웃 — command -v timeout 이 없으면 그대로(무제한) 실행한다 ──────
# TIMEOUT_PREFIX 는 항상 최소 1개 원소(env)를 갖도록 한다 — bash 3.2 는 `set -u` 상태에서
# 빈 배열을 "${arr[@]}"로 펼치면 unbound variable 오류를 낼 수 있어(4.4 이전 버전의 알려진
# 동작), 빈 배열 자체를 만들지 않는 쪽이 버전 의존 없이 안전하다. env 는 인자 없이 붙이면
# 그냥 다음 명령을 그대로 실행하므로 claude 호출 동작에는 영향이 없다.
EVAL_TIMEOUT_S="${EVAL_TIMEOUT_S:-900}"
TIMEOUT_PREFIX=(env)
TIMEOUT_PREVIEW=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_PREFIX=(timeout "$EVAL_TIMEOUT_S")
  TIMEOUT_PREVIEW="timeout ${EVAL_TIMEOUT_S}s "
fi

# ── jf: case JSON 파일에서 점표기 키를 읽는다. 리스트는 한 줄에 하나, 스칼라는 한 줄 ──
# (jq 미의존 — 표준 라이브러리 json 만 사용)
jf() { # $1=case_file $2=dotted-key
  python3 -c '
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
cur = d
for part in sys.argv[2].split("."):
    cur = cur.get(part) if isinstance(cur, dict) else None
    if cur is None:
        break
if isinstance(cur, list):
    for v in cur:
        print(v)
elif isinstance(cur, bool):
    print("true" if cur else "false")
elif cur is None:
    pass
else:
    print(cur)
' "$1" "$2"
}

# ── evals.json 을 읽어 (선택적 tier 필터 후) 케이스마다 임시 JSON 파일을 만들고 경로를 출력 ──
list_and_stage_cases() { # $1=evals.json $2=tier필터(빈문자열=전체) $3=스테이징 디렉토리
  python3 - "$1" "$2" "$3" <<'PY'
import json, os, sys

path, tier_filter, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path, encoding='utf-8'))
skill = d['skill']
os.makedirs(out_dir, exist_ok=True)
for c in d.get('cases', []) or []:
    if tier_filter and c.get('tier') != tier_filter:
        continue
    c = dict(c)
    c['skill'] = skill
    fn = os.path.join(out_dir, f"{skill}__{c['id']}.json")
    with open(fn, 'w', encoding='utf-8') as f:
        json.dump(c, f, ensure_ascii=False)
    print(fn)
PY
}

# ── stream-json 로그 + 작업 디렉토리 산출물을 expectations 로 결정적으로 판정 ──────────
judge() { # $1=case_file $2=stream_log $3=work_dir $4=claude_exit
  python3 - "$1" "$2" "$3" "$4" <<'PY'
import json, os, sys

case_file, stream_log, work_dir, claude_exit = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
case = json.load(open(case_file, encoding='utf-8'))
exp = case.get('expectations', {}) or {}

bash_cmds, read_paths, texts, skill_calls, tool_texts = [], [], [], [], []
n_events = 0
result_event = None

if os.path.exists(stream_log):
    with open(stream_log, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            n_events += 1
            etype = ev.get('type')
            if etype == 'assistant':
                msg = ev.get('message') or {}
                for block in msg.get('content') or []:
                    btype = block.get('type')
                    if btype == 'text':
                        texts.append(block.get('text', '') or '')
                    elif btype == 'tool_use':
                        name = block.get('name', '')
                        inp = block.get('input') or {}
                        if name == 'Bash':
                            bash_cmds.append(str(inp.get('command', '')))
                        elif name == 'Read':
                            p = inp.get('file_path') or inp.get('path') or ''
                            read_paths.append(str(p))
                        elif name == 'Skill':
                            skill_calls.append(str(inp.get('skill') or inp.get('name') or ''))
            elif etype == 'user':
                # 도구 결과(Bash 출력 등) — must_output 판정용. 사용자 화면에도 보이는 텍스트다.
                msg = ev.get('message') or {}
                content = msg.get('content')
                if isinstance(content, list):
                    for block in content:
                        if isinstance(block, dict) and block.get('type') == 'tool_result':
                            c = block.get('content')
                            if isinstance(c, str):
                                tool_texts.append(c)
                            elif isinstance(c, list):
                                tool_texts.append('\n'.join(str(x.get('text', '')) for x in c if isinstance(x, dict)))
            elif etype == 'result':
                result_event = ev

assistant_text = '\n'.join(texts)
bash_blob = '\n'.join(bash_cmds)
read_blob = '\n'.join(read_paths)
tool_blob = '\n'.join(tool_texts)

# must_contain 은 "최종 산출 텍스트 + 작업 디렉토리 생성 파일"에 대해 판정한다.
file_texts = []
if os.path.isdir(work_dir):
    for root, _dirs, files in os.walk(work_dir):
        for fn in files:
            fp = os.path.join(root, fn)
            try:
                with open(fp, encoding='utf-8', errors='ignore') as fh:
                    file_texts.append(fh.read())
            except OSError:
                pass
haystack = assistant_text + '\n' + '\n'.join(file_texts)

checks = []
def add_check(category, token, ok):
    checks.append({'category': category, 'token': token, 'pass': bool(ok)})

for token in exp.get('must_contain') or []:
    add_check('must_contain', token, token in haystack)
for token in exp.get('must_not_contain') or []:
    add_check('must_not_contain', token, token not in haystack)
for token in exp.get('must_call') or []:
    words = token.split()
    add_check('must_call', token, bool(words) and all(w in bash_blob for w in words))
for token in exp.get('must_read') or []:
    add_check('must_read', token, token in read_blob)
# must_output: 도구 결과(스크립트 stdout)에 있어야 하는 토큰 — 모델이 출력을 요약해도 스크립트가 실제로 낸 값을 판정한다.
for token in exp.get('must_output') or []:
    add_check('must_output', token, token in tool_blob)

no_events = (n_events == 0)
timed_out = (claude_exit == 124)  # timeout(1) 이 죽였을 때의 종료 코드 — 부분 이벤트가 남아도 FAIL 처리
deterministic_pass = (not no_events) and (not timed_out) and all(c['pass'] for c in checks)

out = {
    'skill': case.get('skill'), 'id': case.get('id'), 'tier': case.get('tier'),
    'grader': case.get('grader'), 'claude_exit': claude_exit, 'num_events': n_events,
    'bash_command_count': len(bash_cmds), 'read_count': len(read_paths),
    'skill_calls': skill_calls, 'checks': checks,
    'deterministic_pass': deterministic_pass, 'pass': deterministic_pass,
    'no_events_parsed': no_events, 'timed_out': timed_out,
}
if result_event is not None:
    out['result_summary'] = {
        'num_turns': result_event.get('num_turns'),
        'total_cost_usd': result_event.get('total_cost_usd'),
        'is_error': result_event.get('is_error'),
    }
print(json.dumps(out, ensure_ascii=False))
PY
}

# ── grader:"llm" 케이스의 채점 프롬프트를 만든다 (기대 특성 목록 → PASS/FAIL JSON 요청) ──
build_grading_prompt() { # $1=case_file $2=stream_log
  python3 - "$1" "$2" <<'PY'
import json, os, sys

case_file, stream_log = sys.argv[1], sys.argv[2]
case = json.load(open(case_file, encoding='utf-8'))
exp = case.get('expectations', {}) or {}

texts = []
if os.path.exists(stream_log):
    with open(stream_log, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get('type') == 'assistant':
                for block in (ev.get('message') or {}).get('content') or []:
                    if block.get('type') == 'text':
                        texts.append(block.get('text', '') or '')
transcript = '\n'.join(texts)[-8000:]

lines = []
lines.append(f"다음은 jobstack '{case.get('skill')}' 스킬 케이스 '{case.get('id')}' 실행 결과입니다. "
              "산출 텍스트가 기대 특성을 만족하는지 채점하세요. 산출물 자체를 다시 작성하거나 "
              "고치려 하지 말고, 채점만 하세요.")
lines.append('')
lines.append('[사용자 요청]')
lines.append((case.get('prompt') or '')[:2000])
lines.append('')
lines.append('[산출 텍스트]')
lines.append(transcript if transcript else '(텍스트 없음)')
lines.append('')
lines.append('[기대 특성 — 포함해야 함]')
for t in exp.get('must_contain') or []:
    lines.append(f'- {t}')
lines.append('')
lines.append('[기대 특성 — 포함하면 안 됨]')
for t in exp.get('must_not_contain') or []:
    lines.append(f'- {t}')
note = case.get('note')
if note:
    lines.append('')
    lines.append('[채점 시 특히 확인할 점]')
    lines.append(note)
lines.append('')
lines.append('반드시 다음 JSON 한 줄만 출력하세요(다른 텍스트·설명 금지): '
              '{"verdict":"PASS 또는 FAIL","reason":"한 줄 이유"}')
print('\n'.join(lines))
PY
}

# ── haiku 채점 결과를 결정적 verdict 에 병합한다 (둘 다 통과해야 최종 PASS) ────────────
merge_llm_verdict() { # $1=verdict_file $2=llm_stream_log
  python3 - "$1" "$2" <<'PY'
import json, os, re, sys

verdict_file, llm_stream = sys.argv[1], sys.argv[2]
verdict = json.load(open(verdict_file, encoding='utf-8'))

llm_text = ''
if os.path.exists(llm_stream):
    with open(llm_stream, encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get('type') == 'assistant':
                for block in (ev.get('message') or {}).get('content') or []:
                    if block.get('type') == 'text':
                        llm_text += block.get('text', '') or ''

llm_verdict, llm_reason = None, ''
m = re.search(r'\{.*"verdict"\s*:\s*"(PASS|FAIL)".*\}', llm_text, re.S)
if m:
    try:
        obj = json.loads(m.group(0))
        v = str(obj.get('verdict', '')).upper()
        llm_verdict = v if v in ('PASS', 'FAIL') else None
        llm_reason = obj.get('reason', '')
    except json.JSONDecodeError:
        pass
if llm_verdict is None:
    # 관대한 폴백 — 채점 모델이 JSON 형식을 못 지켰어도 PASS/FAIL 단어로 판정
    if re.search(r'\bFAIL\b', llm_text):
        llm_verdict = 'FAIL'
    elif re.search(r'\bPASS\b', llm_text):
        llm_verdict = 'PASS'

verdict['llm_verdict'] = llm_verdict
verdict['llm_reason'] = llm_reason
verdict['llm_raw_text'] = llm_text[:2000]
if llm_verdict is None:
    verdict['pass'] = False
    verdict['llm_grading_failed'] = True
else:
    verdict['pass'] = bool(verdict.get('deterministic_pass')) and (llm_verdict == 'PASS')

print(json.dumps(verdict, ensure_ascii=False))
PY
}

# ── 케이스 1건 실행(또는 나열) ──────────────────────────────────────────────────
run_case() { # $1=case_file
  local case_file="$1"
  local skill_name id tier grader prompt max_turns
  skill_name="$(jf "$case_file" skill)"
  id="$(jf "$case_file" id)"
  tier="$(jf "$case_file" tier)"
  grader="$(jf "$case_file" grader)"
  prompt="$(jf "$case_file" prompt)"
  max_turns="$(jf "$case_file" expectations.max_turns)"
  [ -z "$max_turns" ] && max_turns=10

  echo "── [$skill_name/$id] tier=$tier grader=$grader max_turns=$max_turns ──"

  if [ "$LISTING_ONLY" -eq 1 ]; then
    local preview; preview="$(printf '%s' "$prompt" | tr '\n' ' ' | cut -c1-100)"
    echo "  prompt: ${preview}..."
    local f; while IFS= read -r f; do [ -n "$f" ] && echo "  file: $f"; done < <(jf "$case_file" files)
    local s; while IFS= read -r s; do [ -n "$s" ] && echo "  setup: $s"; done < <(jf "$case_file" setup)
    echo "  실행 예정: ${TIMEOUT_PREVIEW}claude -p --output-format stream-json --verbose --model $MODEL --permission-mode auto --max-turns $max_turns \"<prompt>\""
    [ "$grader" = "llm" ] && echo "  채점 예정: ${TIMEOUT_PREVIEW}claude -p --output-format stream-json --verbose --model $JUDGE_MODEL --max-turns 1 \"<채점 프롬프트>\""
    TOTAL_LISTED=$((TOTAL_LISTED + 1))
    return 0
  fi

  TOTAL_RUN=$((TOTAL_RUN + 1))
  local iso_home work_dir stream_log
  iso_home="$(mktemp -d "${TMPDIR:-/tmp}/jobstack-eval-home.XXXXXX")" || {
    echo "  [FAIL] 격리 HOME 생성 실패"
    printf '{"skill":"%s","id":"%s","tier":"%s","grader":"%s","pass":false,"deterministic_pass":false,"checks":[],"no_events_parsed":true,"note":"격리 HOME 생성 실패"}\n' \
      "$skill_name" "$id" "$tier" "$grader" >> "$RESULTS_JSONL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  }

  if ! ( cd "$REPO" && HOME="$iso_home" JOBSTACK_STATE_DIR="$iso_home/.jobstack" bash install.sh ) \
        >"$iso_home/install.log" 2>&1; then
    echo "  [FAIL] install.sh 실패 — 로그: $iso_home/install.log"
    printf '{"skill":"%s","id":"%s","tier":"%s","grader":"%s","pass":false,"deterministic_pass":false,"checks":[],"no_events_parsed":true,"note":"install.sh 실패"}\n' \
      "$skill_name" "$id" "$tier" "$grader" >> "$RESULTS_JSONL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  work_dir="$iso_home/workspace"
  mkdir -p "$work_dir"

  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    cp "$REPO/$f" "$work_dir/$(basename "$f")" 2>>"$iso_home/install.log"
  done < <(jf "$case_file" files)

  local s
  while IFS= read -r s; do
    [ -z "$s" ] && continue
    ( cd "$work_dir" && REPO="$REPO" STATE_DIR="$iso_home/.jobstack" HOME="$iso_home" bash -c "$s" ) \
      >>"$iso_home/setup.log" 2>&1
  done < <(jf "$case_file" setup)

  stream_log="$iso_home/stream.jsonl"
  ( cd "$work_dir" && HOME="$iso_home" JOBSTACK_STATE_DIR="$iso_home/.jobstack" \
    "${TIMEOUT_PREFIX[@]}" claude -p --output-format stream-json --verbose --model "$MODEL" \
      --permission-mode auto --max-turns "$max_turns" "$prompt" \
  ) >"$stream_log" 2>"$iso_home/stderr.log" </dev/null
  local claude_exit=$?

  local verdict_file="$iso_home/verdict.json"
  judge "$case_file" "$stream_log" "$work_dir" "$claude_exit" > "$verdict_file"

  if [ "$grader" = "llm" ]; then
    local grading_prompt llm_stream
    grading_prompt="$(build_grading_prompt "$case_file" "$stream_log")"
    llm_stream="$iso_home/llm-grade.jsonl"
    ( cd "$work_dir" && HOME="$iso_home" \
      "${TIMEOUT_PREFIX[@]}" claude -p --output-format stream-json --verbose --model "$JUDGE_MODEL" --permission-mode auto --max-turns 1 "$grading_prompt" \
    ) >"$llm_stream" 2>>"$iso_home/stderr.log" </dev/null
    merge_llm_verdict "$verdict_file" "$llm_stream" > "$iso_home/verdict-final.json"
    mv "$iso_home/verdict-final.json" "$verdict_file"
  fi

  cat "$verdict_file" >> "$RESULTS_JSONL"
  local pass; pass="$(jf "$verdict_file" pass)"
  if [ "$pass" = "true" ]; then
    echo "  [PASS]"
    rm -rf "$iso_home"
  else
    echo "  [FAIL] — 로그 보존: $iso_home (verdict.json·stream.jsonl·stderr.log)"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

# ── 실행 결과 JSONL → eval-report.md + eval-report.json ───────────────────────
render_report() { # $1=results.jsonl
  python3 - "$1" "$REPORT_MD" "$REPORT_JSON" <<'PY'
import json, sys
from datetime import datetime, timedelta, timezone

results_path, md_path, json_path = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
try:
    with open(results_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
except FileNotFoundError:
    pass

now = datetime.now(timezone(timedelta(hours=9))).strftime('%Y-%m-%d %H:%M KST')
total = len(rows)
passed = sum(1 for r in rows if r.get('pass'))

lines = [
    '# jobstack eval 리포트', '',
    f'생성: {now} · 총 {total}건 · 통과 {passed}건 · 실패 {total - passed}건', '',
    '| 스킬 | 케이스 | tier | grader | 판정 | 근거 요약 |',
    '|---|---|---|---|---|---|',
]
for r in rows:
    verdict = 'PASS' if r.get('pass') else 'FAIL'
    ev = []
    if r.get('timed_out') or r.get('claude_exit') == 124:
        ev.append('timeout')
    if r.get('no_events_parsed'):
        ev.append('실행 로그 없음')
    if r.get('note') and not r.get('checks'):
        ev.append(r['note'])
    for c in [c for c in r.get('checks', []) if not c.get('pass')][:3]:
        ev.append(f"{c['category']}:{str(c['token'])[:24]}")
    if r.get('grader') == 'llm':
        ev.append(f"llm={r.get('llm_verdict')}")
    lines.append(f"| {r.get('skill')} | {r.get('id')} | {r.get('tier')} | {r.get('grader')} | {verdict} | {'; '.join(ev) or '-'} |")

with open(md_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump({'generated_at': now, 'total': total, 'passed': passed, 'failed': total - passed, 'results': rows},
               f, ensure_ascii=False, indent=2)
print(f'[리포트] {md_path} · {json_path} (통과 {passed}/{total})')
PY
}

# ── should_trigger 쿼리 1건 실행(또는 나열) ────────────────────────────────────
run_trigger_query() { # $1=skill $2=query $3=expect(true/false)
  local skill_name="$1" query="$2" expect="$3"
  TRIGGER_TOTAL=$((TRIGGER_TOTAL + 1))

  if [ "$LISTING_ONLY" -eq 1 ]; then
    echo "  expect=$expect  \"$query\""
    return 0
  fi

  local iso_home stream_log
  iso_home="$(mktemp -d "${TMPDIR:-/tmp}/jobstack-trigger-home.XXXXXX")" || {
    echo "  [FAIL] 격리 HOME 생성 실패"
    printf '{"skill":"%s","query":%s,"expect":%s,"triggered":null,"pass":false}\n' \
      "$skill_name" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$query")" \
      "$([ "$expect" = true ] && echo true || echo false)" >> "$TRIGGER_RESULTS_JSONL"
    TRIGGER_FAIL=$((TRIGGER_FAIL + 1))
    return 1
  }
  ( cd "$REPO" && HOME="$iso_home" JOBSTACK_STATE_DIR="$iso_home/.jobstack" bash install.sh ) \
    >"$iso_home/install.log" 2>&1

  stream_log="$iso_home/stream.jsonl"
  ( cd "$iso_home" && HOME="$iso_home" JOBSTACK_STATE_DIR="$iso_home/.jobstack" \
    "${TIMEOUT_PREFIX[@]}" claude -p --output-format stream-json --verbose --model "$MODEL" \
      --permission-mode auto --max-turns 1 "$query" \
  ) >"$stream_log" 2>"$iso_home/stderr.log" </dev/null
  local claude_exit=$?

  local triggered
  triggered="$(python3 - "$stream_log" <<'PY'
import json, sys
skills = []
try:
    with open(sys.argv[1], encoding='utf-8', errors='replace') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except json.JSONDecodeError:
                continue
            if ev.get('type') == 'assistant':
                for block in (ev.get('message') or {}).get('content') or []:
                    if block.get('type') == 'tool_use' and block.get('name') == 'Skill':
                        inp = block.get('input') or {}
                        skills.append(str(inp.get('skill') or inp.get('name') or ''))
except FileNotFoundError:
    pass
print(skills[0] if skills else '')
PY
)"

  local row
  row="$(python3 - "$skill_name" "$query" "$expect" "$triggered" "$claude_exit" <<'PY'
import json, sys
skill, query, expect, triggered, claude_exit = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
expect_b = (expect == 'true')
timed_out = (claude_exit == 124)
actual_b = (triggered == skill) and not timed_out
row = {'skill': skill, 'query': query, 'expect': expect_b,
       'triggered': (triggered or None), 'pass': (actual_b == expect_b) and not timed_out}
if timed_out:
    row['timed_out'] = True
print(json.dumps(row, ensure_ascii=False))
PY
)"
  echo "$row" >> "$TRIGGER_RESULTS_JSONL"

  local pass timed_out_tag=""
  pass="$(printf '%s' "$row" | python3 -c 'import json,sys; print("true" if json.load(sys.stdin)["pass"] else "false")')"
  printf '%s' "$row" | python3 -c 'import json,sys; sys.exit(0 if json.load(sys.stdin).get("timed_out") else 1)' && timed_out_tag=" (timeout)"
  if [ "$pass" = "true" ]; then
    echo "  [PASS] expect=$expect actual=${triggered:-<없음>}  \"$query\""
  else
    echo "  [FAIL]${timed_out_tag} expect=$expect actual=${triggered:-<없음>}  \"$query\""
    TRIGGER_FAIL=$((TRIGGER_FAIL + 1))
  fi
  rm -rf "$iso_home"
}

render_trigger_report() { # $1=results.jsonl
  python3 - "$1" "$TRIGGER_REPORT_MD" "$TRIGGER_REPORT_JSON" <<'PY'
import json, sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

results_path, md_path, json_path = sys.argv[1], sys.argv[2], sys.argv[3]
rows = []
try:
    with open(results_path, encoding='utf-8') as f:
        for line in f:
            line = line.strip()
            if line:
                rows.append(json.loads(line))
except FileNotFoundError:
    pass

now = datetime.now(timezone(timedelta(hours=9))).strftime('%Y-%m-%d %H:%M KST')
by_skill = defaultdict(lambda: {'tp': 0, 'fp': 0, 'tn': 0, 'fn': 0})
for r in rows:
    sk = r['skill']
    expect, actual = r['expect'], (r.get('triggered') == sk)
    key = ('tp' if expect and actual else 'fn' if expect and not actual
           else 'fp' if actual else 'tn')
    by_skill[sk][key] += 1

lines = ['# jobstack 트리거 정확도 리포트', '', f'생성: {now} · 총 {len(rows)}건', '',
         '| 스킬 | TP | FP | TN | FN | 정확도 |', '|---|---|---|---|---|---|']
for sk, c in sorted(by_skill.items()):
    total = c['tp'] + c['fp'] + c['tn'] + c['fn']
    acc = f"{100 * (c['tp'] + c['tn']) / total:.0f}%" if total else '-'
    lines.append(f"| {sk} | {c['tp']} | {c['fp']} | {c['tn']} | {c['fn']} | {acc} |")
lines += ['', 'FP = 관계없는 요청인데 이 스킬이 뜸(과잉 트리거) · FN = 이 스킬이 떠야 하는데 안 뜸(과소 트리거)']

with open(md_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines) + '\n')
with open(json_path, 'w', encoding='utf-8') as f:
    json.dump({'generated_at': now, 'by_skill': by_skill, 'rows': rows}, f, ensure_ascii=False, indent=2)
print(f'[리포트] {md_path} · {json_path}')
PY
}

run_trigger_mode() {
  TRIGGER_TOTAL=0
  TRIGGER_FAIL=0
  TRIGGER_RESULTS_JSONL="$(mktemp "${TMPDIR:-/tmp}/jobstack-trigger-results.XXXXXX")"
  if [ "$LISTING_ONLY" -eq 0 ]; then
    echo "[비용 안내] --trigger 는 스킬마다 8~10건, claude -p --max-turns 1 을 쿼리 수만큼 호출합니다 —"
    echo "            케이스당 1턴이라도 모델 호출 자체는 과금 대상입니다(docs/evals.md 비용 추정 방식 참조)."
  fi

  local matched=0
  local ef sk
  for ef in "${EVAL_FILES[@]}"; do
    sk="$(basename "$(dirname "$ef")")"
    if [ -n "$SKILL_FILTER" ] && [ "$sk" != "$SKILL_FILTER" ]; then continue; fi
    matched=$((matched + 1))
    echo ""
    echo "=== should_trigger: $sk ==="
    local q e
    while IFS=$'\t' read -r q e; do
      [ -z "$q" ] && continue
      run_trigger_query "$sk" "$q" "$e"
    done < <(python3 - "$ef" <<'PY'
import json, sys
d = json.load(open(sys.argv[1], encoding='utf-8'))
for item in d.get('should_trigger', []) or []:
    q = str(item.get('query', '')).replace('\t', ' ').replace('\n', ' ')
    e = 'true' if item.get('expect') else 'false'
    print(f"{q}\t{e}")
PY
)
  done

  if [ "$matched" -eq 0 ]; then
    echo "[오류] --skill '$SKILL_FILTER' 와 일치하는 evals.json 을 찾지 못했습니다." >&2
    return 1
  fi

  echo ""
  if [ "$LISTING_ONLY" -eq 1 ]; then
    echo "총 ${TRIGGER_TOTAL}개 트리거 쿼리 나열됨 (실행 없음 — dry-run, exit 0)."
    rm -f "$TRIGGER_RESULTS_JSONL"
    return 0
  fi

  render_trigger_report "$TRIGGER_RESULTS_JSONL"
  rm -f "$TRIGGER_RESULTS_JSONL"
  echo "트리거 쿼리 ${TRIGGER_TOTAL}건 · 오판정 ${TRIGGER_FAIL}건"
  [ "$TRIGGER_FAIL" -eq 0 ]
}

main() {
  if [ ! -f "$REPO/install.sh" ]; then
    echo "[경고] REPO='$REPO' 에 install.sh 가 없습니다 — REPO 환경변수로 jobstack 저장소 경로를 지정하세요." >&2
    [ "$LISTING_ONLY" -eq 0 ] && exit 1
  fi

  EVAL_FILES=()
  while IFS= read -r ef_line; do EVAL_FILES+=("$ef_line"); done \
    < <(find "$EVALS_DIR" -mindepth 2 -maxdepth 2 -name evals.json 2>/dev/null | sort)
  if [ "${#EVAL_FILES[@]}" -eq 0 ]; then
    echo "[오류] $EVALS_DIR 아래에서 evals.json 을 찾지 못했습니다." >&2
    exit 1
  fi

  if [ "$TRIGGER_MODE" -eq 1 ]; then
    run_trigger_mode
    exit $?
  fi

  TOTAL_LISTED=0
  TOTAL_RUN=0
  FAIL_COUNT=0
  RESULTS_JSONL="$(mktemp "${TMPDIR:-/tmp}/jobstack-eval-results.XXXXXX")"

  local matched=0
  local ef sk stage
  for ef in "${EVAL_FILES[@]}"; do
    sk="$(basename "$(dirname "$ef")")"
    if [ -n "$SKILL_FILTER" ] && [ "$sk" != "$SKILL_FILTER" ]; then continue; fi
    matched=$((matched + 1))
    echo ""
    echo "=== $sk ($ef) ==="
    stage="$(mktemp -d "${TMPDIR:-/tmp}/jobstack-eval-stage.XXXXXX")"
    local case_file
    while IFS= read -r case_file; do
      run_case "$case_file"
    done < <(list_and_stage_cases "$ef" "$TIER" "$stage")
    rm -rf "$stage"
  done

  if [ "$matched" -eq 0 ]; then
    echo "[오류] --skill '$SKILL_FILTER' 와 일치하는 evals.json 을 찾지 못했습니다." >&2
    rm -f "$RESULTS_JSONL"
    exit 1
  fi

  echo ""
  if [ "$LISTING_ONLY" -eq 1 ]; then
    echo "총 ${TOTAL_LISTED}개 케이스 나열됨 (실행 없음 — dry-run, exit 0)."
    rm -f "$RESULTS_JSONL"
    exit 0
  fi

  render_report "$RESULTS_JSONL"
  rm -f "$RESULTS_JSONL"
  echo "실행 ${TOTAL_RUN}건 · 실패 ${FAIL_COUNT}건"
  [ "$FAIL_COUNT" -eq 0 ]
}

main
