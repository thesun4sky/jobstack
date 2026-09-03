#!/usr/bin/env bash
# test-is-fetch-classify.sh — is-fetch.py 분류 로직 단위 테스트 (검토 보고서 U-12 ④).
#
# 네트워크·curl_cffi 없이 통과해야 한다. 파일명이 하이픈을 포함해 일반 import 구문으로
# 부를 수 없으므로 importlib.util.spec_from_file_location 으로 모듈로 로드한다. curl_cffi 는
# _load_curl_cffi() 안에서만(호출 시점) import 되므로 모듈 로드 자체는 안전하다 — 이 테스트는
# classify()·_classify_block_class()·_parse_args()·_parse_retry_after_seconds() 등 순수
# 함수만 호출하고 네트워크 함수(_fetch_with_guarded_redirects 등)는 부르지 않는다.
set -u
HERE="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../bin/is-fetch.py"

python3 - "$SCRIPT" <<'PY'
import importlib.util
import os
import sys

script = sys.argv[1]
spec = importlib.util.spec_from_file_location("is_fetch_under_test", script)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

results = []


def check(name, cond, detail=""):
    results.append((name, bool(cond), detail))


def raises_arg_error(fn):
    try:
        fn()
    except m._ArgError:
        return True
    except Exception:
        return False
    return False


BIG = "x" * (m.TOO_SMALL_LEN)  # TOO_SMALL_LEN 이상 크기의 채움 텍스트(strong_ok 후보)

# ── 1. 경계 매칭 — classify() 의 challenge 판정 ─────────────────────────────
check(
    "datadomestic 은 datadome 마커에 오검출되지 않음(단어 내부 포함은 음성)",
    m.classify(f"<html>{BIG} datadomestic</html>", 200) == "strong_ok",
)
check(
    '<div class="datadome"> 는 datadome 마커에 정확히 걸림',
    m.classify(f'<html>{BIG} <div class="datadome"></div></html>', 200) == "challenge",
)
check(
    "xrecaptchay(단어 내부 포함) 는 recaptcha 마커에 오검출되지 않음",
    m.classify(f"<html>{BIG} xrecaptchay</html>", 200) == "strong_ok",
)
check(
    "recaptcha 단독 토큰은 정확히 걸림(경계 매칭 양성)",
    m.classify(f"<html>{BIG} recaptcha</html>", 200) == "challenge",
)
check(
    "g-recaptcha 는 정확히 걸림(하이픈은 마커 경계 밖 문자)",
    m.classify(f"<html>{BIG} g-recaptcha</html>", 200) == "challenge",
)
check(
    "cf-browser-verification 문장부호로 둘러싸이면 걸림",
    m.classify(f"<html>{BIG} (cf-browser-verification).</html>", 200) == "challenge",
)

# ── 2. 한글 마커 — 부분 문자열 매칭(경계 없음) ────────────────────────────
check(
    "자동입력 방지 — 앞뒤에 공백 없이 붙어도 부분 문자열 매칭으로 걸림",
    m.classify(f"<html>{BIG}주의:자동입력 방지문자를입력하세요</html>", 200) == "challenge",
)
check(
    "접근이 차단 — 부분 문자열 매칭으로 걸림",
    m.classify(f"<html>{BIG}귀하의접근이 차단되었습니다</html>", 200) == "challenge",
)

# ── 3. classify() 기본 동작(회귀 — boundary 도입 전과 동일해야 함) ─────────
check("빈 html → error", m.classify("", 200) == "error")
check("status>=400 → error(마커 없어도)", m.classify(f"<html>{BIG}</html>", 500) == "error")
check("3000자 미만 정상 텍스트 → too_small", m.classify("<html>tiny</html>", 200) == "too_small")
check("큰 정상 텍스트 → strong_ok", m.classify(f"<html>{BIG}</html>", 200) == "strong_ok")

# ── 4. block_class ──────────────────────────────────────────────────────
bc = m._classify_block_class

check(
    "waf_challenge: just a moment",
    bc(f"<html>Just a moment...{BIG}</html>", 200, None, None, False) == ("waf_challenge", "just a moment"),
)
check(
    "captcha: recaptcha",
    bc(f"<html>{BIG} recaptcha</html>", 200, None, None, False) == ("captcha", "recaptcha"),
)
check(
    "access_denied: 텍스트 마커",
    bc(f"<html>Access Denied {BIG}</html>", 200, None, None, False) == ("access_denied", "access denied"),
)
check(
    "access_denied: status 403(마커 없이)",
    bc(f"<html>{BIG}</html>", 403, None, None, False) == ("access_denied", ""),
)
check(
    "rate_limited: status 429",
    bc("", 429, None, None, False) == ("rate_limited", ""),
)
check(
    "rate_limited: status 503 + Retry-After 헤더",
    bc(f"<html>{BIG}</html>", 503, "30", None, False) == ("rate_limited", ""),
)
check(
    "503인데 Retry-After 없으면 rate_limited 아님(status>=400 → error 로 폴백)",
    bc(f"<html>{BIG}</html>", 503, None, None, False) == ("error", ""),
)
check(
    "login_wall: 폼+비밀번호 필드 + 선택자 0건(보수적 판정)",
    bc('<html><form>...<input type="password"></form></html>', 200, None, 0, True) == ("login_wall", ""),
)
check(
    "login_wall 아님: 선택자가 아예 주어지지 않으면 폼+비밀번호만으론 판정 안 함",
    bc(f'<html><form><input type="password"></form>{BIG}</html>', 200, None, None, False) == ("none", ""),
)
check(
    "login_wall 아님: 선택자 hits>0 이면 판정 안 함",
    bc(f'<html><form><input type="password"></form>{BIG}</html>', 200, None, 1, True) == ("none", ""),
)
check(
    "too_small: 작은 정상 html",
    bc("<html>tiny</html>", 200, None, None, False) == ("too_small", ""),
)
check(
    "none: 큰 정상 html",
    bc(f"<html>{BIG}</html>", 200, None, None, False) == ("none", ""),
)
check(
    "error: 빈 html",
    bc("", 200, None, None, False) == ("error", ""),
)
check(
    "우선순위: status 403 이어도 WAF 마커가 있으면 waf_challenge 가 access_denied 보다 우선",
    bc(f"<html>Just a moment {BIG}</html>", 403, None, None, False) == ("waf_challenge", "just a moment"),
)

# ── 5. Retry-After 파싱 헬퍼 ────────────────────────────────────────────
ra = m._parse_retry_after_seconds
check("Retry-After '5' → 5", ra("5") == 5)
check("Retry-After ' 3 '(공백 포함) → 3", ra(" 3 ") == 3)
check("Retry-After HTTP-date 형식 → None(무시)", ra("Wed, 21 Oct 2026 07:28:00 GMT") is None)
check("Retry-After None → None", ra(None) is None)
check("Retry-After 빈 문자열 → None", ra("") is None)
check("Retry-After 음수 → None", ra("-1") is None)
check("Retry-After 소수 → None(정수 초만 인정)", ra("3.5") is None)
check(
    "Retry-After 유니코드 숫자(위첨자 '5²') → None(isdigit() 오탐 방지, int() 크래시 없음)",
    ra("5²") is None,
)

# ── 6. _parse_args — 순수 함수 옵션 파싱 ────────────────────────────────
DEFAULT_PROFILES = list(m.IMPERSONATE_PROFILES)

check(
    "URL 만 있으면 기본 프로필·빈 selectors·no_retry=False",
    m._parse_args(["https://example.com"]) == ("https://example.com", [], DEFAULT_PROFILES, False),
)
check(
    "--selector 반복 시 순서대로 수집",
    m._parse_args(["https://example.com", "--selector", "a", "--selector", "b"])
    == ("https://example.com", ["a", "b"], DEFAULT_PROFILES, False),
)
check(
    "--profiles chrome → ['chrome']",
    m._parse_args(["https://example.com", "--profiles", "chrome"])
    == ("https://example.com", [], ["chrome"], False),
)
check(
    "--profiles safari,chrome → 입력 순서 유지",
    m._parse_args(["https://example.com", "--profiles", "safari,chrome"])[2] == ["safari", "chrome"],
)
check(
    "--no-retry → no_retry=True",
    m._parse_args(["https://example.com", "--no-retry"])[3] is True,
)
check(
    "잘못된 프로필 이름(--profiles) → _ArgError(exit 2 로 변환될 신호)",
    raises_arg_error(lambda: m._parse_args(["https://example.com", "--profiles", "chrome,bogus"])),
)
check(
    "URL 누락 → _ArgError",
    raises_arg_error(lambda: m._parse_args([])),
)
check(
    "알 수 없는 옵션 → _ArgError",
    raises_arg_error(lambda: m._parse_args(["https://example.com", "--wat"])),
)
check(
    "--selector 값 누락 → _ArgError",
    raises_arg_error(lambda: m._parse_args(["https://example.com", "--selector"])),
)

# ── 7. IS_FETCH_PROFILES / IS_FETCH_NO_RETRY 환경변수 ──────────────────
_saved_profiles = os.environ.pop("IS_FETCH_PROFILES", None)
_saved_no_retry = os.environ.pop("IS_FETCH_NO_RETRY", None)
try:
    os.environ["IS_FETCH_PROFILES"] = "chrome"
    check(
        "IS_FETCH_PROFILES=chrome (옵션 없음) → profiles=['chrome']",
        m._parse_args(["https://example.com"])[2] == ["chrome"],
    )
    check(
        "--profiles 옵션이 IS_FETCH_PROFILES 보다 우선",
        m._parse_args(["https://example.com", "--profiles", "safari"])[2] == ["safari"],
    )
    os.environ["IS_FETCH_PROFILES"] = "bogus"
    check(
        "IS_FETCH_PROFILES 값이 잘못되면 _ArgError",
        raises_arg_error(lambda: m._parse_args(["https://example.com"])),
    )
    os.environ.pop("IS_FETCH_PROFILES", None)

    os.environ["IS_FETCH_NO_RETRY"] = "1"
    check(
        "IS_FETCH_NO_RETRY=1 (옵션 없음) → no_retry=True",
        m._parse_args(["https://example.com"])[3] is True,
    )
finally:
    os.environ.pop("IS_FETCH_PROFILES", None)
    os.environ.pop("IS_FETCH_NO_RETRY", None)
    if _saved_profiles is not None:
        os.environ["IS_FETCH_PROFILES"] = _saved_profiles
    if _saved_no_retry is not None:
        os.environ["IS_FETCH_NO_RETRY"] = _saved_no_retry

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
