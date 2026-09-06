#!/usr/bin/env node
/**
 * jobstack-defense-map.mjs — 문장↔꼬리질문 맵(defense-map)의 결정적 조작 (U-09).
 *
 * cover-letter/review/career-history 가 산출한 미끼 인벤토리를 스키마 검증해 저장하고,
 * mock-interview(소비)·retro(방어 준비율 집계)가 읽기 쉬운 형태로 압축해 내보낸다.
 * 데이터 계약의 단일 소스는 docs/defense-map-schema.md — 이 스크립트는 그 계약의 구현이다.
 *
 * 사용법:
 *   jobstack-defense-map add --company C --position P
 *                             --source-skill cover-letter|review|career-history
 *                             --document-ref D
 *                             (--entries-json '[...]' | --from <yaml 파일>)
 *   jobstack-defense-map list [--company C] [--json]
 *   jobstack-defense-map show [--company C] [--file F] [--max-chars 1500] [--all]
 *   jobstack-defense-map set-status (<file> | --company C) <entry-id> <ready|weak|unprepared>
 *   jobstack-defense-map stats [--company C] [--json]
 *   jobstack-defense-map validate <file>
 *
 * 환경: JOBSTACK_STATE_DIR (기본 ~/.jobstack) → defense-maps/<회사명>_<직무>_<YYYYMMDD>.yaml
 * 종료 코드: 0 정상 · 1 오류 · 3 의존성 없음(yaml 패키지 미설치)
 *
 * 스키마 정의: docs/defense-map-schema.md · 예시: templates/defense-map-example.yaml
 */

import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, statSync, writeFileSync } from 'node:fs';
import { withLock, LOCK_TIMEOUT_CODE } from './lib/lockfile.mjs';
import { dirname, join, resolve, sep } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';

let YAML;
try {
  YAML = await import('yaml');
} catch {
  process.stderr.write('jobstack-defense-map: `yaml` 패키지가 없습니다 — bin/ 에서 `npm install` 후 재시도하세요\n');
  process.exit(3);
}
const { parseDocument, parse, stringify } = YAML;

const STATE_DIR = process.env.JOBSTACK_STATE_DIR || join(homedir(), '.jobstack');
const DM_DIR = join(STATE_DIR, 'defense-maps');

const SOURCE_SKILLS = ['cover-letter', 'review', 'career-history'];
const BAIT_TYPES = ['수치', '기술선택', '역할범위', '성과', '갈등·판단'];
const DIFFICULTIES = ['mild', 'normal', 'hard'];
const DEFENSE_STATUSES = ['ready', 'weak', 'unprepared'];
// docs/defense-map-schema.md 의 enum 주석과 동일한 한글 라벨 — 사람이 보는 출력(예: set-status 확인
// 메시지)에는 이 라벨을 쓰고, mock-interview 가 파싱하는 show 압축 라인(계약상 고정 포맷)만 예외로 원문 키를 쓴다.
const DEFENSE_STATUS_LABEL = { ready: '방어 준비됨', weak: '답변 불충분', unprepared: '미준비' };
const STATUS_RANK = { unprepared: 0, weak: 1, ready: 2 };
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
const ENTRY_ID_RE = /^dm-\d{3,}$/;

// ── KST 날짜 헬퍼 (가드레일 §4) ────────────────────────────────────────────────
function kstNow() {
  return new Date(Date.now() + 9 * 3600 * 1000);
}
function pad2(n) {
  return String(n).padStart(2, '0');
}
function kstDateCompact(d = kstNow()) {
  return `${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}`;
}
function kstIsoOffset(d = kstNow()) {
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`
    + `T${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}:${pad2(d.getUTCSeconds())}+09:00`;
}

function die(msg, code = 1) {
  process.stderr.write(`jobstack-defense-map: ${msg}\n`);
  process.exit(code);
}

function usage() {
  return `사용법:
  jobstack-defense-map add --company C --position P
                            --source-skill cover-letter|review|career-history
                            --document-ref D
                            (--entries-json '[...]' | --from <yaml 파일>)
  jobstack-defense-map list [--company C] [--json]
  jobstack-defense-map show [--company C] [--file F] [--max-chars 1500] [--all]
  jobstack-defense-map set-status (<file> | --company C) <entry-id> <ready|weak|unprepared>
  jobstack-defense-map stats [--company C] [--json]
  jobstack-defense-map validate <file>

환경: JOBSTACK_STATE_DIR (기본 ~/.jobstack) → defense-maps/<회사명>_<직무>_<YYYYMMDD>.yaml
종료 코드: 0 정상 · 1 오류 · 3 의존성 없음(yaml 패키지 미설치)
스키마: docs/defense-map-schema.md
`;
}

// ── 인자 파싱 ───────────────────────────────────────────────────────────────
function parseArgs(argv) {
  const flags = {};
  const positionals = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith('--')) {
        flags[key] = next;
        i++;
      } else {
        flags[key] = true;
      }
    } else {
      positionals.push(a);
    }
  }
  return { flags, positionals };
}

// ── 원자적 쓰기 — 임시 파일 + rename. defense-maps/ 디렉토리 밖에는 쓰지 않는다 ──────
function assertInsideDmDir(filePath) {
  const resolved = resolve(filePath);
  const dirWithSep = resolve(DM_DIR) + sep;
  if (!resolved.startsWith(dirWithSep)) {
    die(`상태 디렉토리 밖에는 쓸 수 없습니다: ${filePath} (허용 범위: ${DM_DIR})`);
  }
  return resolved;
}

function atomicWrite(filePath, content) {
  const dir = dirname(filePath);
  mkdirSync(dir, { recursive: true, mode: 0o700 }); // 방어맵도 개인 정보 — 디렉토리 0700·파일 0600(PR #18 재리뷰)
  const tmp = join(dir, `.${Date.now()}.${randomBytes(4).toString('hex')}.tmp`);
  writeFileSync(tmp, content, { encoding: 'utf8', mode: 0o600 });
  renameSync(tmp, filePath);
}

function readRaw(filePath) {
  if (!existsSync(filePath)) return null;
  return readFileSync(filePath, 'utf8');
}

function normalizeSlug(s) {
  return String(s).trim().replace(/[\s/\\]+/g, '-');
}

function uniqueFilePath(dir, base) {
  let candidate = join(dir, `${base}.yaml`);
  if (!existsSync(candidate)) return candidate;
  let n = 2;
  do {
    candidate = join(dir, `${base}_${n}.yaml`);
    n++;
  } while (existsSync(candidate));
  return candidate;
}

// ── 목록/로드 ───────────────────────────────────────────────────────────────
function listFiles() {
  if (!existsSync(DM_DIR)) return [];
  return readdirSync(DM_DIR)
    .filter((f) => f.endsWith('.yaml'))
    .map((f) => join(DM_DIR, f));
}

function loadDoc(filePath) {
  const raw = readRaw(filePath);
  if (raw === null) return null;
  try {
    return parse(raw);
  } catch {
    return null;
  }
}

// 느슨 매칭: 공백·하이픈 제거 + 소문자 부분일치 (저장 시 공백->하이픈 정규화를 하므로
// 하이픈도 함께 제거해야 사용자가 원래 표기(공백 포함)로 검색해도 걸린다)
function looseNorm(s) {
  return String(s ?? '').replace(/[\s-]+/g, '').toLowerCase();
}
function looseMatch(company, query) {
  return looseNorm(company).includes(looseNorm(query));
}

function readyRatio(doc) {
  const entries = Array.isArray(doc?.entries) ? doc.entries : [];
  const ready = entries.filter((e) => e?.defense_status === 'ready').length;
  return { ready, total: entries.length };
}

function fmtRatio({ ready, total }) {
  const pct = total > 0 ? Math.round((ready / total) * 100) : 0;
  return `${ready}/${total} (${pct}%)`;
}

function docRows(companyFilter) {
  const rows = [];
  for (const f of listFiles()) {
    const doc = loadDoc(f);
    if (!doc) continue;
    if (companyFilter && !looseMatch(doc.company, companyFilter)) continue;
    let mtimeMs = 0;
    try {
      mtimeMs = statSync(f).mtimeMs;
    } catch { /* 조회 실패 시 tie-break 만 0 처리, 목록 자체는 계속 진행 */ }
    rows.push({ file: f, doc, mtimeMs });
  }
  // created_at(초 단위) 우선 내림차순, 같은 초에 여러 파일이 생기면 실제 쓰기 시각(mtime)으로 tie-break —
  // 파일시스템 readdir 순서에 최신순 판정을 맡기지 않는다.
  rows.sort((a, b) => {
    const byCreated = String(b.doc.created_at ?? '').localeCompare(String(a.doc.created_at ?? ''));
    return byCreated !== 0 ? byCreated : b.mtimeMs - a.mtimeMs;
  });
  return rows;
}

// ── 스키마 검증 (add 저장 전 / validate 명령이 공유) ─────────────────────────────
// docs/defense-map-schema.md 의 구현. errors 가 있으면 저장 불가, warnings 는 저장은 진행하되 알림만.
function validateDoc(doc, label) {
  const errors = [];
  const warnings = [];
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) {
    errors.push(`${label}: 최상위가 객체가 아닙니다`);
    return { errors, warnings };
  }
  if (doc.schema_version !== 1) errors.push(`${label}: schema_version 은 1 이어야 합니다`);
  if (!SOURCE_SKILLS.includes(doc.source_skill)) {
    errors.push(`${label}: source_skill 값이 올바르지 않습니다 (${doc.source_skill}) — 허용: ${SOURCE_SKILLS.join('|')}`);
  }
  if (typeof doc.created_at !== 'string' || !ISO_RE.test(doc.created_at)) {
    errors.push(`${label}: created_at 형식 오류 (ISO 8601 아님)`);
  }
  if (typeof doc.company !== 'string' || !doc.company) errors.push(`${label}: company 없음`);
  if (typeof doc.position !== 'string' || !doc.position) errors.push(`${label}: position 없음`);
  if (typeof doc.document_ref !== 'string' || !doc.document_ref) errors.push(`${label}: document_ref 없음`);

  const entries = Array.isArray(doc.entries) ? doc.entries : null;
  if (!entries) {
    errors.push(`${label}: entries 가 리스트가 아닙니다`);
    return { errors, warnings };
  }
  if (entries.length < 1) {
    errors.push(`${label}: entries 는 1개 이상이어야 합니다`);
  } else if (doc.source_skill === 'cover-letter' && entries.length < 5) {
    warnings.push(`${label}: cover-letter 는 미끼 5개 배치 원칙 권장 (현재 ${entries.length}개)`);
  }

  const seen = new Set();
  entries.forEach((e, i) => {
    const hasId = e && typeof e === 'object' && typeof e.id === 'string' && e.id;
    const eid = hasId ? e.id : `entries[${i}]`;
    if (!e || typeof e !== 'object' || Array.isArray(e)) {
      errors.push(`${eid}: entry 가 객체가 아닙니다`);
      return;
    }
    if (!hasId) {
      errors.push(`${eid}: id 없음`);
    } else {
      if (!ENTRY_ID_RE.test(e.id)) errors.push(`${eid}: id 형식 오류 (dm-NNN 아님)`);
      if (seen.has(e.id)) errors.push(`${eid}: id 중복`);
      seen.add(e.id);
    }
    if (typeof e.sentence !== 'string' || !e.sentence) errors.push(`${eid}: sentence 없음`);
    if (typeof e.location !== 'string' || !e.location) errors.push(`${eid}: location 없음`);
    if (!BAIT_TYPES.includes(e.bait_type)) {
      errors.push(`${eid}: bait_type 값이 올바르지 않습니다 (${e.bait_type}) — 허용: ${BAIT_TYPES.join('|')}`);
    }
    if (!Array.isArray(e.questions) || e.questions.length < 2) {
      errors.push(`${eid}: questions 는 2개 이상이어야 합니다`);
    } else {
      e.questions.forEach((q, qi) => {
        if (!q || typeof q !== 'object' || Array.isArray(q)) {
          errors.push(`${eid}: questions[${qi}] 형식 오류`);
          return;
        }
        if (typeof q.q !== 'string' || !q.q) errors.push(`${eid}: questions[${qi}].q 없음`);
        if (typeof q.intent !== 'string' || !q.intent) errors.push(`${eid}: questions[${qi}].intent 없음`);
        if (!DIFFICULTIES.includes(q.difficulty)) {
          errors.push(`${eid}: questions[${qi}].difficulty 값이 올바르지 않습니다 (${q.difficulty})`);
        }
      });
    }
    if (e.answer_hint !== null && e.answer_hint !== undefined && typeof e.answer_hint !== 'string') {
      errors.push(`${eid}: answer_hint 는 문자열 또는 null 이어야 합니다`);
    }
    if (!DEFENSE_STATUSES.includes(e.defense_status)) {
      errors.push(`${eid}: defense_status 값이 올바르지 않습니다 (${e.defense_status}) — 허용: ${DEFENSE_STATUSES.join('|')}`);
    }
  });

  return { errors, warnings };
}

// entries 의 id 없는 항목에 dm-001 부터 순서대로 부여 (이미 쓰인 번호는 건너뜀)
function assignEntryIds(entries) {
  const used = new Set();
  for (const e of entries) {
    if (e && typeof e.id === 'string' && ENTRY_ID_RE.test(e.id)) used.add(e.id);
  }
  let n = 1;
  const nextFree = () => {
    let id;
    do {
      id = `dm-${String(n).padStart(3, '0')}`;
      n++;
    } while (used.has(id));
    used.add(id);
    return id;
  };
  for (const e of entries) {
    if (!e || typeof e.id !== 'string' || !e.id) e.id = nextFree();
  }
}

// 필드 순서를 스키마 표 순서로 고정해 출력을 일관되게 한다 (입력 JSON 의 키 순서에 의존하지 않음)
function canonicalEntry(e) {
  return {
    id: e.id,
    sentence: e.sentence,
    location: e.location,
    bait_type: e.bait_type,
    questions: Array.isArray(e.questions)
      ? e.questions.map((q) => ({ q: q?.q, intent: q?.intent, difficulty: q?.difficulty }))
      : e.questions,
    answer_hint: e.answer_hint === undefined ? null : e.answer_hint,
    defense_status: e.defense_status,
  };
}

// ── add ─────────────────────────────────────────────────────────────────────
function cmdAdd(flags) {
  const company = typeof flags.company === 'string' ? flags.company : null;
  const position = typeof flags.position === 'string' ? flags.position : null;
  const sourceSkill = typeof flags['source-skill'] === 'string' ? flags['source-skill'] : null;
  const documentRef = typeof flags['document-ref'] === 'string' ? flags['document-ref'] : null;

  if (!company) die('--company 를 지정하세요');
  if (!position) die('--position 를 지정하세요');
  if (!SOURCE_SKILLS.includes(sourceSkill)) die(`--source-skill 은 ${SOURCE_SKILLS.join('|')} 중 하나여야 합니다`);
  if (!documentRef) die('--document-ref 를 지정하세요');

  let entries;
  if (typeof flags['entries-json'] === 'string') {
    try {
      entries = JSON.parse(flags['entries-json']);
    } catch (e) {
      die(`--entries-json 파싱 실패: ${e.message}`);
    }
  } else if (typeof flags.from === 'string') {
    const raw = readRaw(resolve(flags.from));
    if (raw === null) die(`--from 파일을 읽을 수 없습니다: ${flags.from}`);
    let loaded;
    try {
      loaded = parse(raw);
    } catch (e) {
      die(`--from YAML 파싱 실패: ${e.message}`);
    }
    entries = Array.isArray(loaded) ? loaded : loaded?.entries;
  } else {
    die('--entries-json 또는 --from 중 하나를 지정하세요');
  }
  if (!Array.isArray(entries)) die('entries 를 배열로 확인할 수 없습니다 (--entries-json 배열 또는 --from 파일의 최상위/entries 배열)');

  entries = entries.map((e) => ({ ...e }));
  assignEntryIds(entries);
  for (const e of entries) {
    if (e.defense_status === undefined || e.defense_status === null || e.defense_status === '') {
      e.defense_status = 'unprepared';
    }
    if (e.answer_hint === undefined) e.answer_hint = null;
  }
  entries = entries.map(canonicalEntry);

  const companyNorm = normalizeSlug(company);
  const positionNorm = normalizeSlug(position);

  const doc = {
    schema_version: 1,
    source_skill: sourceSkill,
    created_at: kstIsoOffset(),
    company: companyNorm,
    position: positionNorm,
    document_ref: documentRef,
    entries,
  };

  const { errors, warnings } = validateDoc(doc, '입력');
  if (errors.length) {
    for (const e of errors) process.stderr.write(`[FAIL] ${e}\n`);
    process.exit(1);
  }
  for (const w of warnings) process.stderr.write(`[경고] ${w}\n`);

  const dateCompact = kstDateCompact();
  const baseName = `${companyNorm}_${positionNorm}_${dateCompact}`;
  const filePath = assertInsideDmDir(uniqueFilePath(DM_DIR, baseName));
  atomicWrite(filePath, stringify(doc));
  process.stdout.write(`${filePath}\n`);
}

// ── list ────────────────────────────────────────────────────────────────────
function cmdList(flags) {
  const rows = docRows(typeof flags.company === 'string' ? flags.company : null);

  if (flags.json) {
    const out = rows.map(({ file, doc }) => {
      const r = readyRatio(doc);
      return {
        file,
        company: doc.company,
        position: doc.position,
        created_at: doc.created_at,
        entries: r.total,
        ready: r.ready,
        ready_ratio: fmtRatio(r),
      };
    });
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
    return;
  }

  if (!rows.length) {
    console.log('defense-map 파일이 없습니다');
    return;
  }
  const bar = '━'.repeat(60);
  console.log('defense-map 목록 (최신순)');
  console.log(bar);
  for (const { file, doc } of rows) {
    const r = readyRatio(doc);
    const date = String(doc.created_at ?? '').slice(0, 10);
    console.log(`${doc.company} · ${doc.position} · ${date} · entry ${r.total}개 · 준비율 ${fmtRatio(r)}`);
    console.log(`  ${file}`);
  }
  console.log(bar);
}

// ── show (mock-interview 소비용) ───────────────────────────────────────────
function resolveShowFile(flags) {
  if (typeof flags.file === 'string') {
    const direct = resolve(flags.file);
    if (existsSync(direct)) return direct;
    const inDir = join(DM_DIR, flags.file);
    if (existsSync(inDir)) return inDir;
    return null;
  }
  const rows = docRows(typeof flags.company === 'string' ? flags.company : null);
  return rows.length ? rows[0].file : null;
}

function formatEntryLine(e) {
  const qs = Array.isArray(e.questions) ? e.questions.map((q) => q?.q).filter(Boolean) : [];
  return `[${e.id}|${e.bait_type}|${e.defense_status}] ${e.sentence} — ${qs.join(' / ')}`;
}

function cmdShow(flags) {
  const file = resolveShowFile(flags);
  if (!file) die('표시할 defense-map 파일을 찾지 못했습니다');
  const doc = loadDoc(file);
  if (!doc) die(`${file} 파싱에 실패했습니다`);

  const entries = Array.isArray(doc.entries) ? [...doc.entries] : [];
  entries.sort((a, b) => (STATUS_RANK[a?.defense_status] ?? 9) - (STATUS_RANK[b?.defense_status] ?? 9));
  const lines = entries.map(formatEntryLine);

  if (!lines.length) {
    process.stdout.write('(entries 없음)\n');
    return;
  }

  if (flags.all) {
    process.stdout.write(lines.join('\n') + '\n');
    return;
  }

  const rawMax = flags['max-chars'];
  const maxChars = typeof rawMax === 'string' && /^\d+$/.test(rawMax) ? parseInt(rawMax, 10) : 1500;

  let acc = '';
  let shown = 0;
  for (let i = 0; i < lines.length; i++) {
    const candidate = acc ? `${acc}\n${lines[i]}` : lines[i];
    if (candidate.length > maxChars) {
      const omitted = lines.length - shown;
      const trailer = `${acc ? '\n' : ''}… (${omitted}개 생략)`;
      process.stdout.write(acc + trailer + '\n');
      return;
    }
    acc = candidate;
    shown++;
  }
  process.stdout.write(acc + '\n');
}

// ── set-status ──────────────────────────────────────────────────────────────
function cmdSetStatus(flags, positionals) {
  let filePath;
  let entryId;
  let status;

  if (typeof flags.company === 'string') {
    filePath = resolveShowFile({ company: flags.company });
    if (!filePath) die(`--company ${flags.company} 에 해당하는 defense-map 파일을 찾지 못했습니다`);
    [entryId, status] = positionals;
  } else {
    const [f, ...restPositionals] = positionals;
    if (!f) die('file 또는 --company 를 지정하세요');
    if (existsSync(f)) {
      filePath = resolve(f);
    } else if (existsSync(join(DM_DIR, f))) {
      filePath = join(DM_DIR, f);
    } else {
      die(`파일을 찾을 수 없습니다: ${f}`);
    }
    [entryId, status] = restPositionals;
  }
  filePath = assertInsideDmDir(filePath);

  if (!entryId || !status) die('entry-id 와 status(ready|weak|unprepared) 를 지정하세요');
  if (!DEFENSE_STATUSES.includes(status)) die(`status 는 ${DEFENSE_STATUSES.join('|')} 중 하나여야 합니다`);

  const raw = readRaw(filePath);
  if (raw === null) die(`파일을 찾을 수 없습니다: ${filePath}`);
  let doc;
  try {
    doc = parseDocument(raw);
  } catch (e) {
    die(`${filePath} YAML 파싱 실패 — ${e.message}`);
  }
  const entriesNode = doc.get('entries', true);
  if (!YAML.isSeq(entriesNode)) die(`${filePath}: entries 가 리스트가 아닙니다`);
  const item = entriesNode.items.find((it) => YAML.isMap(it) && it.get('id') === entryId);
  if (!item) die(`entry ${entryId} 를 찾을 수 없습니다`);

  item.set('defense_status', status);
  atomicWrite(filePath, doc.toString());
  process.stdout.write(`갱신됨: ${entryId} → ${DEFENSE_STATUS_LABEL[status]}(${status})\n경로: ${filePath}\n`);
}

// ── stats (retro 소비용) ────────────────────────────────────────────────────
function cmdStats(flags) {
  const rows = docRows(typeof flags.company === 'string' ? flags.company : null);
  const totals = rows.reduce(
    (acc, { doc }) => {
      const r = readyRatio(doc);
      acc.ready += r.ready;
      acc.total += r.total;
      return acc;
    },
    { ready: 0, total: 0 },
  );

  if (flags.json) {
    const out = {
      files: rows.map(({ file, doc }) => {
        const r = readyRatio(doc);
        return { file, company: doc.company, position: doc.position, ready: r.ready, total: r.total, ratio: fmtRatio(r) };
      }),
      overall: { ready: totals.ready, total: totals.total, ratio: fmtRatio(totals) },
    };
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
    return;
  }

  if (!rows.length) {
    console.log('defense-map 파일이 없습니다');
    return;
  }
  const bar = '━'.repeat(60);
  console.log('방어 준비율');
  console.log(bar);
  for (const { doc } of rows) {
    console.log(`${doc.company} · ${doc.position}  준비율 ${fmtRatio(readyRatio(doc))}`);
  }
  console.log(bar);
  console.log(`전체  준비율 ${fmtRatio(totals)}`);
}

// ── validate ────────────────────────────────────────────────────────────────
function cmdValidate(positionals) {
  const fileArg = positionals[0];
  if (!fileArg) die('검사할 file 을 지정하세요 (jobstack-defense-map validate <file>)');
  const filePath = resolve(fileArg);
  const raw = readRaw(filePath);
  if (raw === null) {
    console.log(`[FAIL] ${filePath}: 파일이 없습니다`);
    return 1;
  }
  let doc;
  try {
    doc = parse(raw);
  } catch (e) {
    console.log(`[FAIL] ${filePath}: YAML 파싱 실패 — ${e.message}`);
    return 1;
  }
  const { errors, warnings } = validateDoc(doc, filePath);
  for (const w of warnings) console.log(`[경고] ${w}`);
  if (errors.length) {
    for (const e of errors) console.log(`[FAIL] ${e}`);
    return 1;
  }
  const n = Array.isArray(doc?.entries) ? doc.entries.length : 0;
  console.log(`[PASS] entries ${n}개`);
  return 0;
}

// ── main ────────────────────────────────────────────────────────────────────
const argvAll = process.argv.slice(2);
if (argvAll.includes('--help') || argvAll.includes('-h')) {
  process.stdout.write(usage());
  process.exit(0);
}
const [cmd, ...rest] = argvAll;
if (!cmd) {
  process.stderr.write(usage());
  process.exit(1);
}
const { flags, positionals } = parseArgs(rest);

try {
  switch (cmd) {
    case 'add':
      withLock(join(DM_DIR, '.write'), () => cmdAdd(flags)); // 디렉토리 단위 잠금(PR #17 리뷰 반영)
      break;
    case 'list':
      cmdList(flags);
      break;
    case 'show':
      cmdShow(flags);
      break;
    case 'set-status':
      withLock(join(DM_DIR, '.write'), () => cmdSetStatus(flags, positionals)); // 디렉토리 단위 잠금(PR #17 리뷰 반영)
      break;
    case 'stats':
      cmdStats(flags);
      break;
    case 'validate':
      process.exit(cmdValidate(positionals));
      break;
    default:
      process.stderr.write(`알 수 없는 명령: ${cmd}\n\n${usage()}`);
      process.exit(1);
  }
} catch (e) {
  if (e?.code === LOCK_TIMEOUT_CODE) die(e.message); // 스택 트레이스 대신 안내(PR #18 리뷰)
  throw e;
}
