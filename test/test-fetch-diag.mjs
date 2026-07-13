#!/usr/bin/env node
/**
 * fetch-diag.mjs 회귀 테스트 — classifyFailure 원인 분류 + JOBSTACK_FETCH_DIAG_LOG 파일 로깅.
 * 실행: node test/test-fetch-diag.mjs
 */
import { classifyFailure, logFailure, CHALLENGE_MARKERS } from '../bin/fetch-diag.mjs';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

let pass = 0, fail = 0;
function eq(name, got, exp) {
  if (got === exp) { pass++; console.log(`✅ ${name}`); }
  else { fail++; console.log(`❌ ${name} — 기대=${exp} 실제=${got}`); }
}

// ── classifyFailure: 원인 분류 ─────────────────────────────────────────────
eq('challenge: 혼합 대소문자', classifyFailure('<html>Just A Moment...</html>', 403).cause, 'challenge');
eq('challenge: 전체 대문자', classifyFailure('<html>JUST A MOMENT</html>', 200).cause, 'challenge');
eq('challenge: ACCESS DENIED', classifyFailure('<html>ACCESS DENIED</html>', 403).cause, 'challenge');
eq('challenge: DataDome 원래 케이싱', classifyFailure('<html>DataDome protection</html>', 200).cause, 'challenge');
eq('challenge: 한국어 차단 문구', classifyFailure('<html>자동입력 방지문자</html>', 200).cause, 'challenge');
eq('challenge: cf-challenge 경로', classifyFailure('<html><script src="/cdn-cgi/challenge-platform/x"></script></html>', 200).cause, 'challenge');
eq('too_small: 3000 미만', classifyFailure('x'.repeat(1500), 200).cause, 'too_small');
eq('empty_result: 대형 정상 HTML', classifyFailure('<html>' + 'valid content '.repeat(500) + '</html>', 200).cause, 'empty_result');
eq('no_html: 빈 문자열', classifyFailure('', 0).cause, 'no_html');
eq('no_html: null', classifyFailure(null, 0).cause, 'no_html');
eq('no_html: undefined', classifyFailure(undefined).cause, 'no_html');

// ── detail: status/len 표기 ────────────────────────────────────────────────
eq('detail: status n/a 폴백', classifyFailure('<html>Just a moment</html>', 0).detail.includes('status=n/a'), true);
eq('detail: status 반영', classifyFailure('<html>Just a moment</html>', 403).detail.includes('status=403'), true);
eq('detail: len 표기(바이트 아님)', classifyFailure('x'.repeat(1500), 200).detail.includes('len=1500'), true);

// ── 마커 상수 무결성 (전부 소문자여야 toLowerCase 대조가 성립) ──────────────
eq('마커는 전부 소문자', CHALLENGE_MARKERS.every(m => m === m.toLowerCase()), true);

// ── logFailure: JOBSTACK_FETCH_DIAG_LOG 파일 로깅 ───────────────────────────
const dir = mkdtempSync(join(tmpdir(), 'fetch-diag-'));
const logPath = join(dir, 'diag.log');
try {
  process.env.JOBSTACK_FETCH_DIAG_LOG = logPath;
  logFailure('wanted', '<html>' + 'x'.repeat(5000) + '</html>', 0);
  const logged = readFileSync(logPath, 'utf8');
  eq('파일 로깅: 진단 라인 append', logged.includes('[fetch-jobs:diag] platform=wanted cause=empty_result'), true);
  eq('파일 로깅: 타임스탬프 포함', /\d{4}-\d{2}-\d{2}T/.test(logged), true);
} finally {
  delete process.env.JOBSTACK_FETCH_DIAG_LOG;
  rmSync(dir, { recursive: true, force: true });
}

// env 미설정 시 파일 로깅 안 함(예외 없이 stderr만) — 호출이 던지지 않으면 통과
try { logFailure('saramin', '', 0); eq('env 미설정: 예외 없음', true, true); }
catch { eq('env 미설정: 예외 없음', false, true); }

console.log(`\nPASS: ${pass} / FAIL: ${fail}`);
process.exit(fail === 0 ? 0 : 1);
