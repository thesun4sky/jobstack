#!/usr/bin/env node
/**
 * md2docx.mjs — pandoc 없이 마크다운을 ATS-safe .docx 로 변환 (U-13, jobstack-export 폴백).
 *
 * 규칙(templates/export/ats-reference.docx 와 같은 방향): 단일 컬럼, 표준 제목 스타일
 * (Heading 1~3 — #### 이상은 모두 Heading 3 로 수렴), 본문 11pt, 표·이미지·텍스트박스 없음.
 * 마크다운 표는 행마다 한 문단("셀 · 셀")으로 풀어 쓰고, 헤더 행(구분선 바로 앞 행)은 굵게 표시한다.
 *
 * 지원 문법: #~###### 제목 · 문단 · - / * 불릿 · 1. 번호 목록(번호를 텍스트로 유지, 예: "1. 첫째") ·
 * **굵게**(유지) · `코드`(백틱 제거, 서식 없음) · [텍스트](url) → "텍스트 (url)" ·
 * *기울임* · _기울임_ (기호만 제거 — ATS-safe 서식 없는 텍스트) · 수평선(무시) · 인용(> 는 일반 문단) ·
 * 표(행 → 문단). 기울임 기호 제거는 바깥쪽에 영문/숫자가 붙어 있으면 건드리지 않는다 —
 * SCRIPT_DIR·snake_case_id 같은 식별자가 밑줄 때문에 잘려나가지 않게 하기 위함이다.
 *
 * 이 파일을 직접 실행하면(node md2docx.mjs ...) CLI 로 동작한다. import 될 때는(단위 테스트 등)
 * toParagraphs/inlineRuns 만 순수 함수로 노출하고 CLI 로직(main)은 실행하지 않는다 — docx
 * 패키지 부재는 main 실행 시에만 exit 3 로 처리하며, 모듈 import 자체는 throw 하지 않는다.
 *
 * 사용법: node md2docx.mjs <입력.md> <출력.docx> [--font "Noto Sans KR"]
 * 종료 코드: 0 성공 · 1 입력 오류 · 3 변환 실패(docx 패키지 부재 포함)
 */
import { readFileSync, writeFileSync, renameSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// docx 부재는 여기서 exit 하지 않는다 — 모듈 import 자체는 항상 성공해야 테스트가
// toParagraphs/inlineRuns 를 안전하게 가져올 수 있다(exit 3 판단은 main 에서만 한다).
let docx;
try {
  docx = await import('docx');
} catch {
  docx = null;
}
const { Document, Packer, Paragraph, TextRun, HeadingLevel } = docx ?? {};

const FONT_DEFAULT = 'Noto Sans KR';

/**
 * *기울임* · _기울임_ 의 기호만 제거(서식 없는 텍스트 유지 — ATS-safe).
 * 바깥쪽에 영문/숫자가 붙어 있으면(예: snake_case_id, SCRIPT_DIR) 기호로 보지 않고 그대로 둔다
 * — 그렇지 않으면 밑줄이 든 식별자가 기울임 기호로 오인되어 텍스트가 손상된다.
 */
function stripItalics(s) {
  return s
    .replace(/(?<!\w)\*([^*]+?)\*(?!\w)/g, '$1')
    .replace(/(?<!\w)_([^_]+?)_(?!\w)/g, '$1');
}

/** [텍스트](url) → "텍스트 (url)" */
function convertLinks(s) {
  return s.replace(/\[([^\]]*)\]\(([^)]+)\)/g, '$1 ($2)');
}

/** 제목 텍스트를 서식 기호 없는 문자열로 평탄화(제목 TextRun 자체가 이미 굵게 처리됨). */
function sanitizeHeadingText(s) {
  const noLinks = convertLinks(s);
  const noCode = noLinks.replace(/`([^`]+)`/g, '$1');
  const noBold = noCode.replace(/\*\*([^*]+)\*\*/g, '$1');
  return stripItalics(noBold);
}

/**
 * 인라인 마크다운 → TextRun 배열.
 * 처리 순서: 링크 치환 → **굵게** · `코드` 토큰화(교차 매칭) → 나머지 구간은 기울임 기호만 제거.
 */
export function inlineRuns(text, font = FONT_DEFAULT) {
  const withLinks = convertLinks(text);
  const runs = [];
  const re = /\*\*([^*]+)\*\*|`([^`]+)`/g;
  let last = 0;
  let m;
  while ((m = re.exec(withLinks)) !== null) {
    if (m.index > last) {
      const plain = stripItalics(withLinks.slice(last, m.index));
      if (plain) runs.push(new TextRun({ text: plain, font, size: 22 }));
    }
    if (m[1] !== undefined) {
      // 굵게: 내부에 기울임 기호가 섞여 있을 수 있으니 동일하게 제거
      runs.push(new TextRun({ text: stripItalics(m[1]), bold: true, font, size: 22 }));
    } else {
      // 코드: 백틱만 제거, 서식 없음(굵게 처리 안 함)
      runs.push(new TextRun({ text: m[2], font, size: 22 }));
    }
    last = m.index + m[0].length;
  }
  if (last < withLinks.length) {
    const plain = stripItalics(withLinks.slice(last));
    if (plain) runs.push(new TextRun({ text: plain, font, size: 22 }));
  }
  if (runs.length === 0) runs.push(new TextRun({ text: '', font, size: 22 }));
  return runs;
}

/** 마크다운 → docx Paragraph 배열 (순수 함수, 테스트 가능) */
export function toParagraphs(markdown, font = FONT_DEFAULT) {
  const out = [];
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  let para = [];
  let inFence = false;
  const flush = () => {
    if (para.length) {
      out.push(new Paragraph({ children: inlineRuns(para.join(' '), font), spacing: { after: 120 } }));
      para = [];
    }
  };
  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const line = raw.replace(/\s+$/, '');
    if (/^```/.test(line)) { flush(); inFence = !inFence; continue; }
    if (inFence) { out.push(new Paragraph({ children: [new TextRun({ text: line, font, size: 20 })] })); continue; }
    if (!line.trim()) { flush(); continue; }
    // #~###### 제목 — 4단계 이상(####+)은 전부 Heading 3 로 수렴(레퍼런스 문서에 그 이상 스타일 없음)
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) {
      flush();
      const level = [HeadingLevel.HEADING_1, HeadingLevel.HEADING_2, HeadingLevel.HEADING_3][Math.min(h[1].length, 3) - 1];
      out.push(new Paragraph({ heading: level, children: [new TextRun({ text: sanitizeHeadingText(h[2]), font, bold: true })] }));
      continue;
    }
    if (/^(-{3,}|\*{3,}|_{3,})$/.test(line.trim())) { flush(); continue; }
    if (/^\|/.test(line.trim())) {
      flush();
      const trimmed = line.trim();
      if (/^\|\s*:?-{2,}/.test(trimmed)) continue; // 구분선
      const cells = trimmed.replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim()).filter(Boolean);
      // 구분선 바로 앞 행 = 헤더 행 → 굵게. 표 전체를 문단으로 풀어 쓰므로 lookahead 만으로 충분히 판별된다.
      const nextTrimmed = (lines[i + 1] || '').trim();
      const isHeaderRow = /^\|\s*:?-{2,}/.test(nextTrimmed);
      if (isHeaderRow) {
        out.push(new Paragraph({ children: [new TextRun({ text: sanitizeHeadingText(cells.join(' · ')), bold: true, font, size: 22 })], spacing: { after: 60 } }));
      } else {
        out.push(new Paragraph({ children: inlineRuns(cells.join(' · '), font), spacing: { after: 60 } }));
      }
      continue;
    }
    const bullet = /^\s*[-*]\s+(.*)$/.exec(line);
    if (bullet) { flush(); out.push(new Paragraph({ children: inlineRuns(bullet[1], font), bullet: { level: 0 }, spacing: { after: 60 } })); continue; }
    // 번호 목록: numbering 정의를 새로 만드는 대신 원문 번호를 텍스트로 유지한다(예: "1. 첫째").
    const num = /^\s*(\d+[.)])\s+(.*)$/.exec(line);
    if (num) { flush(); out.push(new Paragraph({ children: inlineRuns(`${num[1]} ${num[2]}`, font), spacing: { after: 60 } })); continue; }
    para.push(line.replace(/^>\s?/, ''));
  }
  flush();
  return out;
}

async function main() {
  if (!docx) {
    process.stderr.write('md2docx: `docx` 패키지가 없습니다 — bin/ 에서 `npm install` 후 재시도하세요\n');
    process.exit(3);
  }

  const args = process.argv.slice(2);
  const fontIdx = args.indexOf('--font');
  const FONT = fontIdx >= 0 ? args.splice(fontIdx, 2)[1] : FONT_DEFAULT;
  const [input, output] = args;
  if (!input || !output) {
    process.stderr.write('Usage: md2docx.mjs <입력.md> <출력.docx> [--font "Noto Sans KR"]\n');
    process.exit(1);
  }

  let md;
  try {
    md = readFileSync(input, 'utf8');
  } catch (e) {
    process.stderr.write(`md2docx: 입력을 읽을 수 없습니다: ${e.message}\n`);
    process.exit(1);
  }

  const doc = new Document({
    creator: 'jobstack',
    styles: {
      default: { document: { run: { font: FONT, size: 22 } } },
      paragraphStyles: [
        { id: 'Heading1', name: 'Heading 1', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 32, bold: true, font: FONT }, paragraph: { spacing: { before: 240, after: 120 } } },
        { id: 'Heading2', name: 'Heading 2', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 26, bold: true, font: FONT }, paragraph: { spacing: { before: 200, after: 100 } } },
        { id: 'Heading3', name: 'Heading 3', basedOn: 'Normal', next: 'Normal', quickFormat: true, run: { size: 24, bold: true, font: FONT }, paragraph: { spacing: { before: 160, after: 80 } } },
      ],
    },
    sections: [{ properties: {}, children: toParagraphs(md, FONT) }],
  });

  try {
    const buf = await Packer.toBuffer(doc);
    // 임시 파일에 쓴 뒤 rename 으로 교체 — writeFileSync(output, buf) 직접 쓰기는 중간에
    // 프로세스가 죽으면 output 경로에 반쯤 쓰인 손상된 .docx 가 남는다(리뷰 반영).
    // rename 은 같은 파일시스템 안에서 원자적이라 output 은 항상 완성본이거나 이전 버전이다.
    const tmpPath = `${output}.tmp.${process.pid}`;
    writeFileSync(tmpPath, buf);
    renameSync(tmpPath, output);
    process.stdout.write(output + '\n');
  } catch (e) {
    process.stderr.write(`md2docx: 변환 실패: ${e.message}\n`);
    process.exit(3);
  }
}

// CLI 로 직접 실행됐을 때만 main 을 돈다 — import 시(테스트 등)에는 함수 정의만 노출한다.
let isMain = false;
try {
  isMain = import.meta.url === pathToFileURL(process.argv[1]).href;
} catch {
  isMain = false;
}
if (isMain) {
  await main();
}
