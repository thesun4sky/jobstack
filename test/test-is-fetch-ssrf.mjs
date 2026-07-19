#!/usr/bin/env node
/**
 * test-is-fetch-ssrf.mjs — is-fetch.py SSRF 가드·상태코드 분류 회귀 (curl_cffi 불필요).
 *
 * curl_cffi 없이도 SSRF 차단 경로는 네트워크를 건드리기 전에 동작해야 한다:
 * 위험 스킴(file://, gopher://)·내부 IP(127.0.0.1, 169.254.169.254)는 verdict:error +
 * detail 'blocked_unsafe_url' 로 즉시 반환하고 exit 0(stdout JSON 유효).
 * curl_cffi 미설치 환경에서도 이 검증은 _load_curl_cffi 호출 전에 수행되므로 통과한다.
 */
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = dirname(fileURLToPath(import.meta.url));
const SCRIPT = join(HERE, '..', 'bin', 'is-fetch.py');
let pass = 0;
const check = (name, fn) => {
  try { fn(); console.log(`  [PASS] ${name}`); pass++; }
  catch (e) { console.error(`  [FAIL] ${name}: ${e.message}`); process.exitCode = 1; }
};

function run(url) {
  const r = spawnSync('python3', [SCRIPT, url], { encoding: 'utf8', timeout: 10000 });
  let json = null;
  try { json = JSON.parse(r.stdout); } catch { /* noop */ }
  return { code: r.status, json, stderr: r.stderr };
}

const BLOCKED = [
  ['file:// 로컬파일', 'file:///etc/passwd'],
  ['gopher://', 'gopher://127.0.0.1:6379/_INFO'],
  ['dict://', 'dict://127.0.0.1:11211/stat'],
  ['loopback', 'http://127.0.0.1/'],
  ['GCP metadata', 'http://169.254.169.254/latest/meta-data/'],
  ['사설대역', 'http://10.0.0.1/'],
  ['localhost 이름', 'http://localhost:8080/'],
];

for (const [label, url] of BLOCKED) {
  check(`SSRF 차단: ${label}`, () => {
    const { code, json } = run(url);
    assert.equal(code, 0, 'exit 0(stdout JSON 유효)');
    assert.ok(json, 'JSON 파싱');
    assert.equal(json.verdict, 'error', `verdict=error 여야 함 (got ${json?.verdict})`);
    assert.ok(String(json.detail).includes('blocked_unsafe_url'), `blocked_unsafe_url detail 여야 함 (got ${json?.detail})`);
    assert.equal(json.html, '', 'html 비어야 함');
  });
}

check('스킴 없는 상대경로도 차단', () => {
  const { json } = run('/etc/passwd');
  assert.equal(json?.verdict, 'error');
  assert.ok(String(json?.detail).includes('blocked_unsafe_url'));
});

console.log(`\n[${process.exitCode ? 'FAIL' : 'PASS'}] test-is-fetch-ssrf — ${pass} passed`);
