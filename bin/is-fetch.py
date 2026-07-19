#!/usr/bin/env python3
"""
is-fetch.py — insane-search 흡수 어댑터 (실행계획 §2 "어댑터 계약", Phase 1·2).

URL 을 curl_cffi TLS 임퍼소네이션으로 fetch 해 stdout 에 JSON 한 건을 낸다.
파싱·마감일·캐싱·guardrails 는 호출측(jobstack)이 그대로 유지 — 이 스크립트는
"입력 URL → 출력 HTML + verdict" 계약만 구현한다(엔진 전체 흡수 ✗, 실행계획 §6).

계약:
  입력:  is-fetch.py <URL> [--selector <substr>]...
  출력(stdout, JSON 한 건):
    {"html": "...", "verdict": "strong_ok|too_small|challenge|error",
     "status": <int|null>, "untried_routes": ["playwright"], "detail": "..."}
  종료코드:
    0 — 정상. verdict 로 성패를 판정한다(stdout JSON 유효).
    2 — 사용법 오류(인자 누락). stderr 안내.
    3 — curl_cffi 미가용(어댑터 no-op 신호). stderr 1줄, stdout 오염 금지.

verdict 분류는 bin/fetch-diag.mjs 의 classifyFailure 를 파이썬에 미러링한다.
⚠️ CHALLENGE_MARKERS·TOO_SMALL_LEN 은 fetch-diag.mjs 와 반드시 동기화한다
   (test/test-is-fetch-adapter.mjs 가 두 소스 간 마커 일치를 강제).

venv 구조: bin/.is-venv/bin/python 이 자기 자신을 재실행하는 부트스트랩이다.
시스템 python3 로 호출돼도(예: SKILL.md 의 `python3 .../is-fetch.py`) curl_cffi 가
없으면 venv python 으로 execv 재실행한다. venv 부재 시 exit 3(no-op).
"""
import json
import os
import sys

# ── fetch-diag.mjs 와 동기화 필수 (test-is-fetch-adapter.mjs 가 강제) ──────────
# 마커는 소문자로 통일 — html.lower() 와 대조해 WAF 응답의 케이싱 변형을 흡수한다.
CHALLENGE_MARKERS = [
    'just a moment', 'cf-browser-verification', '/cdn-cgi/challenge-platform',
    'datadome', 'g-recaptcha', 'recaptcha', '자동입력 방지',
    'access denied', '접근이 차단', 'request unsuccessful',
]
TOO_SMALL_LEN = 3000  # fetch-diag.mjs classifyFailure 의 html.length < 3000 미러

IMPERSONATE_PROFILES = ('safari', 'chrome')  # safari → chrome 순환(최대 2회)
TIMEOUT_S = 15
# verdict 우선순위 — 프로필을 순환하며 가장 좋은 결과를 채택한다.
_VERDICT_RANK = {'strong_ok': 3, 'too_small': 2, 'challenge': 1, 'error': 0}


def classify(html, status):
    """fetch-diag.mjs classifyFailure 미러 — html 없으면 error, 챌린지 마커 →
    challenge, 3000자 미만 → too_small, 그 외 정상 → strong_ok. status 는 미사용
    (fetch-diag 와 동일하게 verdict 는 본문 기준)."""
    if not html:
        return 'error'
    lower = html.lower()
    if any(m in lower for m in CHALLENGE_MARKERS):
        return 'challenge'
    if len(html) < TOO_SMALL_LEN:
        return 'too_small'
    return 'strong_ok'


def _diag(msg):
    sys.stderr.write(msg + '\n')


# 재실행 sentinel — 이미 venv python 으로 재실행한 뒤에도 import 가 실패하면
# 더 재실행하지 않는다(무한 루프 방지). venv 의 bin/python 은 base 인터프리터로의
# 심링크라 realpath 비교로는 서로 다른 venv 를 구분할 수 없어(둘 다 base 로 수렴)
# 이 환경변수 sentinel 을 재실행 여부 판정에 쓴다.
_REEXEC_ENV = 'IS_FETCH_REEXEC'


def _load_curl_cffi():
    """curl_cffi 를 로드하거나, 실패 시 venv python 으로 자기 자신을 재실행한다.
    - 현재 인터프리터에 curl_cffi 가 있으면 그대로 반환.
    - 없으면 bin/.is-venv/bin/python 으로 execve(sentinel 세팅 → 자기 자신 실행 구조).
    - venv 부재이거나 재실행 후에도 실패면 exit 3(어댑터 no-op)."""
    try:
        from curl_cffi import requests as cffi_requests  # noqa: PLC0415
        return cffi_requests
    except Exception:  # noqa: BLE001 — import 실패 전반을 no-op 신호로 흡수
        pass
    if os.environ.get(_REEXEC_ENV) == '1':
        _diag('is-fetch: curl_cffi unavailable in venv — no-op')
        sys.exit(3)
    venv_py = os.path.join(os.path.dirname(os.path.abspath(__file__)), '.is-venv', 'bin', 'python')
    if os.path.exists(venv_py):
        env = dict(os.environ, **{_REEXEC_ENV: '1'})
        try:
            os.execve(venv_py, [venv_py, os.path.abspath(__file__), *sys.argv[1:]], env)  # 반환 안 함
        except OSError as err:
            _diag(f'is-fetch: venv re-exec failed ({err.__class__.__name__}) — no-op')
            sys.exit(3)
    _diag('is-fetch: curl_cffi unavailable — no-op (install: ./install.sh --with-insane-search)')
    sys.exit(3)


def _emit(html, verdict, status, detail):
    json.dump(
        {
            'html': html,
            'verdict': verdict,
            'status': status,
            'untried_routes': ['playwright'],
            'detail': detail,
        },
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write('\n')


def main(argv):
    url = None
    selectors = []
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--selector':
            i += 1
            if i >= len(argv):
                _diag('is-fetch: --selector 값 누락')
                return 2
            selectors.append(argv[i])
        elif a.startswith('--') and url is not None:
            _diag(f'is-fetch: 알 수 없는 옵션 {a}')
            return 2
        elif url is None:
            url = a
        i += 1
    if not url:
        _diag('Usage: is-fetch.py <URL> [--selector <substr>]...')
        return 2

    cffi_requests = _load_curl_cffi()  # 미가용이면 exit 3 (아래로 반환하지 않음)

    best_html, best_status, best_verdict = '', None, 'error'
    for profile in IMPERSONATE_PROFILES:
        try:
            resp = cffi_requests.get(
                url,
                impersonate=profile,
                timeout=TIMEOUT_S,
                headers={'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7'},
            )
            html = resp.text or ''
            status = resp.status_code
            verdict = classify(html, status)
        except Exception as err:  # noqa: BLE001 — 네트워크/프로토콜 오류 전반은 error 로
            html, status, verdict = '', None, 'error'
            _diag(f'is-fetch: {profile} failed — {err.__class__.__name__}')
        if _VERDICT_RANK[verdict] > _VERDICT_RANK[best_verdict]:
            best_html, best_status, best_verdict = html, status, verdict
        if best_verdict == 'strong_ok':
            break

    # selector 보강 — 주어진 substr 들이 HTML 에 몇 개 잡히는지로 strong_ok 를 확인한다.
    # 큰 페이지인데 대상 콘텐츠가 없으면(0건) too_small 로 강등(정보성; detail 에 기록).
    selector_hits = None
    if selectors:
        selector_hits = sum(1 for s in selectors if s in best_html)
        if best_verdict == 'strong_ok' and selector_hits == 0:
            best_verdict = 'too_small'

    detail = f'len={len(best_html)} status={best_status if best_status is not None else "n/a"}'
    if selector_hits is not None:
        detail += f' selector_hits={selector_hits}'
    _emit(best_html, best_verdict, best_status, detail)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
