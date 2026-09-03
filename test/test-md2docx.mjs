#!/usr/bin/env node
/**
 * test-md2docx.mjs — bin/md2docx.mjs 회귀 (U-13 Node docx 폴백 변환기).
 *
 * toParagraphs/inlineRuns 를 직접 호출해 반환 배열의 표면적인 형태를 확인하고, 실제로
 * Packer 로 .docx 를 만들어 zip 안 word/document.xml 을 열어(python3 zipfile 을
 * child_process 로 호출) 굵게 분리·헤더 행 굵게·펜스 블록·번호 목록 텍스트 유지 등 서식이
 * 기대대로 들어갔는지, 표/이미지 태그가 전혀 없는지 검증한다. docx 클래스(Document/Packer)는
 * bin/node_modules/docx 를 상대 경로로 직접 불러온다 — test/ 에는 자체 node_modules 가 없다.
 */
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { inlineRuns, toParagraphs } from '../bin/md2docx.mjs';
import { Document, Packer } from '../bin/node_modules/docx/dist/index.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, '..');
const MD2DOCX = join(REPO, 'bin', 'md2docx.mjs');

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

const WORK = mkdtempSync(join(tmpdir(), 'md2docx-test-'));

/** python3 zipfile 로 .docx(zip) 안의 word/document.xml 텍스트를 읽는다. */
function readDocumentXml(docxPath) {
  const script =
    "import sys, zipfile\n" +
    "with zipfile.ZipFile(sys.argv[1]) as z:\n" +
    "    sys.stdout.write(z.read('word/document.xml').decode('utf-8'))\n";
  return execFileSync('python3', ['-c', script, docxPath], { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
}

/** paragraphs 배열을 실제 .docx 로 Packer 변환한 뒤 document.xml 텍스트를 반환한다. */
async function renderXml(paragraphs, name) {
  const doc = new Document({ sections: [{ properties: {}, children: paragraphs }] });
  const buf = await Packer.toBuffer(doc);
  const outPath = join(WORK, `${name}.docx`);
  writeFileSync(outPath, buf);
  return { xml: readDocumentXml(outPath), outPath };
}

// ── XML 문단/run 단위 조회 헬퍼(완전한 XML 파서는 아니고, <w:p>/<w:r> 시작 태그 기준 분리) ──
const paragraphBlocks = (xml) => xml.split(/(?=<w:p[ >])/).filter((b) => b.startsWith('<w:p'));
const blockContaining = (xml, text) => paragraphBlocks(xml).find((b) => b.includes(text));
const runBlocks = (block) => block.split(/(?=<w:r[ >])/).filter((b) => b.startsWith('<w:r'));
const runContaining = (block, text) => runBlocks(block).find((r) => r.includes(text));
const isBoldRun = (run) => /<w:b\s*\/>|<w:b\s+[^>]*>/.test(run);

const FIXTURE_MD = [
  '# 제목1',
  '## 제목2',
  '### 제목3',
  '#### 제목4레벨',
  '',
  '일반문단 **굵은부분** 나머지부분.',
  '',
  '인라인 `코드조각` 확인문단.',
  '',
  '[깃허브](https://example.com/repo) 링크문단.',
  '',
  '*기울임단어* 와 _다른기울임_ 그리고 snake_case_id 문단.',
  '',
  '| 헤더1 | 헤더2 |',
  '| --- | --- |',
  '| 값1 | 값2 |',
  '',
  '- 불릿항목',
  '',
  '1. 첫째항목',
  '2. 둘째항목',
  '',
  '```',
  '펜스안텍스트유지',
  '```',
].join('\n') + '\n';

try {
  const paragraphs = toParagraphs(FIXTURE_MD);
  check('toParagraphs 는 순수 함수로 문단 배열을 반환한다', () => {
    assert.ok(Array.isArray(paragraphs));
    assert.ok(paragraphs.length >= 10, `문단 수가 너무 적음: ${paragraphs.length}`);
  });

  const { xml, outPath } = await renderXml(paragraphs, 'fixture');

  check('산출 .docx 파일이 실제로 생성됨', () => {
    assert.ok(existsSync(outPath));
    assert.ok(statSync(outPath).size > 0);
  });

  // ── (f) 표·이미지·텍스트박스 없음 ──
  check('문서 전체에 표 태그(<w:tbl)가 없음', () => {
    assert.ok(!xml.includes('<w:tbl'), '표 태그가 남아있음');
  });
  check('문서 전체에 이미지·텍스트박스 태그가 없음', () => {
    assert.ok(!xml.includes('<w:drawing'), '이미지(drawing) 태그가 남아있음');
    assert.ok(!xml.includes('<w:pict'), '텍스트박스/그림(pict) 태그가 남아있음');
  });

  // ── (e) 제목 레벨 ──
  check('# → Heading1', () => {
    const b = blockContaining(xml, '제목1');
    assert.ok(b, '제목1 문단을 찾지 못함');
    assert.ok(b.includes('Heading1'), 'Heading1 스타일이 아님');
  });
  check('## → Heading2', () => {
    const b = blockContaining(xml, '제목2');
    assert.ok(b, '제목2 문단을 찾지 못함');
    assert.ok(b.includes('Heading2'), 'Heading2 스타일이 아님');
  });
  check('### → Heading3', () => {
    const b = blockContaining(xml, '제목3');
    assert.ok(b, '제목3 문단을 찾지 못함');
    assert.ok(b.includes('Heading3'), 'Heading3 스타일이 아님');
  });
  check('#### (4단계 이상) → Heading3 로 수렴', () => {
    const b = blockContaining(xml, '제목4레벨');
    assert.ok(b, '제목4레벨 문단을 찾지 못함');
    assert.ok(b.includes('Heading3'), '#### 가 Heading3 로 처리되지 않음');
    assert.ok(!b.includes('Heading4'), 'Heading4 스타일은 정의되어 있지 않아야 함');
  });

  // ── 굵게 분리 ──
  check('**굵게** 는 별도 굵은 run 으로 분리되고 인접 텍스트는 굵지 않음', () => {
    const p = blockContaining(xml, '일반문단');
    assert.ok(p, '굵게 테스트 문단을 찾지 못함');
    const boldRun = runContaining(p, '굵은부분');
    assert.ok(boldRun, '굵은부분 run 을 찾지 못함');
    assert.ok(isBoldRun(boldRun), '굵은부분 run 이 bold 로 렌더링되지 않음');
    const plainRun = runContaining(p, '나머지부분');
    assert.ok(plainRun, '나머지부분 run 을 찾지 못함');
    assert.ok(!isBoldRun(plainRun), '나머지부분 run 이 의도치 않게 bold 임');
  });

  // ── (b) 코드 백틱 제거 ──
  check('인라인 `코드` 는 백틱이 제거되고 bold 로 렌더링되지 않음', () => {
    const p = blockContaining(xml, '코드조각');
    assert.ok(p, '코드조각 문단을 찾지 못함');
    assert.ok(!p.includes('`'), '백틱이 남아있음');
    const run = runContaining(p, '코드조각');
    assert.ok(run && !isBoldRun(run), '코드 run 이 의도치 않게 bold 임');
  });

  // ── (b) 링크 변환 ──
  check('[텍스트](url) → "텍스트 (url)" 로 치환', () => {
    const p = blockContaining(xml, '깃허브');
    assert.ok(p, '링크 테스트 문단을 찾지 못함');
    assert.ok(p.includes('깃허브 (https://example.com/repo)'), '링크 변환 형식이 다름');
    assert.ok(!p.includes('](https://example.com/repo)'), '마크다운 링크 문법이 남아있음');
  });

  // ── (b) 기울임 기호 제거 + 식별자 보존 ──
  check('*기울임*/_기울임_ 기호는 제거되고 snake_case_id 는 손상되지 않음', () => {
    const p = blockContaining(xml, 'snake_case_id');
    assert.ok(p, '기울임 테스트 문단을 찾지 못함');
    assert.ok(p.includes('기울임단어'), '별표 기울임 텍스트가 없음');
    assert.ok(!p.includes('*기울임단어*'), '별표 기호가 남아있음');
    assert.ok(p.includes('다른기울임'), '밑줄 기울임 텍스트가 없음');
    assert.ok(!p.includes('_다른기울임_'), '밑줄 기호가 남아있음');
    assert.ok(p.includes('snake_case_id'), 'snake_case_id 내부 밑줄이 기울임으로 오인되어 손상됨');
  });

  // ── (d) 표 → 문단, 헤더 행 굵게 ──
  check('표 헤더 행 → 굵은 문단("헤더1 · 헤더2")', () => {
    const p = blockContaining(xml, '헤더1');
    assert.ok(p, '표 헤더 문단을 찾지 못함');
    assert.ok(p.includes('헤더1 · 헤더2'), '헤더 셀 결합 형식이 다름');
    const run = runContaining(p, '헤더1');
    assert.ok(run && isBoldRun(run), '표 헤더 행이 bold 로 렌더링되지 않음');
  });
  check('표 본문 행 → 일반 문단("값1 · 값2"), 굵지 않음', () => {
    const p = blockContaining(xml, '값1');
    assert.ok(p, '표 본문 문단을 찾지 못함');
    assert.ok(p.includes('값1 · 값2'), '본문 셀 결합 형식이 다름');
    const run = runContaining(p, '값1');
    assert.ok(run && !isBoldRun(run), '표 본문 행이 의도치 않게 bold 임');
  });

  // ── 펜스 블록 ──
  check('펜스 코드블록 내용은 그대로 별도 문단으로 유지됨', () => {
    assert.ok(xml.includes('펜스안텍스트유지'), '펜스 블록 텍스트가 없음');
  });

  // ── (c) 번호 목록 텍스트 유지 ──
  check('번호 목록은 원문 번호를 텍스트로 유지("1. 첫째항목")', () => {
    const p = blockContaining(xml, '첫째항목');
    assert.ok(p, '번호 목록 문단을 찾지 못함');
    const run = runContaining(p, '첫째항목');
    assert.ok(run && run.includes('1. 첫째항목'), '번호가 텍스트로 유지되지 않음');
  });

  // ── inlineRuns 직접 호출 — run 분리 개수(표면적 구조) 확인 ──
  check('inlineRuns("") 는 빈 run 하나를 반환', () => {
    assert.equal(inlineRuns('').length, 1);
  });
  check('inlineRuns 는 **굵게** 앞뒤 텍스트를 run 3개로 분리', () => {
    assert.equal(inlineRuns('앞**굵음**뒤').length, 3);
  });
  check('inlineRuns 는 전체가 굵게면 run 1개', () => {
    assert.equal(inlineRuns('**전부굵음**').length, 1);
  });

  // ── CLI 엔드투엔드(import.meta.url 가드 포함 실제 실행 경로) ──
  const cliMd = join(WORK, 'cli-input.md');
  const cliOut = join(WORK, 'cli-output.docx');
  writeFileSync(cliMd, '# CLI 제목\n\n**CLI굵게** 확인 문단.\n');

  const res = spawnSync(process.execPath, [MD2DOCX, cliMd, cliOut], { encoding: 'utf8' });
  check('CLI 직접 실행 → exit 0, stdout 은 산출 경로 한 줄', () => {
    assert.equal(res.status, 0, `stderr: ${res.stderr}`);
    assert.equal(res.stdout.trim(), cliOut);
  });
  check('CLI 산출물도 표 태그 없음 + 기대 텍스트 포함', () => {
    assert.ok(existsSync(cliOut));
    const cliXml = readDocumentXml(cliOut);
    assert.ok(!cliXml.includes('<w:tbl'), 'CLI 산출물에 표 태그가 있음');
    assert.ok(cliXml.includes('CLI굵게'), 'CLI 산출물에 기대 텍스트가 없음');
  });

  check('CLI 인자 부족 → exit 1', () => {
    const r = spawnSync(process.execPath, [MD2DOCX, cliMd], { encoding: 'utf8' });
    assert.equal(r.status, 1);
  });
  check('CLI 입력 파일 없음 → exit 1', () => {
    const r = spawnSync(process.execPath, [MD2DOCX, join(WORK, 'nope.md'), cliOut], { encoding: 'utf8' });
    assert.equal(r.status, 1);
  });
} finally {
  rmSync(WORK, { recursive: true, force: true });
}

console.log(`\n[${process.exitCode ? 'FAIL' : 'PASS'}] test-md2docx — ${pass} passed`);
