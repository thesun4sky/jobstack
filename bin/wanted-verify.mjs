/**
 * 원티드 마감 검증 — api/v4/jobs/{id} detail 기반 생사 판정.
 *
 * 배경(2026-07-19 prod 사고): 원티드 HTML 페이지(wd/{id})는 마감 배너를 JS로
 * 렌더링해 HTML fetch로는 마감 감지가 불가하고, due_time:null(상시채용) 공고는
 * 날짜 필터로도 걸러지지 않는다. 실제로 마감 공고 3건이 검증 없이 유저에게
 * 노출됐고, HTML 기반 "재확인"조차 3/3을 진행 중으로 오판했다.
 * → 마감 판정은 이 모듈의 detail API 경로만 신뢰한다(fail-closed).
 *
 * classify/format 계열은 순수 함수라 test/test-wanted-verify.mjs 에서 직접
 * 회귀 검증하고, fetch 는 주입 가능(fetchImpl)해 네트워크 없이 테스트한다.
 */

const API_BASE = 'https://www.wanted.co.kr/api/v4/jobs/';
const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';
const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** KST 기준 YYYY-MM-DD. */
export function kstDateStr(now = new Date()) {
  return new Date(now.getTime() + KST_OFFSET_MS).toISOString().slice(0, 10);
}

/** URL 또는 숫자 문자열에서 원티드 job ID 추출. 실패 시 null. */
export function extractWantedId(input) {
  const s = String(input ?? '').trim();
  if (/^\d+$/.test(s)) return s;
  const m = s.match(/wanted\.co\.kr\/wd\/(\d+)/);
  return m ? m[1] : null;
}

/**
 * detail API JSON → 생사 판정 (순수 함수).
 * closed: status!=='active' 또는 hidden===true 또는 due_time 경과(KST)
 * unknown: 응답 형태가 예상과 다름 (fail-closed — 호출측에서 제외)
 */
export function classifyDetail(json, now = new Date()) {
  const job = json?.job;
  if (!job || typeof job !== 'object' || typeof job.status === 'undefined') {
    return { verdict: 'unknown', cause: 'parse' };
  }
  const dueTime = job.due_time ? String(job.due_time).slice(0, 10) : null;
  const base = { status: job.status, hidden: job.hidden === true, dueTime };
  if (job.status !== 'active' || job.hidden === true) {
    return { verdict: 'closed', cause: 'status', ...base };
  }
  if (dueTime && dueTime < kstDateStr(now)) {
    return { verdict: 'closed', cause: 'due_passed', ...base };
  }
  return { verdict: 'active', ...base };
}

/**
 * deadline/dRemaining 필드 생성 (순수 함수).
 * 형식은 기존 파이프라인과의 호환 계약:
 * - deadline "YYYY-MM-DD 마감" — jobclaw parseDeadline 의 (\d{4})[-.](\d{1,2})[-.](\d{1,2})
 *   정규식이 선행 특수문자 없이 매칭되도록 날짜가 앞에 온다.
 * - dRemaining 은 jumpit 관례(D-N / D-day / 상시채용)를 따른다.
 */
export function formatDeadlineFields(dueTime, now = new Date()) {
  if (!dueTime) return { deadline: '상시채용', dRemaining: '상시채용' };
  const today = kstDateStr(now);
  const days = Math.round((Date.parse(dueTime) - Date.parse(today)) / 86_400_000);
  return {
    deadline: `${dueTime} 마감`,
    dRemaining: days <= 0 ? 'D-day' : `D-${days}`,
  };
}

/**
 * detail API 1건 조회. 5xx/네트워크 오류는 1회 재시도, 개별 5초 타임아웃.
 * 실패는 verdict:'unknown' + cause(http_NNN|timeout|network|parse)로 반환 — throw 하지 않는다.
 */
export async function fetchWantedDetail(id, opts = {}) {
  const { fetchImpl = fetch, timeoutMs = 5000, retries = 1 } = opts;
  let last = { verdict: 'unknown', cause: 'network' };
  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const resp = await fetchImpl(`${API_BASE}${id}`, {
        headers: { 'User-Agent': UA, Accept: 'application/json' },
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!resp.ok) {
        last = { verdict: 'unknown', cause: `http_${resp.status}` };
        if (resp.status >= 500 && attempt < retries) continue;
        return last;
      }
      let json;
      try { json = await resp.json(); } catch { return { verdict: 'unknown', cause: 'parse' }; }
      return classifyDetail(json, opts.now);
    } catch (err) {
      last = { verdict: 'unknown', cause: err?.name === 'TimeoutError' || err?.name === 'AbortError' ? 'timeout' : 'network' };
      if (attempt < retries) continue;
    }
  }
  return last;
}

/**
 * 수집된 원티드 공고 배열을 전수 검증(fail-closed).
 * - active 만 유지 + deadline/dRemaining 을 due_time 실값으로 교체
 * - closed/unknown 제외, unknown 은 verify_fail 진단 라인
 * - 실패율 > outageThreshold 면 전체 [] 반환(verify_outage) — 미검증 공고를
 *   내보내느니 원티드 섹션을 비운다. 타 플랫폼·전일 캐시가 자연 폴백.
 * 진단 라인은 fetch-diag 관례(`[fetch-jobs:diag] ...`)를 따른다.
 */
export async function verifyWantedJobs(jobs, opts = {}) {
  const {
    fetchImpl,
    now = new Date(),
    concurrency = 3,
    delayMs = 200,
    outageThreshold = 0.5,
    log = (line) => process.stderr.write(line + '\n'),
  } = opts;
  if (!Array.isArray(jobs) || jobs.length === 0) {
    return { jobs: [], stats: { scraped: 0, excludedClosed: 0, failed: 0, outage: false } };
  }

  const results = new Array(jobs.length);
  let cursor = 0;
  async function worker() {
    while (cursor < jobs.length) {
      const i = cursor++;
      const id = extractWantedId(jobs[i]?.link);
      if (!id) {
        results[i] = { verdict: 'unknown', cause: 'no_id' };
      } else {
        results[i] = { id, ...(await fetchWantedDetail(id, { fetchImpl, now })) };
      }
      if (results[i].verdict === 'unknown') {
        log(`[fetch-jobs:diag] wanted verify_fail id=${id ?? 'n/a'} cause=${results[i].cause}`);
      }
      if (delayMs > 0 && cursor < jobs.length) await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  await Promise.all(Array.from({ length: Math.min(concurrency, jobs.length) }, worker));

  const failed = results.filter((r) => r.verdict === 'unknown').length;
  if (failed / jobs.length > outageThreshold) {
    log(`[fetch-jobs:diag] wanted verify_outage rate=${Math.round((failed / jobs.length) * 100)}%`);
    return { jobs: [], stats: { scraped: jobs.length, excludedClosed: 0, failed, outage: true } };
  }

  const kept = [];
  let excludedClosed = 0;
  for (let i = 0; i < jobs.length; i++) {
    const r = results[i];
    if (r.verdict === 'active') {
      kept.push({ ...jobs[i], ...formatDeadlineFields(r.dueTime, now) });
    } else if (r.verdict === 'closed') {
      excludedClosed++;
    }
    // unknown → fail-closed 제외 (개별 진단 라인은 위에서 기록됨)
  }
  log(`[fetch-jobs:diag] wanted verified=${jobs.length} excluded_closed=${excludedClosed}`);
  return { jobs: kept, stats: { scraped: jobs.length, excludedClosed, failed, outage: false } };
}

/** verify 서브커맨드 본체: URL/ID 목록 → 판정 배열 (Playwright 불필요). */
export async function verifyInputs(inputs, opts = {}) {
  const out = [];
  for (const input of inputs) {
    const id = extractWantedId(input);
    if (!id) {
      out.push({ input: String(input), id: null, verdict: 'unknown', cause: 'bad_input' });
      continue;
    }
    const r = await fetchWantedDetail(id, opts);
    out.push({
      input: String(input),
      id,
      verdict: r.verdict,
      status: r.status ?? null,
      hidden: r.hidden ?? null,
      due_time: r.dueTime ?? null,
      ...(r.cause ? { cause: r.cause } : {}),
    });
    if (opts.delayMs !== 0) await new Promise((res) => setTimeout(res, opts.delayMs ?? 200));
  }
  return out;
}
