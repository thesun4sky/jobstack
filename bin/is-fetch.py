#!/usr/bin/env python3
"""
is-fetch.py — insane-search 흡수 어댑터 (실행계획 §2 "어댑터 계약", Phase 1·2, U-12 ④).

URL 을 curl_cffi TLS 임퍼소네이션으로 fetch 해 stdout 에 JSON 한 건을 낸다.
파싱·마감일·캐싱·guardrails 는 호출측(jobstack)이 그대로 유지 — 이 스크립트는
"입력 URL → 출력 HTML + verdict" 계약만 구현한다(엔진 전체 흡수 ✗, 실행계획 §6).

계약:
  입력:  is-fetch.py <URL> [--selector <substr>]... [--profiles <p1,p2>] [--no-retry]
  출력(stdout, JSON 한 건):
    {"html": "...", "verdict": "strong_ok|too_small|challenge|error",
     "status": <int|null>,
     "block_class": "none|waf_challenge|captcha|access_denied|rate_limited|login_wall|
                     too_small|error",
     "untried_routes": ["playwright"], "detail": "..."}
    block_class 는 verdict 보다 세분화된 차단 원인이다 — verdict 는 429/503/403 을 전부
    status≥400 → error 로 뭉뚱그리지만, block_class 는 WAF 챌린지·캡차·접근거부·rate
    limit·로그인월을 구분해 호출측이 원인별로 다르게 대응할 수 있게 한다. 기존 필드
    (html/verdict/status/untried_routes/detail)는 그대로 유지한다(계약 불변) — block_class 는
    추가 필드일 뿐이다.
  종료코드:
    0 — 정상. verdict 로 성패를 판정한다(stdout JSON 유효).
    2 — 사용법 오류(인자 누락·잘못된 --profiles 값). stderr 안내.
    3 — curl_cffi 미가용(어댑터 no-op 신호). stderr 1줄, stdout 오염 금지.

옵션:
  --selector <substr>  (반복 가능) HTML 에 있어야 할 문자열 — strong_ok 인데 0건이면
                        too_small 로 강등한다.
  --profiles <p1,p2>   임퍼소네이션 프로필 순서·집합을 제한한다(허용값은 IMPERSONATE_PROFILES
                        에 있는 이름뿐, 그 외는 exit 2). IS_FETCH_PROFILES 환경변수로도 지정
                        가능(옵션이 환경변수보다 우선).
  --no-retry            아래 Retry-After 재시도를 끈다. IS_FETCH_NO_RETRY=1 로도 끌 수 있다.

Retry-After 재시도: 429/503 응답의 Retry-After 헤더가 정수 초이고 RETRY_AFTER_MAX_S 이하이며
프로필 예산이 남아 있으면, 그 초만큼 대기한 뒤 같은 프로필로 1회만 재시도한다(HTTP-date
형식은 무시 — 재시도하지 않는다). 재시도 요청도 SSRF 가드·스트림 상한을 그대로 거친다
(리다이렉트 홉 루프 안이 아니라 바깥에서 fetch 전체를 한 번 더 호출하는 방식).

verdict 분류는 bin/fetch-diag.mjs 의 classifyFailure 를 파이썬에 미러링한다.
⚠️ CHALLENGE_MARKERS·TOO_SMALL_LEN 은 fetch-diag.mjs 와 반드시 동기화한다
   (test/test-is-fetch-adapter.mjs 가 두 소스 간 마커 일치를 강제). 마커 문자열 리터럴은
   그대로 두고 매칭 방식만 나눈다 — ASCII 마커는 단어 경계 매칭, 한글 마커는 부분 문자열
   매칭("datadomestic" 이 "datadome" 에 오검출되지 않으면서 "<div class=\"datadome\">" 는
   정확히 걸리게 한다).

venv 구조: bin/.is-venv/bin/python 이 자기 자신을 재실행하는 부트스트랩이다.
시스템 python3 로 호출돼도(예: SKILL.md 의 `python3 .../is-fetch.py`) curl_cffi 가
없으면 venv python 으로 execv 재실행한다. venv 부재 시 exit 3(no-op).
"""
import ipaddress
import json
import os
import re
import socket
import sys
import time
from urllib.parse import urljoin, urlparse

# ── fetch-diag.mjs 와 동기화 필수 (test-is-fetch-adapter.mjs 가 강제) ──────────
# 마커는 소문자로 통일 — html.lower() 와 대조해 WAF 응답의 케이싱 변형을 흡수한다.
CHALLENGE_MARKERS = [
    'just a moment', 'cf-browser-verification', '/cdn-cgi/challenge-platform',
    'datadome', 'g-recaptcha', 'recaptcha', '자동입력 방지',
    'access denied', '접근이 차단', 'request unsuccessful',
]
TOO_SMALL_LEN = 3000  # fetch-diag.mjs classifyFailure 의 html.length < 3000 미러

IMPERSONATE_PROFILES = ('safari', 'chrome')  # safari → chrome 순환(최대 2회)
TIMEOUT_S = 8  # 단일 요청 타임아웃(홉당)
# 프로필당 전체 리다이렉트 체인 예산. per-request timeout은 홉마다 재부여되므로(curl_cffi는
# CURLOPT_TIMEOUT=단일 transfer), 이 예산으로 체인 총 시간을 bound한다 — 2 프로필×PROFILE_BUDGET_S
# 가 어댑터 SIGKILL(25s)·직접호출 경로 상한을 넘지 않게 한다(리뷰 반영: 홉 누적으로 20s 상한이
# 깨지던 문제).
PROFILE_BUDGET_S = 11
MAX_REDIRECTS = 10  # curl_cffi 기본값(30) 의존 금지 — 오픈 리다이렉트 경유 SSRF 표면 축소
MAX_RESPONSE_BYTES = 10_000_000  # 응답 크기 상한 — 초과 시 error (OOM 방지)
RETRY_AFTER_MAX_S = 5  # 이 초를 넘는 Retry-After 는 재시도하지 않는다(무한정 대기 방지)
# verdict 우선순위 — 프로필을 순환하며 가장 좋은 결과를 채택한다.
_VERDICT_RANK = {'strong_ok': 3, 'too_small': 2, 'challenge': 1, 'error': 0}


# ── 경계 매칭 (검토 보고서 U-12 ④) ────────────────────────────────────────────
# CHALLENGE_MARKERS 리스트 리터럴 자체는 위에서 그대로 유지한다(fetch-diag.mjs 동기화 검사
# 대상 — test-is-fetch-adapter.mjs 가 소스 문자열 포함 여부로 검사하므로 한 글자도 못 건드림).
# 매칭 방식만 나눈다: ASCII 마커는 단어 경계로 감싸 컴파일하고(소문자 HTML 대상), 한글 등
# 비ASCII 마커는 부분 문자열 매칭으로 남겨둔다 — "datadomestic" 이 "datadome" 에 오검출되지
# 않으면서 `<div class="datadome">` 는 정확히 걸리게 한다.
def _compile_marker(marker):
    if not marker.isascii():
        return None  # 한글 등 비ASCII 마커 → 부분 문자열 매칭으로 폴백
    return re.compile(r'(?<![a-z0-9])' + re.escape(marker) + r'(?![a-z0-9])')


_MARKER_RE = {m: _compile_marker(m) for m in CHALLENGE_MARKERS}


def _marker_hit(marker, lower_html):
    pattern = _MARKER_RE.get(marker)
    if pattern is not None:
        return pattern.search(lower_html) is not None
    return marker in lower_html  # 한글 마커: 부분 문자열 매칭


def _find_marker(lower_html, markers):
    """markers 를 순서대로 보아 첫 매치 마커 문자열을 반환한다. 없으면 None."""
    for m in markers:
        if _marker_hit(m, lower_html):
            return m
    return None


# block_class 세분류용 마커 그룹 — 전부 CHALLENGE_MARKERS 의 부분집합(동일 문자열 리터럴을
# 재사용할 뿐 CHALLENGE_MARKERS 자체는 건드리지 않는다).
_WAF_MARKERS = (
    'just a moment', 'cf-browser-verification', '/cdn-cgi/challenge-platform',
    'datadome', 'request unsuccessful',
)
_CAPTCHA_MARKERS = ('recaptcha', 'g-recaptcha', '자동입력 방지')
_ACCESS_DENIED_MARKERS = ('access denied', '접근이 차단')


def classify(html, status):
    """fetch-diag.mjs classifyFailure 미러 + HTTP 상태 반영. html 없거나 status>=400 →
    error(에러 페이지를 strong_ok로 채택해 사람인 폴백을 잃지 않게 함, 리뷰 반영), 챌린지 마커
    → challenge, 3000자 미만 → too_small, 그 외 정상 → strong_ok."""
    if not html:
        return 'error'
    if status is not None and status >= 400:
        return 'error'
    lower = html.lower()
    if _find_marker(lower, CHALLENGE_MARKERS):
        return 'challenge'
    if len(html) < TOO_SMALL_LEN:
        return 'too_small'
    return 'strong_ok'


def _parse_retry_after_seconds(value):
    """Retry-After 헤더 값에서 정수 초를 파싱한다. HTTP-date 형식·빈 값·음수·소수는 None
    (재시도 대상이 아님 — 요구사항이 '정수 초' 형식만 재시도하도록 한정한다)."""
    if value is None:
        return None
    value = value.strip()
    if not value.isdigit():
        return None
    return int(value)


def _classify_block_class(html, status, retry_after_header, selector_hits, has_selectors):
    """block_class 판정: none|waf_challenge|captcha|access_denied|rate_limited|login_wall|
    too_small|error. verdict 와 달리 429/503/403 도 원인을 구분해서 본다(verdict 는
    status>=400 을 전부 error 로 뭉뚱그린다 — 재시도 힌트를 위해 block_class 만 세분화).
    반환: (block_class, marker) — marker 는 텍스트 마커로 판정됐을 때만 채워지고, 상태코드나
    selector 조건만으로 판정되면 빈 문자열이다."""
    lower = (html or '').lower()

    marker = _find_marker(lower, _WAF_MARKERS)
    if marker:
        return 'waf_challenge', marker

    marker = _find_marker(lower, _CAPTCHA_MARKERS)
    if marker:
        return 'captcha', marker

    marker = _find_marker(lower, _ACCESS_DENIED_MARKERS)
    if marker or status == 403:
        return 'access_denied', marker or ''

    if status == 429:
        return 'rate_limited', ''
    if status == 503 and retry_after_header not in (None, ''):
        return 'rate_limited', ''

    if (status == 200 and has_selectors and selector_hits == 0
            and '<form' in lower and 'type="password"' in lower):
        return 'login_wall', ''  # 보수적 판정 — 폼+비밀번호 필드 + 선택자 0건일 때만

    if not html:
        return 'error', ''
    if status is not None and status >= 400:
        return 'error', ''
    if len(html) < TOO_SMALL_LEN:
        return 'too_small', ''
    return 'none', ''


def _diag(msg):
    sys.stderr.write(msg + '\n')


# ── SSRF 가드 (리뷰 반영) ──────────────────────────────────────────────────
# is-fetch는 SKILL.md 지시로 WebSearch 결과·사용자 유래 URL을 받는다. 스킴(http/https)
# 제한 + 해석 IP가 글로벌 공인이 아니면(사설/CGNAT/루프백/링크로컬/메타데이터 등) 거부해,
# 내부망 응답이 stdout으로 유출되는 것을 막는다. 리다이렉트는 수동 추종하며 매 홉을 재검증한다.
# ⚠️ 잔여 위험(문서화): getaddrinfo 검증 IP와 curl 실제 연결 IP가 분리돼 DNS rebinding/TOCTOU가
#    이론상 가능하다(공인 도메인으로 통과시킨 뒤 재해석으로 내부 IP 연결). 완전 차단은 검증 IP를
#    연결에 고정(CURLOPT_RESOLVE)해야 하나 curl_cffi 0.15에 안정 API가 없어 미적용. 이 도구는
#    opt-in·"WebFetch 차단 시 폴백" 게이트 뒤에서만 쓰이고 직접 IP·메타데이터·스킴 등 주요 벡터는
#    차단되므로, DNS-rebinding은 수용 가능한 잔여 위험으로 둔다(악용에 공격자 도메인+빠른 DNS 플립
#    +에이전트가 그 URL을 폴백 fetch하는 3중 조건 필요).
def _host_is_safe(host):
    """host의 모든 해석 IP가 '글로벌 공인'이면 True. 하나라도 비공인이면 False.
    블랙리스트(사설/루프백/…) 대신 is_global 화이트리스트를 쓴다 — 블랙리스트는 CGNAT
    (100.64.0.0/10, is_private=False)처럼 빠지는 특수대역이 있어 SSRF가 우회된다(리뷰 반영)."""
    if not host:
        return False
    try:
        infos = socket.getaddrinfo(host, None)
    except OSError:
        return False
    if not infos:
        return False
    for info in infos:
        ip = info[4][0]
        try:
            addr = ipaddress.ip_address(ip.split('%')[0])  # zone id 제거(IPv6 link-local)
        except ValueError:
            return False
        # IPv4 매핑된 IPv6(::ffff:a.b.c.d)는 내장 IPv4로 환원해 판정.
        if getattr(addr, 'ipv4_mapped', None) is not None:
            addr = addr.ipv4_mapped
        if not addr.is_global:
            return False
    return True


def _url_is_safe(url):
    parsed = urlparse(url)
    if parsed.scheme not in ('http', 'https'):
        return False, f'scheme={parsed.scheme or "none"}'
    if not _host_is_safe(parsed.hostname):
        return False, f'host={parsed.hostname}'
    return True, ''


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


def _emit(html, verdict, status, block_class, detail):
    json.dump(
        {
            'html': html,
            'verdict': verdict,
            'status': status,
            'block_class': block_class,
            'untried_routes': ['playwright'],
            'detail': detail,
        },
        sys.stdout,
        ensure_ascii=False,
    )
    sys.stdout.write('\n')


def _read_capped(resp):
    """스트리밍으로 본문을 읽되 MAX_RESPONSE_BYTES 초과 시 즉시 중단(압축폭탄·거대응답 OOM 방지).
    상한 초과면 (None, True). 정상이면 (text, False)."""
    chunks = []
    total = 0
    try:
        for chunk in resp.iter_content():
            if not chunk:
                continue
            total += len(chunk)
            if total > MAX_RESPONSE_BYTES:
                return None, True
            chunks.append(chunk)
    except Exception:  # noqa: BLE001 — 스트림 오류는 error로 흡수
        return None, True
    raw = b''.join(chunks)
    enc = getattr(resp, 'encoding', None) or 'utf-8'
    try:
        return raw.decode(enc, errors='replace'), False
    except (LookupError, TypeError):
        return raw.decode('utf-8', errors='replace'), False


def _fetch_with_guarded_redirects(cffi_requests, url, profile, deadline=None):
    """리다이렉트를 수동 추종하며 매 홉의 URL을 SSRF 재검증하고, 본문은 스트리밍 상한으로 읽는다.
    반환: (html, status, verdict, retry_after_header) — retry_after_header 는 최종(비-리다이렉트)
    응답의 Retry-After 헤더 원문(없으면 None)이며, block_class 의 rate_limited 판정과
    _fetch_profile 의 재시도 여부 판단이 이 값을 쓴다.
    ⚠️ curl_cffi stream=True 는 백그라운드 스레드가 본문을 무제한 큐에 계속 내려받으므로,
    3xx·초과·오류로 조기 반환하는 모든 경로에서 resp.close()로 다운로드를 중단해야 한다 —
    안 그러면 폐기된 리다이렉트 응답 본문이 계속 버퍼링돼 크기 상한이 무력화되고 핸들/스레드가
    누수된다(리뷰 반영). deadline: 전체 리다이렉트 체인의 monotonic 마감시각(홉당 재부여되는
    per-request timeout이 누적되지 않게 상한)."""
    current = url
    for _hop in range(MAX_REDIRECTS + 1):
        # 남은 체인 예산으로 이번 홉 타임아웃을 조인다 — 예산 소진 시 종료(홉 누적 방지).
        req_timeout = TIMEOUT_S
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _diag(f'is-fetch: {profile} overall deadline exceeded')
                return '', None, 'error', None
            req_timeout = max(1, min(TIMEOUT_S, remaining))
        resp = None
        try:
            resp = cffi_requests.get(
                current,
                impersonate=profile,
                timeout=req_timeout,
                allow_redirects=False,  # 수동 추종 — 각 홉을 재검증(공개→내부망 리다이렉트 차단)
                stream=True,
                headers={'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7'},
            )
            status = resp.status_code
            location = resp.headers.get('location') if 300 <= status < 400 else None
            if location:
                resp.close()  # 3xx 본문 다운로드 즉시 중단(스트림 abort)
                resp = None
                nxt = urljoin(current, location)
                safe, why = _url_is_safe(nxt)
                if not safe:
                    _diag(f'is-fetch: {profile} blocked redirect ({why})')
                    return '', status, 'error', None
                current = nxt
                continue
            retry_after_header = resp.headers.get('retry-after')
            html, too_big = _read_capped(resp)
            if too_big:
                _diag(f'is-fetch: {profile} response too large (> {MAX_RESPONSE_BYTES}B)')
                return '', status, 'error', retry_after_header
            return html or '', status, classify(html, status), retry_after_header
        except Exception as err:  # noqa: BLE001 — 네트워크/프로토콜 오류 전반은 error 로
            _diag(f'is-fetch: {profile} failed — {err.__class__.__name__}')
            return '', None, 'error', None
        finally:
            # 조기 반환·예외 어느 경로든 남은 스트림을 닫아 백그라운드 다운로드/핸들 누수를 막는다.
            if resp is not None:
                try:
                    resp.close()
                except Exception:  # noqa: BLE001
                    pass
    _diag(f'is-fetch: {profile} too many redirects')
    return '', None, 'error', None


def _fetch_profile(cffi_requests, url, profile, deadline, no_retry):
    """프로필 하나로 fetch 하고, 429/503 응답의 Retry-After 가 정수 초이며
    RETRY_AFTER_MAX_S 이하이고 프로필 예산이 남아 있으면 그 초만큼 대기한 뒤 같은 프로필로
    1회만 재시도한다(HTTP-date 형식은 무시 — 재시도하지 않음). 재시도 요청도
    _fetch_with_guarded_redirects 를 그대로 다시 호출해 SSRF 가드·스트림 닫기 규칙을 그대로
    따른다 — 리다이렉트 홉 루프 안에서 처리하지 않고 바깥에서 fetch 전체를 한 번 더 호출하는
    방식이 단순하다.
    반환: (html, status, verdict, retry_after_header, retried_after) — retried_after 는
    실제로 대기·재시도했으면 대기한 초(N), 아니면 None(detail 표기용)."""
    html, status, verdict, retry_after_header = _fetch_with_guarded_redirects(
        cffi_requests, url, profile, deadline
    )
    if no_retry or status not in (429, 503):
        return html, status, verdict, retry_after_header, None

    wait_s = _parse_retry_after_seconds(retry_after_header)
    if wait_s is None or wait_s > RETRY_AFTER_MAX_S:
        return html, status, verdict, retry_after_header, None
    if deadline is not None and (deadline - time.monotonic()) <= wait_s:
        _diag(f'is-fetch: {profile} retry skipped — profile budget insufficient')
        return html, status, verdict, retry_after_header, None

    time.sleep(wait_s)
    html2, status2, verdict2, retry_after_header2 = _fetch_with_guarded_redirects(
        cffi_requests, url, profile, deadline
    )
    return html2, status2, verdict2, retry_after_header2, wait_s


class _ArgError(Exception):
    """_parse_args 인자 오류 — main() 이 stderr 안내 + exit 2 로 변환한다."""


def _parse_profiles(raw, label):
    """콤마 구분 프로필 이름 문자열을 검증해 리스트로 돌려준다(입력 순서 유지). 허용값은
    IMPERSONATE_PROFILES 에 있는 이름뿐이다 — 그 외는 _ArgError."""
    names = [p.strip() for p in raw.split(',') if p.strip()]
    if not names:
        raise _ArgError(f'{label} 값이 비어 있음')
    for name in names:
        if name not in IMPERSONATE_PROFILES:
            raise _ArgError(
                f'{label} 알 수 없는 프로필 "{name}" (허용: {", ".join(IMPERSONATE_PROFILES)})'
            )
    return names


def _parse_args(argv):
    """argv 를 (url, selectors, profiles, no_retry) 로 파싱하는 순수 함수 — stdout/stderr
    출력이나 sys.exit 은 하지 않고, 오류는 _ArgError 로 던져 호출측(main)이 exit 코드로
    변환하게 한다. --profiles/--no-retry 를 안 쓰면 IS_FETCH_PROFILES/IS_FETCH_NO_RETRY
    환경변수를 본다(명시적 옵션이 환경변수보다 우선한다)."""
    url = None
    selectors = []
    no_retry = False
    profiles = None
    i = 0
    while i < len(argv):
        a = argv[i]
        if a == '--selector':
            i += 1
            if i >= len(argv):
                raise _ArgError('is-fetch: --selector 값 누락')
            selectors.append(argv[i])
        elif a == '--profiles':
            i += 1
            if i >= len(argv):
                raise _ArgError('is-fetch: --profiles 값 누락')
            profiles = _parse_profiles(argv[i], 'is-fetch: --profiles')
        elif a == '--no-retry':
            no_retry = True
        elif a.startswith('--'):
            raise _ArgError(f'is-fetch: 알 수 없는 옵션 {a}')
        elif url is None:
            url = a
        else:
            raise _ArgError(f'is-fetch: 알 수 없는 인자 {a}')
        i += 1

    if not url:
        raise _ArgError(
            'Usage: is-fetch.py <URL> [--selector <substr>]... [--profiles p1,p2] [--no-retry]'
        )

    if profiles is None:
        env_profiles = os.environ.get('IS_FETCH_PROFILES')
        profiles = (_parse_profiles(env_profiles, 'is-fetch: IS_FETCH_PROFILES')
                    if env_profiles else list(IMPERSONATE_PROFILES))

    if os.environ.get('IS_FETCH_NO_RETRY') == '1':
        no_retry = True

    return url, selectors, profiles, no_retry


def main(argv):
    try:
        url, selectors, profiles, no_retry = _parse_args(argv)
    except _ArgError as err:
        _diag(str(err))
        return 2

    # SSRF: 최초 URL 스킴·호스트 검증. 위험하면 네트워크를 아예 건드리지 않고 error.
    safe, why = _url_is_safe(url)
    if not safe:
        _diag(f'is-fetch: blocked unsafe url ({why})')
        _emit('', 'error', None, 'error', f'blocked_unsafe_url {why}')
        return 0

    cffi_requests = _load_curl_cffi()  # 미가용이면 exit 3 (아래로 반환하지 않음)

    best_html, best_status, best_verdict = '', None, 'error'
    best_retry_after_header = None
    best_retry_used = None
    for profile in profiles:
        deadline = time.monotonic() + PROFILE_BUDGET_S
        html, status, verdict, retry_after_header, retry_used = _fetch_profile(
            cffi_requests, url, profile, deadline, no_retry
        )
        if _VERDICT_RANK[verdict] > _VERDICT_RANK[best_verdict]:
            best_html, best_status, best_verdict = html, status, verdict
            best_retry_after_header = retry_after_header
            best_retry_used = retry_used
        if best_verdict == 'strong_ok':
            break

    # selector 보강 — 주어진 substr 들이 HTML 에 몇 개 잡히는지로 strong_ok 를 확인한다.
    # 큰 페이지인데 대상 콘텐츠가 없으면(0건) too_small 로 강등(정보성; detail 에 기록).
    selector_hits = None
    if selectors:
        selector_hits = sum(1 for s in selectors if s in best_html)
        if best_verdict == 'strong_ok' and selector_hits == 0:
            best_verdict = 'too_small'

    block_class, marker = _classify_block_class(
        best_html, best_status, best_retry_after_header, selector_hits, bool(selectors)
    )

    detail = f'len={len(best_html)} status={best_status if best_status is not None else "n/a"}'
    if selector_hits is not None:
        detail += f' selector_hits={selector_hits}'
    if best_retry_used is not None:
        detail += f' retry_after={best_retry_used}'
    detail += f' block_class={block_class} marker="{marker}"'

    _emit(best_html, best_verdict, best_status, block_class, detail)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
