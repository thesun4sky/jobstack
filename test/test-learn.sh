#!/usr/bin/env bash
# test-learn.sh — jobstack-learn add/top/list/validate 회귀 테스트 (검토 보고서 U-20 초안).
#
# test-fetch-diag-summary.sh 와 같은 방식: mktemp 로 격리된 로그 파일에 CLI 를 서브프로세스로
# 실행해 stdout/stderr/exit code 를 검사하는 블랙박스 테스트. 네트워크 불필요, 표준 라이브러리만
# 사용한다. 통합 시 이 파일은 jobstack 저장소의 test/test-learn.sh 로 옮기고, SCRIPT 경로를
# 실제 bin/jobstack-learn 으로 바꾼다(현재는 이 초안 트리 안의 bin/jobstack-learn 을 가리킨다).
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../bin/jobstack-learn"

python3 - "$SCRIPT" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
import shutil
from datetime import datetime, timedelta, timezone

SCRIPT = sys.argv[1]
PY_EXE = sys.executable

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))


def run(args, env=None, cwd=None):
    # JOBSTACK_STATE_DIR/JOBSTACK_LEARN_LOG 를 기본적으로 비워 테스트 간 격리를 보장하고,
    # 경로 해석 순서를 검증하는 케이스에서만 명시적으로 채운다(test-fetch-diag-summary.sh 와 동일 패턴).
    full_env = dict(os.environ)
    full_env.pop("JOBSTACK_STATE_DIR", None)
    full_env.pop("JOBSTACK_LEARN_LOG", None)
    if env:
        full_env.update(env)
    r = subprocess.run(
        [PY_EXE, SCRIPT, *args], env=full_env, cwd=cwd,
        capture_output=True, text=True, timeout=15,
    )
    return r.returncode, r.stdout, r.stderr


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [ln for ln in f.read().splitlines() if ln.strip()]


def write_lines(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for o in objs:
            f.write(o if isinstance(o, str) else json.dumps(o, ensure_ascii=False))
            f.write("\n")


TMP = tempfile.mkdtemp(prefix="jobstack-learn-test-")
try:
    LOG = os.path.join(TMP, "learnings.jsonl")

    # ── add: 기본 성공 ──────────────────────────────────────────────────
    code, out, err = run(["add", "--skill", "job-search", "--kind", "selector_broken",
                           "--key", "saramin.item_recruit", "--note", "목록 셀렉터 응답 0건",
                           "--session", "sess-1", "--file", LOG])
    check("add 기본: exit 0", code == 0, err)
    check("add 기본: 확인 메시지 출력", "saramin.item_recruit" in out, out)
    lines = read_lines(LOG)
    check("add 기본: 파일에 1줄 기록", len(lines) == 1, lines)
    if lines:
        rec = json.loads(lines[0])
        check("add 기본: 필드 6종 구성(dup 없음)", set(rec) == {"ts", "skill", "kind", "key", "note", "session"}, rec)
        check("add 기본: skill/kind/key/note/session 값 일치",
              rec.get("skill") == "job-search" and rec.get("kind") == "selector_broken"
              and rec.get("key") == "saramin.item_recruit" and rec.get("note") == "목록 셀렉터 응답 0건"
              and rec.get("session") == "sess-1", rec)
        check("add 기본: ts 가 UTC ISO8601(Z)", isinstance(rec.get("ts"), str) and rec["ts"].endswith("Z"), rec)

    # ── add: note/session 생략 시 필드도 생략 ───────────────────────────
    log2 = os.path.join(TMP, "l2.jsonl")
    code, out, err = run(["add", "--skill", "resume", "--kind", "other", "--key", "abc.def", "--file", log2])
    check("add note 생략: exit 0", code == 0, err)
    rec2 = json.loads(read_lines(log2)[0])
    check("add note 생략: note/session 필드 없음", "note" not in rec2 and "session" not in rec2, rec2)

    # ── add: 24시간 내 중복 → dup:true, 24시간 밖 → dup 없음 ────────────
    code, out, err = run(["add", "--skill", "job-search", "--kind", "selector_broken",
                           "--key", "saramin.item_recruit", "--file", LOG])
    check("add 중복(24h 내): exit 0", code == 0, err)
    check("add 중복(24h 내): 출력에 dup 표기", "dup" in out, out)
    lines = read_lines(LOG)
    check("add 중복(24h 내): 파일 2줄", len(lines) == 2, lines)
    if len(lines) == 2:
        rec_dup = json.loads(lines[1])
        check("add 중복(24h 내): dup:true 로 새 줄 추가(기존 줄은 안 건드림)", rec_dup.get("dup") is True, rec_dup)
        rec_first = json.loads(lines[0])
        check("add 중복(24h 내): 첫 줄은 그대로(고쳐쓰지 않음, dup 없음)", "dup" not in rec_first, rec_first)

    log3 = os.path.join(TMP, "l3-old-dup.jsonl")
    old_ts = (datetime.now(timezone.utc) - timedelta(hours=30)).strftime("%Y-%m-%dT%H:%M:%SZ")
    write_lines(log3, [{"ts": old_ts, "skill": "job-search", "kind": "selector_broken", "key": "wanted.due_time"}])
    code, out, err = run(["add", "--skill", "job-search", "--kind", "selector_broken",
                           "--key", "wanted.due_time", "--file", log3])
    check("add 중복(24h 밖): exit 0", code == 0, err)
    check("add 중복(24h 밖): dup 아님", "dup" not in out, out)
    rec_old = json.loads(read_lines(log3)[1])
    check("add 중복(24h 밖): dup 필드 없음", "dup" not in rec_old, rec_old)

    # ── add: 인자·형식 오류 → exit 2, 파일 미기록 ───────────────────────
    log_err = os.path.join(TMP, "l-err.jsonl")
    code, out, err = run(["add", "--skill", "job-search", "--file", log_err])
    check("add 필수값 누락: exit 2", code == 2, err)
    code, out, err = run(["add", "--skill", "job-search", "--kind", "bogus_kind",
                           "--key", "a.b", "--file", log_err])
    check("add kind 어휘 밖: exit 2", code == 2, err)
    check("add kind 어휘 밖: 허용값 안내", "selector_broken" in err, err)
    code, out, err = run(["add", "--skill", "job-search", "--kind", "other",
                           "--key", "Not Valid Key!", "--file", log_err])
    check("add key 형식 오류: exit 2", code == 2, err)
    long_note = "가" * 61
    code, out, err = run(["add", "--skill", "job-search", "--kind", "other",
                           "--key", "a.b", "--note", long_note, "--file", log_err])
    check("add note 60자 초과: exit 2", code == 2, err)
    check("add note 60자 초과: 파일 미생성(거부 시 append 안 함)", not os.path.exists(log_err), "")

    # ── add: PII 휴리스틱 거부 → exit 1, 파일 미기록 ────────────────────
    pii_cases = [
        ("이메일", "담당자 test.user@example.com 확인 요청"),
        ("전화번호", "010-1234-5678 로 회신 요청"),
        ("URL 쿼리", "링크 https://x.example/apply?ref=abc123 로 지원"),
        ("한글 이름(라벨:이름)", "담당자: 김민수"),
        ("한글 이름(예시 placeholder)", "홍길동 이력서 확인 필요"),
    ]
    for label, note in pii_cases:
        logp = os.path.join(TMP, "l-pii.jsonl")
        if os.path.exists(logp):
            os.remove(logp)
        code, out, err = run(["add", "--skill", "job-search", "--kind", "data_requested",
                               "--key", "pii.case", "--note", note, "--file", logp])
        check(f"add PII 거부({label}): exit 1", code == 1, f"note={note!r} err={err}")
        check(f"add PII 거부({label}): 파일 미기록", not os.path.exists(logp), "")

    # ── add: PII 휴리스틱과 유사하지만 실제로는 안전한 문구 → 통과(오탐 방지) ──
    safe_cases = [
        "담당자 확인 필요 반복",     # 라벨 뒤 콜론이 없으므로 이름 패턴 아님
        "고객님 회사명 요청 반복",   # 님이 흔한 존칭에 붙었을 뿐 이름이 아님
        "이력서 PDF 표 깨짐 반복",   # '이력서' 자체를 이름으로 오인하지 않음
    ]
    for note in safe_cases:
        logs = os.path.join(TMP, "l-safe.jsonl")
        if os.path.exists(logs):
            os.remove(logs)
        code, out, err = run(["add", "--skill", "job-search", "--kind", "format_mismatch",
                               "--key", "safe.case", "--note", note, "--file", logs])
        check(f"add 오탐 방지({note!r}): exit 0", code == 0, err)

    # ── key 의 PII 검사 (charset 이 막지만, 이중 방어로 명시 검사) ──────
    logk = os.path.join(TMP, "l-key-pii.jsonl")
    code, out, err = run(["add", "--skill", "job-search", "--kind", "other",
                           "--key", "test@example.com", "--file", logk])
    check("add key 형식/PII: 이메일 모양 key → exit 2(charset 위반이 먼저 걸림)", code == 2, err)

    # ══════════════════════════════════════════════════════════════════
    # top
    # ══════════════════════════════════════════════════════════════════
    empty_log = os.path.join(TMP, "no-such-learnings.jsonl")
    code, out, err = run(["top", "--file", empty_log])
    check("top 빈 로그(파일 없음): exit 0", code == 0, err)
    check("top 빈 로그(파일 없음): 빈 출력", out == "", repr(out))

    top_log = os.path.join(TMP, "top.jsonl")
    now = datetime.now(timezone.utc)

    def ts(delta):
        return (now - delta).strftime("%Y-%m-%dT%H:%M:%SZ")

    write_lines(top_log, [
        {"ts": ts(timedelta(hours=1)), "skill": "job-search", "kind": "selector_broken",
         "key": "saramin.item_recruit", "note": "n1"},
        {"ts": ts(timedelta(hours=5)), "skill": "job-search", "kind": "selector_broken",
         "key": "saramin.item_recruit", "dup": True},
        {"ts": ts(timedelta(hours=10)), "skill": "company-research", "kind": "selector_broken",
         "key": "saramin.item_recruit", "dup": True},
        {"ts": ts(timedelta(days=2)), "skill": "job-search", "kind": "source_blocked",
         "key": "wanted.api_v4"},
        {"ts": ts(timedelta(days=1)), "skill": "resume", "kind": "data_requested",
         "key": "career.gap_reason"},
        {"ts": ts(timedelta(days=40)), "skill": "salary", "kind": "tool_missing",
         "key": "pandoc"},
        "not-a-json-object",
        {"skill": "job-search", "kind": "other", "key": "no_ts_field"},
    ])

    code, out, err = run(["top", "--file", top_log])
    check("top 기본: exit 0", code == 0, err)
    top_lines = [ln for ln in out.splitlines() if ln.strip()]
    check("top 기본: 기본 n=3 → 정확히 3줄", len(top_lines) == 3, out)
    check("top 기본: 1위는 saramin.item_recruit ×3(중복 포함 합산, 스킬 2개 표기)",
          top_lines and top_lines[0].startswith("- [selector_broken] saramin.item_recruit ×3")
          and "job-search" in top_lines[0] and "company-research" in top_lines[0], out)
    check("top 기본: 형식이 스펙 예시와 일치(대괄호 kind, × 건수, 최근 날짜)",
          bool(top_lines) and "(최근 " in top_lines[0] and top_lines[0].count("[") == 1, out)
    check("top 기본: 손상된 줄·ts 없는 줄은 집계에서 조용히 제외(에러 없이 exit 0)", code == 0)

    code, out, err = run(["top", "--file", top_log, "--n", "1"])
    check("top --n 1: 정확히 1줄", len([ln for ln in out.splitlines() if ln.strip()]) == 1, out)

    code, out, err = run(["top", "--file", top_log, "--n", "5"])
    top5 = [ln for ln in out.splitlines() if ln.strip()]
    check("top --n 5: 유효 그룹 4개만(5개 요청해도 초과분 없음)", len(top5) == 4, out)
    check("top --n 5: pandoc(40일 전)도 전체 기간이면 포함됨", any("pandoc" in ln for ln in top5), out)

    code, out, err = run(["top", "--file", top_log, "--since", "3d", "--n", "5"])
    top_since = [ln for ln in out.splitlines() if ln.strip()]
    check("top --since 3d: 40일 전 pandoc 제외", not any("pandoc" in ln for ln in top_since), out)
    check("top --since 3d: 최근 3건은 포함", len(top_since) == 3, out)

    code, out, err = run(["top", "--file", top_log, "--json"])
    check("top --json: exit 0", code == 0, err)
    try:
        data = json.loads(out)
        json_ok = True
    except json.JSONDecodeError:
        data = []
        json_ok = False
    check("top --json: 유효한 JSON 배열", json_ok and isinstance(data, list), out)
    if json_ok and data:
        check("top --json: 1위 항목 count=3, skills 2개(정렬됨)",
              data[0]["count"] == 3 and data[0]["skills"] == sorted(data[0]["skills"])
              and set(data[0]["skills"]) == {"job-search", "company-research"}, data[0])
        check("top --json: kind/key 필드 존재", "kind" in data[0] and "key" in data[0], data[0])

    code, out, err = run(["top", "--file", top_log, "--since", "7days"])
    check("top 잘못된 --since 형식: exit 2", code == 2, f"code={code} err={err}")
    code, out, err = run(["top", "--file", top_log, "--n", "0"])
    check("top --n 0: exit 2", code == 2, f"code={code} err={err}")
    code, out, err = run(["top", "--file", top_log, "--n", "abc"])
    check("top --n 비정수: exit 2", code == 2, f"code={code} err={err}")

    # ══════════════════════════════════════════════════════════════════
    # list
    # ══════════════════════════════════════════════════════════════════
    code, out, err = run(["list", "--file", top_log, "--skill", "job-search"])
    check("list --skill: exit 0", code == 0, err)
    js_lines = [ln for ln in out.splitlines() if ln.strip()]
    # top_log 픽스처에는 job-search 태그가 붙은 ts 없는 손상 줄(no_ts_field)도 하나 섞여 있다 —
    # list 는 top 과 달리 집계용 필터링을 하지 않고 매칭되는 줄을 그대로 보여주는 것이 목적이므로
    # (스키마 문제 자체는 validate 가 잡는다) 그 줄도 포함해 4줄이 기대값이다.
    check("list --skill job-search: 4줄(selector×2 + source_blocked×1 + ts없는 손상줄×1)", len(js_lines) == 4, out)
    check("list --skill job-search: ts 없는 줄은 '(ts 없음)'으로 표시", any("(ts 없음)" in ln for ln in js_lines), out)
    check("list --skill job-search: 다른 스킬 행 없음",
          all("company-research" not in ln and "resume" not in ln and "salary" not in ln for ln in js_lines), out)

    code, out, err = run(["list", "--file", top_log, "--kind", "selector_broken"])
    kind_lines = [ln for ln in out.splitlines() if ln.strip()]
    check("list --kind selector_broken: 3줄(스킬 무관 전체)", len(kind_lines) == 3, out)

    code, out, err = run(["list", "--file", top_log, "--skill", "no-such-skill"])
    check("list 매칭 없음: '기록 없음' 출력 + exit 0", code == 0 and out.strip() == "기록 없음", out)

    code, out, err = run(["list", "--file", top_log, "--json"])
    try:
        list_data = json.loads(out)
        list_json_ok = isinstance(list_data, list)
    except json.JSONDecodeError:
        list_json_ok = False
    check("list --json: 유효한 JSON 배열", list_json_ok, out)

    # ══════════════════════════════════════════════════════════════════
    # validate
    # ══════════════════════════════════════════════════════════════════
    code, out, err = run(["validate", "--file", empty_log])
    check("validate 파일 없음: exit 0 + 안내", code == 0 and "기록 없음" in out, out)

    clean_log = os.path.join(TMP, "clean.jsonl")
    code, out, err = run(["add", "--skill", "job-search", "--kind", "other",
                           "--key", "clean.entry", "--note", "정상 메모입니다", "--file", clean_log])
    check("validate 사전 준비(add): exit 0", code == 0, err)
    code, out, err = run(["validate", "--file", clean_log])
    check("validate 정상 파일: exit 0 + OK", code == 0 and "[OK]" in out, out)

    code, out, err = run(["validate", "--file", top_log])
    check("validate 손상 파일: exit 1(스키마 위반 존재)", code == 1, out)
    check("validate 손상 파일: JSON 아닌 줄 지적", "JSON 객체가 아님" in out or "JSON 파싱 실패" in out, out)
    check("validate 손상 파일: ts 누락 줄 지적", "ts" in out, out)

    bad_kind_log = os.path.join(TMP, "bad-kind.jsonl")
    write_lines(bad_kind_log, [
        {"ts": ts(timedelta(hours=1)), "skill": "job-search", "kind": "not_a_real_kind", "key": "a.b"},
    ])
    code, out, err = run(["validate", "--file", bad_kind_log])
    check("validate kind 어휘 위반: exit 1 + 안내", code == 1 and "어휘 밖" in out, out)

    pii_legacy_log = os.path.join(TMP, "pii-legacy.jsonl")
    write_lines(pii_legacy_log, [
        {"ts": ts(timedelta(hours=1)), "skill": "job-search", "kind": "data_requested",
         "key": "legacy.case", "note": "홍길동 확인 요청"},
    ])
    code, out, err = run(["validate", "--file", pii_legacy_log])
    check("validate 과거 PII 줄 재검사: exit 1 + PII 지적", code == 1 and "PII" in out, out)

    dup_field_log = os.path.join(TMP, "dup-field.jsonl")
    write_lines(dup_field_log, [
        {"ts": ts(timedelta(hours=1)), "skill": "job-search", "kind": "other", "key": "a.b", "dup": "yes"},
    ])
    code, out, err = run(["validate", "--file", dup_field_log])
    check("validate dup 필드가 true 가 아님: exit 1", code == 1, out)

    # ══════════════════════════════════════════════════════════════════
    # 인자 오류 일반
    # ══════════════════════════════════════════════════════════════════
    code, out, err = run([])
    check("인자 없음: exit 2", code == 2, f"code={code} err={err}")
    code, out, err = run(["bogus-command"])
    check("알 수 없는 명령: exit 2", code == 2, f"code={code} err={err}")
    code, out, err = run(["add", "--unknown-flag", "x", "--skill", "a", "--kind", "other", "--key", "a.b"])
    check("알 수 없는 옵션: exit 2", code == 2, f"code={code} err={err}")

    # ══════════════════════════════════════════════════════════════════
    # 로그 경로 기본값 해석 순서 (JOBSTACK_LEARN_LOG → JOBSTACK_STATE_DIR → ~/.jobstack)
    # ══════════════════════════════════════════════════════════════════
    resolve_log = os.path.join(TMP, "resolve.jsonl")
    write_lines(resolve_log, [
        {"ts": ts(timedelta(hours=1)), "skill": "job-search", "kind": "other", "key": "resolve.case"},
    ])
    code, out, err = run(["top", "--n", "1"], env={"JOBSTACK_LEARN_LOG": resolve_log})
    check("JOBSTACK_LEARN_LOG 로 기본 경로 해석", code == 0 and "resolve.case" in out, out + err)

    state_dir = os.path.join(TMP, "state")
    os.makedirs(os.path.join(state_dir, "analytics"), exist_ok=True)
    shutil.copy(resolve_log, os.path.join(state_dir, "analytics", "learnings.jsonl"))
    code, out, err = run(["top", "--n", "1"], env={"JOBSTACK_STATE_DIR": state_dir})
    check(
        "JOBSTACK_LEARN_LOG 없을 때 JOBSTACK_STATE_DIR/analytics/learnings.jsonl 폴백",
        code == 0 and "resolve.case" in out,
        out + err,
    )

finally:
    shutil.rmtree(TMP, ignore_errors=True)

# ── 결과 출력 ────────────────────────────────────────────────────────────
pass_n = sum(1 for _, ok, _ in results if ok)
fail_n = len(results) - pass_n
for name, ok, detail in results:
    tag = "PASS" if ok else "FAIL"
    extra = f" ({detail})" if detail and not ok else ""
    print(f"  [{tag}] {name}{extra}")

print(f"\nPASS: {pass_n} / FAIL: {fail_n}")
sys.exit(1 if fail_n else 0)
PY
exit $?
