#!/usr/bin/env node
/**
 * wanted-verify.mjs 회귀 테스트 — 원티드 detail API 마감 검증(fail-closed).
 * 실행: node test/test-wanted-verify.mjs
 * 네트워크 없음 — fetchImpl 주입으로 API 응답을 mock 한다.
 */
import {
  extractWantedId, classifyDetail, formatDeadlineFields,
  fetchWantedDetail, verifyWantedJobs, verifyInputs, kstDateStr,
} from '../bin/wanted-verify.mjs';

let pass = 0, fail = 0;
function eq(name, got, exp) {
  const g = JSON.stringify(got), e = JSON.stringify(exp);
  if (g === e) { pass++; console.log(`✅ ${name}`); }
  else { fail++; console.log(`❌ ${name} — 기대=${e} 실제=${g}`); }
}

// 고정 시각: KST 2026-07-19 (UTC 2026-07-19T05:00Z → KST 14:00)
const NOW = new Date('2026-07-19T05:00:00Z');
eq('kstDateStr: 고정 시각', kstDateStr(NOW), '2026-07-19');
eq('kstDateStr: UTC 자정 직전(KST 익일)', kstDateStr(new Date('2026-07-19T16:00:00Z')), '2026-07-20');

// ── extractWantedId ────────────────────────────────────────────────────────
eq('id: 표준 URL', extractWantedId('https://www.wanted.co.kr/wd/360071'), '360071');
eq('id: www 없는 URL+쿼리', extractWantedId('https://wanted.co.kr/wd/280416?utm=x'), '280416');
eq('id: 숫자 문자열', extractWantedId('175338'), '175338');
eq('id: 무관 URL', extractWantedId('https://jobkorea.co.kr/Recruit/GI_Read/123'), null);
eq('id: null 입력', extractWantedId(null), null);

// ── classifyDetail ─────────────────────────────────────────────────────────
const J = (job) => ({ job });
eq('classify: active 상시채용', classifyDetail(J({ status: 'active', hidden: false, due_time: null }), NOW).verdict, 'active');
eq('classify: active 미래 마감', classifyDetail(J({ status: 'active', hidden: false, due_time: '2026-07-31' }), NOW).verdict, 'active');
eq('classify: 오늘 마감은 active(D-0 유지)', classifyDetail(J({ status: 'active', hidden: false, due_time: '2026-07-19' }), NOW).verdict, 'active');
eq('classify: status close', classifyDetail(J({ status: 'close', hidden: true, due_time: null }), NOW).verdict, 'closed');
eq('classify: hidden true(status active)', classifyDetail(J({ status: 'active', hidden: true, due_time: null }), NOW).verdict, 'closed');
eq('classify: due 경과', classifyDetail(J({ status: 'active', hidden: false, due_time: '2026-07-18' }), NOW), { verdict: 'closed', cause: 'due_passed', status: 'active', hidden: false, dueTime: '2026-07-18' });
eq('classify: datetime due 절삭', classifyDetail(J({ status: 'active', hidden: false, due_time: '2026-07-31T23:59:59' }), NOW).dueTime, '2026-07-31');
eq('classify: job 누락 → unknown', classifyDetail({}, NOW), { verdict: 'unknown', cause: 'parse' });
eq('classify: status 필드 누락 → unknown', classifyDetail(J({ hidden: false }), NOW).verdict, 'unknown');

// ── formatDeadlineFields (parseDeadline 호환 계약 포함) ─────────────────────
eq('format: null → 상시채용', formatDeadlineFields(null, NOW), { deadline: '상시채용', dRemaining: '상시채용' });
eq('format: 미래 → 날짜 마감 + D-N', formatDeadlineFields('2026-07-31', NOW), { deadline: '2026-07-31 마감', dRemaining: 'D-12' });
eq('format: 오늘 → D-day', formatDeadlineFields('2026-07-19', NOW).dRemaining, 'D-day');
// jobclaw parseDeadline(src/db/job-cache-db.ts) 정규식이 선행 특수문자 없이 매칭돼야 함
const PARSE_DEADLINE_RE = /(\d{4})[-.](\d{1,2})[-.](\d{1,2})/;
eq('format: parseDeadline 정규식 호환', PARSE_DEADLINE_RE.test(formatDeadlineFields('2026-07-31', NOW).deadline), true);
eq('format: 날짜가 문자열 선두', formatDeadlineFields('2026-07-31', NOW).deadline.startsWith('2026-07-31'), true);

// ── fetchWantedDetail (mock fetch) ─────────────────────────────────────────
const okResp = (job) => ({ ok: true, status: 200, json: async () => ({ job }) });
const errResp = (status) => ({ ok: false, status, json: async () => ({}) });

{
  const r = await fetchWantedDetail('1', { fetchImpl: async () => okResp({ status: 'active', hidden: false, due_time: null }), now: NOW });
  eq('fetch: 정상 active', r.verdict, 'active');
}
{
  let calls = 0;
  const r = await fetchWantedDetail('1', {
    fetchImpl: async () => (++calls === 1 ? errResp(503) : okResp({ status: 'close', hidden: true, due_time: null })),
    now: NOW,
  });
  eq('fetch: 5xx 1회 재시도 후 성공', r.verdict, 'closed');
  eq('fetch: 재시도 호출 수', calls, 2);
}
{
  let calls = 0;
  const r = await fetchWantedDetail('1', { fetchImpl: async () => { calls++; return errResp(429); }, now: NOW });
  eq('fetch: 429 는 재시도 없이 unknown', r, { verdict: 'unknown', cause: 'http_429' });
  eq('fetch: 429 호출 1회', calls, 1);
}
{
  const abortErr = Object.assign(new Error('aborted'), { name: 'TimeoutError' });
  const r = await fetchWantedDetail('1', { fetchImpl: async () => { throw abortErr; }, now: NOW });
  eq('fetch: 타임아웃 → unknown/timeout', r, { verdict: 'unknown', cause: 'timeout' });
}
{
  const r = await fetchWantedDetail('1', { fetchImpl: async () => ({ ok: true, status: 200, json: async () => { throw new Error('bad json'); } }), now: NOW });
  eq('fetch: JSON 파싱 실패 → unknown/parse', r, { verdict: 'unknown', cause: 'parse' });
}

// ── verifyWantedJobs — 전수 검증·fail-closed·진단 라인 ──────────────────────
const mkJob = (id) => ({ platform: 'wanted', company: 'c', title: 't', deadline: '마감일 미확인', dRemaining: '', link: `https://www.wanted.co.kr/wd/${id}`, skills: '' });
const detailDb = {
  100: { status: 'active', hidden: false, due_time: '2026-07-31' },
  200: { status: 'close', hidden: true, due_time: null },
  300: { status: 'active', hidden: false, due_time: null },
  400: { status: 'active', hidden: false, due_time: '2026-07-01' }, // 경과
};
const dbFetch = async (url) => {
  const id = url.match(/(\d+)$/)[1];
  return detailDb[id] ? okResp(detailDb[id]) : errResp(404);
};

{
  const lines = [];
  const { jobs, stats } = await verifyWantedJobs(
    [mkJob(100), mkJob(200), mkJob(300), mkJob(400)],
    { fetchImpl: dbFetch, now: NOW, delayMs: 0, log: (l) => lines.push(l) },
  );
  eq('verify: active 만 유지(2건)', jobs.length, 2);
  eq('verify: deadline 실값 교체', jobs[0].deadline, '2026-07-31 마감');
  eq('verify: 상시채용 교체', jobs[1].deadline, '상시채용');
  eq('verify: closed 2건 제외(close+due경과)', stats.excludedClosed, 2);
  eq('verify: verified 진단 라인', lines.some((l) => l === '[fetch-jobs:diag] wanted verified=4 excluded_closed=2'), true);
  eq('verify: outage 아님', stats.outage, false);
}
{
  const lines = [];
  const { jobs, stats } = await verifyWantedJobs(
    [mkJob(100), mkJob(900), mkJob(901), mkJob(902)], // 3/4 = 75% 실패(404)
    { fetchImpl: dbFetch, now: NOW, delayMs: 0, log: (l) => lines.push(l) },
  );
  eq('outage: 전체 [] 반환', jobs.length, 0);
  eq('outage: 플래그', stats.outage, true);
  eq('outage: 진단 라인', lines.some((l) => l.includes('wanted verify_outage rate=75%')), true);
  eq('outage: verify_fail 개별 라인', lines.filter((l) => l.includes('verify_fail')).length, 3);
}
{
  const lines = [];
  const badLink = { ...mkJob(100), link: 'https://example.com/x' };
  const { jobs } = await verifyWantedJobs(
    [badLink, mkJob(100), mkJob(300)],
    { fetchImpl: dbFetch, now: NOW, delayMs: 0, log: (l) => lines.push(l) },
  );
  eq('no_id: 제외 + 나머지 유지', jobs.length, 2);
  eq('no_id: 진단 cause', lines.some((l) => l.includes('cause=no_id')), true);
}
{
  const { jobs, stats } = await verifyWantedJobs([], { fetchImpl: dbFetch, delayMs: 0 });
  eq('빈 입력: 그대로 통과', { n: jobs.length, outage: stats.outage }, { n: 0, outage: false });
}

// ── verifyInputs — verify 서브커맨드 계약 ───────────────────────────────────
{
  const out = await verifyInputs(['https://www.wanted.co.kr/wd/200', 'garbage', '100'], { fetchImpl: dbFetch, now: NOW, delayMs: 0 });
  eq('verifyInputs: closed 판정', { id: out[0].id, verdict: out[0].verdict, hidden: out[0].hidden }, { id: '200', verdict: 'closed', hidden: true });
  eq('verifyInputs: bad_input', { id: out[1].id, verdict: out[1].verdict, cause: out[1].cause }, { id: null, verdict: 'unknown', cause: 'bad_input' });
  eq('verifyInputs: active + due', { verdict: out[2].verdict, due: out[2].due_time }, { verdict: 'active', due: '2026-07-31' });
}

console.log(`\nPASS: ${pass} / FAIL: ${fail}`);
process.exit(fail === 0 ? 0 : 1);
