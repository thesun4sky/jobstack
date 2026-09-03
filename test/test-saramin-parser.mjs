#!/usr/bin/env node
/**
 * test-saramin-parser.mjs — bin/parsers/saramin.mjs(cheerio 정적 HTML 파서) 회귀.
 *
 * test/sample-data/saramin-search.html(합성 픽스처, 실명·실제 회사 데이터 없음)을
 * 파싱해 fetch-jobs.mjs 의 saramin page.evaluate 파서와 같은 마감일 규칙·절대 URL
 * 복원·title/company 없는 카드 제외가 유지되는지 검증한다. now 주입으로 "~ MM/DD"
 * 마감일의 연도 롤오버를 결정적으로 확인한다.
 *
 * 네트워크 없이 통과해야 한다. cheerio 가 설치돼 있어야 한다(bin/ 에서 npm install).
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseSaraminSearch } from '../bin/parsers/saramin.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const FIXTURE = readFileSync(join(HERE, 'sample-data', 'saramin-search.html'), 'utf8');

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

const byCompany = (jobs, company) => jobs.find((j) => j.company === company);

// 롤오버 없는 기준일 — "~ 01/05" 카드가 같은 해로 남는 것을 확인하는 기준선(2026-01-03).
const BASELINE_NOW = new Date(2026, 0, 3);
// 12월 기준일 — "~ 01/05" 가 다음 해로 롤오버되는지 확인(2026-12-20).
const DECEMBER_NOW = new Date(2026, 11, 20);

const baseline = await parseSaraminSearch(FIXTURE, 20, BASELINE_NOW);

await check('총 6건 파싱(깨진 카드 1건 제외)', () => {
  assert.equal(baseline.length, 6);
});

await check('전 항목 platform=saramin, dRemaining/skills 는 빈 문자열(동일 객체 형태)', () => {
  assert.ok(baseline.every((j) => j.platform === 'saramin'));
  assert.ok(baseline.every((j) => j.dRemaining === '' && j.skills === ''));
});

await check('카드1: "~ MM/DD" 형식 + 공백 정리(연속 공백·개행 → 한 칸, trim)', () => {
  const job = byCompany(baseline, '가짜테크(주)');
  assert.ok(job, '가짜테크(주) 카드 없음');
  assert.equal(job.title, '백엔드 신입 개발자 채용(가상)');
  assert.equal(job.deadline, '2026-01-05');
});

await check('카드1 롤오버: now 를 12월로 주면 "~ 01/05" 가 다음 해', async () => {
  const rolled = await parseSaraminSearch(FIXTURE, 20, DECEMBER_NOW);
  const job = byCompany(rolled, '가짜테크(주)');
  assert.ok(job, '가짜테크(주) 카드 없음');
  assert.equal(job.deadline, '2027-01-05');
});

await check('카드2: "YYYY.MM.DD" 형식 그대로 반영', () => {
  const job = byCompany(baseline, '모의상사(유)');
  assert.ok(job, '모의상사(유) 카드 없음');
  assert.equal(job.deadline, '2026-12-31');
});

await check('카드3: 상시채용', () => {
  const job = byCompany(baseline, '테스트랩스(주)');
  assert.ok(job, '테스트랩스(주) 카드 없음');
  assert.equal(job.deadline, '상시채용');
});

await check('카드4: 채용시마감', () => {
  const job = byCompany(baseline, '가상소프트(주)');
  assert.ok(job, '가상소프트(주) 카드 없음');
  assert.equal(job.deadline, '채용시마감');
});

await check('카드5: 날짜 정보 없음 → 마감일 미확인', () => {
  const job = byCompany(baseline, '널데이터(주)');
  assert.ok(job, '널데이터(주) 카드 없음');
  assert.equal(job.deadline, '마감일 미확인');
});

await check('카드7: script 태그의 JSON-LD 날짜가 deadline 으로 오검출되지 않음(스크립트 제거)', () => {
  const job = byCompany(baseline, '메타데이터(주)');
  assert.ok(job, '메타데이터(주) 카드 없음');
  assert.equal(job.title, '플랫폼 엔지니어 채용(가상)');
  // .date/.job_date 요소가 없는 카드 — script 내부의 "2099.12.31" 이 fullText 에 섞이면
  // ymMatch 정규식이 오탐해 deadline 이 '2099-12-31' 이 된다(수정 전 회귀 포인트).
  assert.equal(job.deadline, '마감일 미확인');
});

await check('깨진 카드(title 없음) 제외 — 결과에 존재하지 않음', () => {
  assert.equal(byCompany(baseline, '유령회사'), undefined);
});

await check('limit 적용 — limit=3 이면 앞 3건만 반환', async () => {
  const limited = await parseSaraminSearch(FIXTURE, 3, BASELINE_NOW);
  assert.equal(limited.length, 3);
  assert.ok(limited.every((j) => j.title && j.company));
});

await check('링크 절대화 — 상대경로는 https://www.saramin.co.kr 접두', () => {
  const job = byCompany(baseline, '가짜테크(주)');
  assert.equal(job.link, 'https://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=51000001');
});

await check('링크 절대화 — 이미 절대경로면 그대로 유지', () => {
  const job = byCompany(baseline, '널데이터(주)');
  assert.equal(job.link, 'https://www.saramin.co.kr/zf_user/jobs/relay/view?rec_idx=51000005');
});

await check('html 이 빈 문자열이어도 예외 없이 빈 배열', async () => {
  assert.deepEqual(await parseSaraminSearch('', 20, BASELINE_NOW), []);
});

console.log(`\n[${process.exitCode ? 'FAIL' : 'PASS'}] test-saramin-parser — ${pass} passed`);
