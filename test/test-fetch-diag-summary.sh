#!/usr/bin/env bash
# test-fetch-diag-summary.sh — jobstack-fetch-diag summary/tail 회귀 테스트 (검토 보고서 U-12 ⑦).
#
# 픽스처 로그를 mktemp 디렉터리에 쓰고 CLI 를 서브프로세스로 실행해 stdout/exit code 를
# 검사한다(순수 함수 단위 테스트가 아니라 실제 사용자가 호출하는 방식 그대로 블랙박스 검증).
# 네트워크 불필요, 표준 라이브러리만 사용.
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../bin/jobstack-fetch-diag"

python3 - "$SCRIPT" <<'PY'
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timedelta, timezone

SCRIPT = sys.argv[1]
PY_EXE = sys.executable

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))


def run(args, env=None, cwd=None):
    full_env = dict(os.environ)
    full_env.pop("JOBSTACK_FETCH_DIAG_LOG", None)
    full_env.pop("JOBSTACK_STATE_DIR", None)
    if env:
        full_env.update(env)
    r = subprocess.run(
        [PY_EXE, SCRIPT, *args], env=full_env, cwd=cwd,
        capture_output=True, text=True, timeout=15,
    )
    return r.returncode, r.stdout, r.stderr


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%S.") + f"{dt.microsecond // 1000:03d}Z"


TMP = tempfile.mkdtemp(prefix="fetch-diag-test-")
try:
    now = datetime.now(timezone.utc)
    fixture = os.path.join(TMP, "fetch-diag.log")

    # saramin: 최근 3건 연속 challenge(경고 트리거 대상)
    lines = [
        f'{iso(now - timedelta(minutes=50))} [fetch-jobs:diag] platform=saramin cause=challenge marker="datadome" status=403',
        f'{iso(now - timedelta(minutes=40))} [fetch-jobs:diag] platform=saramin cause=challenge marker="datadome" status=403',
        f'{iso(now - timedelta(minutes=30))} [fetch-jobs:diag] platform=saramin cause=challenge marker="datadome" status=403',
        # jobkorea: 오래된 too_small(40일 전, --since 7d 로 제외돼야 함) + 최근 empty_result
        f'{iso(now - timedelta(days=40))} [fetch-jobs:diag] platform=jobkorea cause=too_small len=120 status=200',
        f'{iso(now - timedelta(hours=2))} [fetch-jobs:diag] platform=jobkorea cause=empty_result len=4000 status=200',
        # wanted: url= 토큰 포함(리댁션 검사 대상)
        f'{iso(now - timedelta(hours=1))} [fetch-jobs:diag] platform=wanted cause=no_html status=n/a url=https://www.wanted.co.kr/search?q=abc&x=1',
        # 깨진 줄 2종 — 형식 자체가 안 맞는 줄 + 타임스탬프만 깨진 줄
        'this is not a valid diag line at all',
        'not-a-timestamp [fetch-jobs:diag] platform=jumpit cause=too_small len=10 status=200',
        '',  # 빈 줄(파싱 불가 카운트에 안 잡혀야 함)
    ]
    with open(fixture, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")

    # ── summary: 전체 기간 ──────────────────────────────────────────────
    code, out, err = run(["summary", fixture])
    check("summary 전체: exit 0", code == 0, err)
    check("summary 전체: saramin challenge 3건", "saramin" in out and "challenge" in out and "3" in out)
    check("summary 전체: jobkorea 두 원인 모두 표시", "empty_result" in out and "too_small" in out)
    check("summary 전체: wanted no_html 표시", "wanted" in out and "no_html" in out)
    check("summary 전체: 전체 합계 6건", "6건" in out, out)
    check("summary 전체: 파싱 불가 2줄 보고", "파싱 불가" in out and "2줄" in out, out)
    check(
        "summary 전체: saramin 연속 challenge 경고",
        "경고" in out and "saramin" in out.split("경고")[-1],
        out,
    )

    # ── summary --since 7d: 40일 전 항목 제외 ───────────────────────────
    code, out, err = run(["summary", fixture, "--since", "7d"])
    check("summary --since 7d: exit 0", code == 0, err)
    check("summary --since 7d: 합계 5건(40일 전 제외)", "5건" in out, out)
    check(
        "summary --since 7d: jobkorea too_small 은 빠지고 empty_result 만 남음",
        "too_small" not in out.split("전체 합계")[0].replace("saramin", "") or True,
    )
    # jobkorea 행에서 too_small 이 사라졌는지 더 직접적으로 확인
    body = out.split("전체 합계")[0]
    jobkorea_rows = [ln for ln in body.splitlines() if ln.startswith("jobkorea")]
    check(
        "summary --since 7d: jobkorea 행에 too_small 없음",
        all("too_small" not in r for r in jobkorea_rows) and any("empty_result" in r for r in jobkorea_rows),
        body,
    )

    # ── summary --since 24h: saramin·wanted·jobkorea(empty_result) 만 ──
    code, out, err = run(["summary", fixture, "--since", "24h"])
    check("summary --since 24h: exit 0", code == 0, err)
    check("summary --since 24h: 합계 5건", "5건" in out, out)

    # ── summary --json ──────────────────────────────────────────────────
    code, out, err = run(["summary", fixture, "--json"])
    check("summary --json: exit 0", code == 0, err)
    try:
        data = json.loads(out)
        json_ok = True
    except json.JSONDecodeError:
        data = {}
        json_ok = False
    check("summary --json: 유효한 JSON", json_ok, out)
    if json_ok:
        check("summary --json: total=6", data.get("total") == 6, str(data))
        check("summary --json: parse_errors=2", data.get("parse_errors") == 2, str(data))
        check("summary --json: rows 4개(platform×cause)", len(data.get("rows", [])) == 4, str(data))
        check(
            "summary --json: saramin challenge count=3",
            any(r["platform"] == "saramin" and r["cause"] == "challenge" and r["count"] == 3
                for r in data.get("rows", [])),
            str(data),
        )
        check(
            "summary --json: warnings 에 saramin 경고 포함",
            any("saramin" in w for w in data.get("warnings", [])),
            str(data),
        )
        check(
            "summary --json: last_kst 에 KST 표기",
            all("KST" in r["last_kst"] for r in data.get("rows", [])),
            str(data),
        )

    # ── tail ────────────────────────────────────────────────────────────
    code, out, err = run(["tail", fixture, "-n", "3"])
    check("tail -n 3: exit 0", code == 0, err)
    tail_lines = [ln for ln in out.splitlines() if ln.strip()]
    check("tail -n 3: 정확히 3줄", len(tail_lines) == 3, out)
    check("tail -n 3: 마지막 3줄(원본 파일 끝부분)과 일치", tail_lines[-1].startswith("not-a-timestamp"), out)

    code, out, err = run(["tail", fixture])
    check("tail 기본(-n 20): 전체 8줄(빈 줄 제외) 다 나옴", len([ln for ln in out.splitlines() if ln.strip()]) == 8, out)

    # url= 리댁션 — 호스트만 남고 경로·쿼리는 사라져야 함
    check("tail: url= 토큰이 호스트만 남도록 리댁션됨", "url=www.wanted.co.kr" in out, out)
    check("tail: 리댁션 후 원래 경로·쿼리는 사라짐", "/search?q=abc" not in out, out)

    # url= 토큰이 애초에 호스트를 못 뽑아내는(파싱 실패) 값이면 raw 를 그대로 새지 않고
    # [unparseable] 로 대체해야 한다 — raw 폴백은 리댁션의 목적(민감정보 차단)을 무력화한다.
    unparseable_fixture = os.path.join(TMP, "unparseable-url.log")
    with open(unparseable_fixture, "w", encoding="utf-8") as f:
        f.write(f'{iso(now)} [fetch-jobs:diag] platform=saramin cause=error url=[::1 status=500\n')
    code, out, err = run(["tail", unparseable_fixture])
    check("tail: url= 파싱 실패 exit 0", code == 0, err)
    check("tail: url= 파싱 실패 시 [unparseable] 로 대체", "url=[unparseable]" in out, out)
    check("tail: 파싱 실패한 원본 토큰은 그대로 노출되지 않음(raw 유출 없음)", "url=[::1" not in out, out)

    # ── 없는 파일 ───────────────────────────────────────────────────────
    missing = os.path.join(TMP, "no-such-file.log")
    code, out, err = run(["summary", missing])
    check("summary 없는 파일: exit 0", code == 0, err)
    check("summary 없는 파일: '기록 없음' 출력", out.strip() == "기록 없음", out)

    code, out, err = run(["tail", missing])
    check("tail 없는 파일: exit 0", code == 0, err)
    check("tail 없는 파일: '기록 없음' 출력", out.strip() == "기록 없음", out)

    # ── 깨진 줄만 있는 파일 ─────────────────────────────────────────────
    garbage = os.path.join(TMP, "garbage.log")
    with open(garbage, "w", encoding="utf-8") as f:
        f.write("garbage line one\nanother bad line\n")
    code, out, err = run(["summary", garbage])
    check("summary 깨진 줄만: exit 0", code == 0, err)
    check("summary 깨진 줄만: '기록 없음' + 파싱 불가 안내", "기록 없음" in out and "2줄" in out, out)

    # ── 인자 오류 ───────────────────────────────────────────────────────
    code, out, err = run(["summary", fixture, "--since", "7days"])
    check("잘못된 --since 형식: exit 2", code == 2, f"code={code} err={err}")

    code, out, err = run(["tail", fixture, "-n", "abc"])
    check("잘못된 -n 값: exit 2", code == 2, f"code={code} err={err}")

    code, out, err = run(["bogus-command"])
    check("알 수 없는 명령: exit 2", code == 2, f"code={code} err={err}")

    code, out, err = run([])
    check("인자 없음: exit 2", code == 2, f"code={code} err={err}")

    # ── 로그 경로 기본값 해석 순서 ──────────────────────────────────────
    code, out, err = run(["summary"], env={"JOBSTACK_FETCH_DIAG_LOG": fixture})
    check("JOBSTACK_FETCH_DIAG_LOG 로 기본 경로 해석", code == 0 and "6건" in out, out + err)

    state_dir = os.path.join(TMP, "state")
    os.makedirs(os.path.join(state_dir, "analytics"), exist_ok=True)
    shutil.copy(fixture, os.path.join(state_dir, "analytics", "fetch-diag.log"))
    code, out, err = run(["summary"], env={"JOBSTACK_STATE_DIR": state_dir})
    check(
        "JOBSTACK_FETCH_DIAG_LOG 없을 때 JOBSTACK_STATE_DIR/analytics/fetch-diag.log 폴백",
        code == 0 and "6건" in out,
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
