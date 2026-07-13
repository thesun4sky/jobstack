/**
 * 수집 실패 진단 — 크롤러가 0건을 수집했을 때 그 원인을 분류하고 로깅한다.
 *
 * HTTP 200을 받아도 WAF 챌린지 페이지일 수 있다("200은 성공이 아니라 검사 시작").
 * 0건 결과의 원인을 challenge / too_small / empty_result / no_html 로 분류해
 * "차단"과 "결과 없음"을 구분한다. classifyFailure 는 순수 함수라
 * test/test-fetch-diag.mjs 에서 직접 회귀 검증한다.
 */
import { appendFileSync } from 'node:fs';

// 마커는 소문자로 통일 — html.toLowerCase()와 대조해 WAF 응답의 케이싱 변형을 흡수한다.
export const CHALLENGE_MARKERS = [
  'just a moment', 'cf-browser-verification', '/cdn-cgi/challenge-platform',
  'datadome', 'g-recaptcha', 'recaptcha', '자동입력 방지',
  'access denied', '접근이 차단', 'request unsuccessful',
];

export function classifyFailure(html, status) {
  if (!html) return { cause: 'no_html', detail: `status=${status || 'n/a'}` };
  const lower = html.toLowerCase();
  const hit = CHALLENGE_MARKERS.find(m => lower.includes(m));
  if (hit) return { cause: 'challenge', detail: `marker="${hit}" status=${status || 'n/a'}` };
  // len 은 UTF-16 코드유닛 수(바이트 아님) — 한글 HTML에서 바이트와 다르므로 명시적으로 len 표기.
  if (html.length < 3000) return { cause: 'too_small', detail: `len=${html.length} status=${status || 'n/a'}` };
  return { cause: 'empty_result', detail: `len=${html.length} status=${status || 'n/a'}` };
}

// 진단 라인을 항상 stderr에 남기고, JOBSTACK_FETCH_DIAG_LOG 가 설정되면 그 파일에도 append.
// SKILL 실행 예시가 stdout JSON 캡처를 위해 stderr를 버려도(2>/dev/null) 파일 로그로 진단이 보존된다.
export function logFailure(platform, html, status) {
  const { cause, detail } = classifyFailure(html, status);
  const line = `[fetch-jobs:diag] platform=${platform} cause=${cause} ${detail}`;
  process.stderr.write(line + '\n');
  const logPath = process.env.JOBSTACK_FETCH_DIAG_LOG;
  if (logPath) {
    try {
      appendFileSync(logPath, `${new Date().toISOString()} ${line}\n`);
    } catch { /* 진단 로깅 실패는 수집을 방해하지 않는다 */ }
  }
}
