#!/usr/bin/env node
/**
 * test-saramin-api.mjs — bin/sources/saramin-api.mjs(사람인 오픈API 클라이언트) 회귀.
 *
 * fetchImpl 주입으로 네트워크 없이 통과한다. 가상 JSON 응답(가상 회사·공고 3건)의
 * 필드 매핑(마감일 KST 변환 포함)과 실패 규약(HTTP 오류·비JSON·키 없음 → null,
 * throw 하지 않음)을 검증한다. 타임아웃(AbortController) 경로는 생략한다.
 */
import assert from 'node:assert/strict';
import { fetchSaraminApi, readSaraminKey, SARAMIN_LOC_CD } from '../bin/sources/saramin-api.mjs';

let pass = 0;
const check = async (name, fn) => {
  try {
    await fn();
    console.log(`  [PASS] ${name}`);
    pass++;
  } catch (e) {
    console.error(`  [FAIL] ${name}: ${e.message}`);
    process.exitCode = 1;
  }
};

// KST 자정 경계를 손으로 계산하지 않고 Date.UTC 로 유도 — 의도를 코드로 드러낸다.
// 2026-06-14T15:00:00Z = 2026-06-15T00:00:00+09:00(KST 자정, 다음날로 넘어감).
const EPOCH_KST_MIDNIGHT_ROLLOVER = Date.UTC(2026, 5, 14, 15, 0, 0) / 1000;
// 2026-06-14T14:59:59Z = 2026-06-14T23:59:59+09:00(KST 자정 1초 전, 같은 날 유지).
const EPOCH_KST_ONE_SECOND_BEFORE_MIDNIGHT = Date.UTC(2026, 5, 14, 14, 59, 59) / 1000;

function fixtureJson() {
  return {
    jobs: {
      count: '3',
      job: [
        {
          url: 'http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=81000001',
          active: 1,
          company: { detail: { name: '가짜테크(주)' } },
          position: {
            title: '데이터사이언티스트 채용(가상)',
            'job-code': { code: '2247', name: '데이터 사이언티스트' },
          },
          'expiration-timestamp': String(EPOCH_KST_MIDNIGHT_ROLLOVER),
        },
        {
          url: 'http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=81000002',
          active: 1,
          company: { detail: { name: '모의상사(유)' } },
          position: {
            title: 'DevOps 엔지니어 채용(가상)',
            'job-code': { code: '2233', name: 'DevOps/시스템 관리자' },
          },
          'expiration-timestamp': EPOCH_KST_ONE_SECOND_BEFORE_MIDNIGHT,
        },
        {
          url: 'http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=81000003',
          active: 1,
          company: { detail: { name: '테스트랩스(주)' } },
          position: {
            title: 'QA 엔지니어 채용(가상)',
            'job-code': { code: '2231', name: 'QA/테스터' },
          },
          // expiration-timestamp 없음 — 상시채용류(마감일 미확인 폴백 검증)
        },
      ],
    },
  };
}

function okJsonFetch(body) {
  const calls = [];
  const impl = async (url, opts) => {
    calls.push({ url, opts });
    return { ok: true, status: 200, json: async () => body };
  };
  impl.calls = calls;
  return impl;
}

await check('매핑 — company/title/link/skills/deadline(KST 자정 롤오버 포함)', async () => {
  const result = await fetchSaraminApi(
    { accessKey: 'FAKE_KEY', keyword: '백엔드', limit: 3 },
    { fetchImpl: okJsonFetch(fixtureJson()) },
  );
  assert.ok(Array.isArray(result), '배열이 아님');
  assert.equal(result.length, 3);

  const a = result.find((j) => j.company === '가짜테크(주)');
  assert.ok(a, '가짜테크(주) 없음');
  assert.equal(a.platform, 'saramin');
  assert.equal(a.title, '데이터사이언티스트 채용(가상)');
  assert.equal(a.link, 'http://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=81000001');
  assert.equal(a.skills, '데이터 사이언티스트');
  assert.equal(a.dRemaining, '');
  assert.equal(a.deadline, '2026-06-15', 'KST 자정 경계 — 다음날로 롤오버돼야 함');

  const b = result.find((j) => j.company === '모의상사(유)');
  assert.ok(b, '모의상사(유) 없음');
  assert.equal(b.deadline, '2026-06-14', 'KST 자정 1초 전 — 같은 날 유지돼야 함');
  assert.equal(b.skills, 'DevOps/시스템 관리자');

  const c = result.find((j) => j.company === '테스트랩스(주)');
  assert.ok(c, '테스트랩스(주) 없음');
  assert.equal(c.deadline, '마감일 미확인', 'expiration-timestamp 없으면 미확인 폴백');
});

await check('HTTP 오류(500) → null', async () => {
  const fetchImpl = async () => ({ ok: false, status: 500, json: async () => ({}) });
  const result = await fetchSaraminApi({ accessKey: 'FAKE_KEY', keyword: 'x' }, { fetchImpl });
  assert.equal(result, null);
});

await check('비JSON 응답 → null', async () => {
  const fetchImpl = async () => ({
    ok: true,
    status: 200,
    json: async () => { throw new SyntaxError('Unexpected token — 비JSON 본문 시뮬레이션'); },
  });
  const result = await fetchSaraminApi({ accessKey: 'FAKE_KEY', keyword: 'x' }, { fetchImpl });
  assert.equal(result, null);
});

await check('키 없음(빈 문자열) → null, 네트워크 호출 0회', async () => {
  let called = 0;
  const fetchImpl = async () => { called++; return { ok: true, status: 200, json: async () => ({}) }; };
  const result = await fetchSaraminApi({ accessKey: '', keyword: 'x' }, { fetchImpl });
  assert.equal(result, null);
  assert.equal(called, 0);
});

await check('네트워크 오류(fetch reject) → null', async () => {
  const fetchImpl = async () => { throw new Error('network down'); };
  const result = await fetchSaraminApi({ accessKey: 'FAKE_KEY', keyword: 'x' }, { fetchImpl });
  assert.equal(result, null);
});

await check('쿼리 파라미터 조립 — access-key/keywords/count/sort/exp_cd/loc_cd', async () => {
  const fetchImpl = okJsonFetch({ jobs: { job: [] } });
  await fetchSaraminApi(
    { accessKey: 'FAKE_KEY', keyword: '백엔드 개발', limit: 5, career: 'entry', location: 'seoul' },
    { fetchImpl },
  );
  assert.equal(fetchImpl.calls.length, 1);
  const requested = new URL(fetchImpl.calls[0].url);
  assert.equal(requested.origin + requested.pathname, 'https://oapi.saramin.co.kr/job-search');
  assert.equal(requested.searchParams.get('access-key'), 'FAKE_KEY');
  assert.equal(requested.searchParams.get('keywords'), '백엔드 개발');
  assert.equal(requested.searchParams.get('count'), '5');
  assert.equal(requested.searchParams.get('sort'), 'pd');
  assert.equal(requested.searchParams.get('exp_cd'), '1', 'entry → exp_cd=1(신입)');
  assert.equal(requested.searchParams.get('loc_cd'), SARAMIN_LOC_CD.seoul);
});

await check('쿼리 파라미터 — career=experienced → exp_cd=2, location 생략 시 loc_cd 없음', async () => {
  const fetchImpl = okJsonFetch({ jobs: { job: [] } });
  await fetchSaraminApi(
    { accessKey: 'FAKE_KEY', keyword: '백엔드', career: 'experienced' },
    { fetchImpl },
  );
  const requested = new URL(fetchImpl.calls[0].url);
  assert.equal(requested.searchParams.get('exp_cd'), '2', 'experienced → exp_cd=2(경력)');
  assert.equal(requested.searchParams.get('loc_cd'), null);
});

await check('readSaraminKey — 성공(spawn 주입, status 0)', () => {
  const spawn = () => ({ status: 0, stdout: 'sr-fake-access-key-1234\n' });
  assert.equal(readSaraminKey('/fake/jobstack-config', { spawn }), 'sr-fake-access-key-1234');
});

await check('readSaraminKey — 미설정(status 1) → 빈 문자열', () => {
  const spawn = () => ({ status: 1, stdout: '' });
  assert.equal(readSaraminKey('/fake/jobstack-config', { spawn }), '');
});

await check('readSaraminKey — spawn 예외 → 빈 문자열(throw 하지 않음)', () => {
  const spawn = () => { throw new Error('spawn ENOENT'); };
  assert.equal(readSaraminKey('/fake/jobstack-config', { spawn }), '');
});

console.log(`\n[${process.exitCode ? 'FAIL' : 'PASS'}] test-saramin-api — ${pass} passed`);
