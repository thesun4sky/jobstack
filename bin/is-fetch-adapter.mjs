/**
 * insane-search 어댑터 브리지 — fetch-jobs.mjs(Node) ↔ is-fetch.py(curl_cffi).
 *
 * venv(bin/.is-venv) 가 있으면 is-fetch.py 로 URL HTML 을 확보하고, 없거나 어댑터가
 * 실패하면 null 을 돌려 호출측이 현행 Playwright 경로로 폴백하게 한다(실행계획 Phase 2).
 * spawn·경로·exists 를 주입 가능하게 열어 test/test-is-fetch-adapter.mjs 가 네트워크·
 * venv 없이 폴백/채택 분기를 검증한다. 경로는 이 파일 위치 기준(import.meta.url)으로
 * 해석해 cwd 가정을 없앤다.
 */
import { spawnSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const HERE = dirname(fileURLToPath(import.meta.url));
export const DEFAULT_VENV_PY = join(HERE, '.is-venv', 'bin', 'python');
export const DEFAULT_IS_FETCH = join(HERE, 'is-fetch.py');

/**
 * is-fetch.py 어댑터로 URL HTML 을 확보한다.
 * @param {string} url
 * @param {object} [opts] venvPy·script·timeoutMs·exists·spawn 주입(테스트용)
 * @returns {{ html: string, status: number, verdict: string } | null}
 *   null = 어댑터 미가용/실패(venv 부재·exit≠0·타임아웃·strong_ok 아님·비JSON) → 폴백 신호
 * timeoutMs 는 is-fetch.py 의 최악 소요(2 프로필 × TIMEOUT_S)보다 커야 첫 프로필 타임아웃
 * 후 두 번째 결과가 유실되지 않는다(리뷰 반영: 25s ≥ 2×10s).
 */
export function fetchViaIsFetch(url, opts = {}) {
  const {
    venvPy = DEFAULT_VENV_PY,
    script = DEFAULT_IS_FETCH,
    timeoutMs = 25000,
    exists = existsSync,
    spawn = spawnSync,
  } = opts;

  if (!exists(venvPy)) return null; // venv 미설치 = 어댑터 no-op → 폴백

  let res;
  try {
    res = spawn(venvPy, [script, url], {
      timeout: timeoutMs,
      killSignal: 'SIGKILL', // 프로세스 경계 — graceful cleanup 불필요, 좀비 방지
      maxBuffer: 32 * 1024 * 1024, // 사람인 검색 HTML ~2.4MB 여유
      encoding: 'utf8',
    });
  } catch {
    return null;
  }
  // status!==0: exit 3(curl_cffi 미설치) 또는 status null(타임아웃/kill) 포함 → 폴백
  if (!res || res.status !== 0 || !res.stdout) return null;

  let parsed;
  try {
    parsed = JSON.parse(res.stdout);
  } catch {
    return null;
  }
  // strong_ok + html 만 채택. too_small(에러 페이지·열화 응답 포함)·challenge·error 는
  // 현행 Playwright 경로로 폴백한다 — too_small 을 채택하면 사람인이 0건을 확정으로 처리해
  // 폴백을 잃는다(리뷰 반영). is-fetch 는 status>=400 을 error 로 분류하므로 4xx/5xx 도 폴백.
  if (parsed.verdict !== 'strong_ok' || !parsed.html) return null;
  return { html: parsed.html, status: parsed.status ?? 0, verdict: parsed.verdict };
}
