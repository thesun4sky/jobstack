#!/usr/bin/env node
/**
 * test-is-fetch-adapter.mjs — insane-search 어댑터 브리지 + verdict 동기화 회귀.
 *
 * 네트워크·curl_cffi·venv 없이 통과해야 한다. 어댑터 경로는 가짜 어댑터 스크립트(sh)를
 * venvPy 로 주입해 spawnSync 를 실제로 태우고, 폴백 선택은 exists 주입으로 검증한다.
 * verdict 분류의 파이썬-노드 동기화는 fetch-diag.mjs 의 CHALLENGE_MARKERS 가 is-fetch.py
 * 소스에 전부 들어있는지로 강제한다(두 구현이 갈라지면 여기서 깨진다).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { fetchViaIsFetch } from '../bin/is-fetch-adapter.mjs';
import { CHALLENGE_MARKERS } from '../bin/fetch-diag.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const BIN = join(HERE, '..', 'bin');
let pass = 0;
const check = (name, fn) => {
  try {
    fn();
    console.log(`  [PASS] ${name}`);
    pass++;
  } catch (e) {
    console.error(`  [FAIL] ${name}: ${e.message}`);
    process.exitCode = 1;
  }
};

// 어댑터 결과는 spawn 주입으로 흉내낸다 — 실제 실행 파일을 /tmp 에 만들지 않는다.
// (noexec 로 마운트된 러너에서 임시 실행 파일이 막혀 테스트가 깨지던 문제 회피, 리뷰 반영.)
// exists:true 로 venv 존재를 가정하고 spawnSync 반환값({status, stdout})만 주입한다.
const spawnReturning = (result) => () => result;
const adapt = (spawnResult, opts = {}) =>
  fetchViaIsFetch('https://x', { venvPy: '/fake/py', exists: () => true, spawn: spawnReturning(spawnResult), ...opts });

try {
  // ── 1. venv 부재 → null(현행 Playwright 경로 폴백 신호) ──
  check('venv 부재 시 null 반환(폴백 선택)', () => {
    const r = fetchViaIsFetch('https://www.saramin.co.kr/x', { exists: () => false });
    assert.equal(r, null);
  });

  // ── 2. 어댑터 경로 — 채택/폴백 분기 ──
  check('strong_ok JSON → html 채택', () => {
    const bigHtml = `<html>${'x'.repeat(5000)}</html>`;
    const r = adapt({ status: 0, stdout: JSON.stringify({ html: bigHtml, verdict: 'strong_ok', status: 200 }) });
    assert.ok(r, 'null 이 아니어야 함');
    assert.equal(r.verdict, 'strong_ok');
    assert.equal(r.status, 200);
    assert.equal(r.html, bigHtml);
  });

  check('too_small JSON → null(폴백) — 열화 응답을 채택해 사람인 폴백 잃지 않게(리뷰 반영)', () => {
    assert.equal(adapt({ status: 0, stdout: JSON.stringify({ html: '<html>tiny</html>', verdict: 'too_small', status: 200 }) }), null);
  });

  check('타임아웃(status null) → null(폴백)', () => {
    assert.equal(adapt({ status: null, stdout: '' }), null);
  });

  check('challenge verdict → null(폴백)', () => {
    assert.equal(adapt({ status: 0, stdout: JSON.stringify({ html: '<html>just a moment</html>', verdict: 'challenge', status: 403 }) }), null);
  });

  check('error verdict → null(폴백)', () => {
    assert.equal(adapt({ status: 0, stdout: JSON.stringify({ html: '', verdict: 'error', status: null }) }), null);
  });

  check('exit 3(curl_cffi 미설치 no-op) → null(폴백)', () => {
    assert.equal(adapt({ status: 3, stdout: '' }), null);
  });

  check('비-JSON stdout → null(폴백)', () => {
    assert.equal(adapt({ status: 0, stdout: 'not json at all' }), null);
  });

  check('html 없는 strong_ok → null(폴백)', () => {
    assert.equal(adapt({ status: 0, stdout: JSON.stringify({ html: '', verdict: 'strong_ok', status: 200 }) }), null);
  });

  // ── 3. verdict 분류 파이썬-노드 동기화 ──
  check('CHALLENGE_MARKERS 전부 is-fetch.py 에 존재(동기화)', () => {
    const src = readFileSync(join(BIN, 'is-fetch.py'), 'utf8');
    for (const m of CHALLENGE_MARKERS) {
      assert.ok(src.includes(m), `is-fetch.py 에 마커 누락: "${m}"`);
    }
  });

  check('too_small 임계(3000) 양쪽 동기화', () => {
    const src = readFileSync(join(BIN, 'is-fetch.py'), 'utf8');
    assert.ok(/TOO_SMALL_LEN\s*=\s*3000/.test(src), 'is-fetch.py TOO_SMALL_LEN=3000 아님');
    const diag = readFileSync(join(BIN, 'fetch-diag.mjs'), 'utf8');
    assert.ok(/<\s*3000/.test(diag), 'fetch-diag.mjs 의 3000자 기준 확인 실패');
  });
} finally { /* 임시 실행 파일 없음 — spawn 주입 방식이라 정리 불필요 */ }

console.log(`\n[${process.exitCode ? 'FAIL' : 'PASS'}] test-is-fetch-adapter — ${pass} passed`);
