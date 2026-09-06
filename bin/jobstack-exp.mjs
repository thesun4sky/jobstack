#!/usr/bin/env node
/**
 * jobstack-exp.mjs — 경험뱅크 카드(experiences.yaml)의 결정적 조작 (U-09).
 *
 * experience-bank 스킬이 카드를 손으로 append/edit 하던 작업을 이 스크립트가 맡는다.
 * 같은 입력이면 같은 출력이 나온다. 판정(수치 O/△/X)·스키마 검증만 결정적으로 수행하고,
 * 소재 발굴·코칭(6단계·4분리·수치 폴백)은 experience-bank 스킬의 몫이다.
 *
 * 사용법:
 *   jobstack-exp add --title T --problem P --role R --action A --change C
 *                     [--numbers N] [--tags a,b] [--json '{...}']
 *                     [--ai-usage-tool X --ai-usage-task Y --ai-usage-effect Z]
 *   jobstack-exp list [--json] [--company C]
 *   jobstack-exp show <id>
 *   jobstack-exp update <id> [--title T] [--problem P] [--role R] [--action A]
 *                     [--change C] [--numbers N] [--tags a,b]
 *                     [--ai-usage-tool X] [--ai-usage-task Y] [--ai-usage-effect Z]
 *   jobstack-exp apply <id> --company C --plan P --basis B --source S [--position X]
 *                     (STAR-R 의 R = 입사 후 적용. 회사당 1건 upsert — 근거·출처가 비면 거부.
 *                      같은 회사 재-apply 는 항목 전체를 교체하므로 --position 생략 시 이전 값은 사라진다.
 *                      회사명 비교: 유니코드 NFKC → 공백·대시·비가시 문자 제거 → 소문자)
 *   jobstack-exp validate [file]
 *
 * 환경: JOBSTACK_STATE_DIR (기본 ~/.jobstack) → profiles/experiences.yaml
 * 종료 코드: 0 정상 · 1 오류 · 3 의존성 없음(yaml 패키지 미설치)
 *
 * 스키마 정의: docs/experience-card-schema.md
 */

import { existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs';
import { withLock, LOCK_TIMEOUT_CODE } from './lib/lockfile.mjs';
import { dirname, join, resolve } from 'node:path';
import { homedir } from 'node:os';
import { randomBytes } from 'node:crypto';

let YAML;
try {
  YAML = await import('yaml');
} catch {
  process.stderr.write('jobstack-exp: `yaml` 패키지가 없습니다 — bin/ 에서 `npm install` 후 재시도하세요\n');
  process.exit(3);
}
const { parseDocument, parse, stringify } = YAML;

const STATE_DIR = process.env.JOBSTACK_STATE_DIR || join(homedir(), '.jobstack');
const EXP_FILE = join(STATE_DIR, 'profiles', 'experiences.yaml');

const REQUIRED_FIELDS = ['id', 'title', 'problem', 'role', 'action', 'change', 'created_at'];
const ID_RE = /^exp-\d{8}-\d{2}$/;
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;
const UPDATE_SIMPLE_FIELDS = ['title', 'problem', 'role', 'action', 'change', 'numbers'];
// apply_plans (STAR-R 의 R = 입사 후 적용) — 회사당 1건, 근거(basis)·출처(source) 없이는 저장하지 않는다
const APPLY_REQUIRED = ['company', 'plan', 'basis', 'source'];
// 회사명 정규화 — NFKC(전각·결합 문자 통일) 뒤 공백·대시(\p{Pd})·비가시 서식 문자(\p{Cf}: zero-width·BOM 등) 제거, 소문자.
// 보이지 않는 문자만 다른 회사명이 별개 항목으로 저장되지 않게 한다(회사당 1건 불변식)
const normCompany = (s) => String(s ?? '').normalize('NFKC').replace(/[\s\p{Pd}\p{Cf}]+/gu, '').toLowerCase();
const applyPlansOf = (card) => (Array.isArray(card?.apply_plans) ? card.apply_plans : []);
// 회사명 느슨 매칭(위 정규화 뒤 부분일치) — defense-map 의 회사 매칭 규칙에 NFKC·비가시 문자 제거를 더한 것.
// matches = 부분일치 전체, exact = 정규화 등치 1건. 계열사 항목이 여럿이면(토스페이먼츠·토스증권 ↔ '토스')
// 단수 키를 비우고 모호 플래그를 준다 — 소비 스킬이 다른 법인의 계획을 섞어 쓰지 않게(PR #18 리뷰)
function matchPlans(card, query) {
  const key = normCompany(query);
  if (!key) return { matches: [], exact: null };
  const matches = applyPlansOf(card).filter((p) => normCompany(p?.company).includes(key));
  const exact = matches.find((p) => normCompany(p?.company) === key) ?? null;
  return { matches, exact };
}
function matchSummary(card, query) {
  const { matches, exact } = matchPlans(card, query);
  const single = exact ?? (matches.length === 1 ? matches[0] : null);
  return { matched_apply_plan: single, matched_apply_plans: matches, ambiguous_company_match: single === null };
}

// ── KST/UTC 날짜 헬퍼 (가드레일 §4: 날짜가 실리는 출력은 항상 기준일을 KST로 확정) ──────
function kstNow() {
  return new Date(Date.now() + 9 * 3600 * 1000);
}
function pad2(n) {
  return String(n).padStart(2, '0');
}
function kstDateCompact(d = kstNow()) {
  return `${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}`;
}
function kstDateDash(d = kstNow()) {
  return `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}
function nowUtcIsoZ() {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z');
}

function die(msg, code = 1) {
  process.stderr.write(`jobstack-exp: ${msg}\n`);
  process.exit(code);
}

function usage() {
  return `사용법:
  jobstack-exp add --title T --problem P --role R --action A --change C
                    [--numbers N] [--tags a,b] [--json '{...}']
                    [--ai-usage-tool X --ai-usage-task Y --ai-usage-effect Z]
  jobstack-exp list [--json] [--company C]
  jobstack-exp show <id>
  jobstack-exp update <id> [--title T] [--problem P] [--role R] [--action A]
                    [--change C] [--numbers N] [--tags a,b]
                    [--ai-usage-tool X] [--ai-usage-task Y] [--ai-usage-effect Z]
  jobstack-exp apply <id> --company C --plan P --basis B --source S [--position X]
                    (입사 후 적용 — 회사당 1건 upsert, --basis/--source 가 비면 저장하지 않음)
  jobstack-exp validate [file]

환경: JOBSTACK_STATE_DIR (기본 ~/.jobstack) → profiles/experiences.yaml
종료 코드: 0 정상 · 1 오류 · 3 의존성 없음(yaml 패키지 미설치)
스키마: docs/experience-card-schema.md
`;
}

// ── 인자 파싱 — "--flag value" 는 값으로, "--flag --other"/말미의 "--flag" 는 불리언으로 ──
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

// ── 원자적 쓰기 — 임시 파일 + rename, 상태 디렉토리 안쪽에만 ────────────────────────
function atomicWrite(filePath, content) {
  const dir = dirname(filePath);
  mkdirSync(dir, { recursive: true });
  const tmp = join(dir, `.${Date.now()}.${randomBytes(4).toString('hex')}.tmp`);
  writeFileSync(tmp, content, 'utf8');
  renameSync(tmp, filePath);
}

function readRaw(filePath) {
  if (!existsSync(filePath)) return null;
  return readFileSync(filePath, 'utf8');
}

// ── 기존 카드 로드 (파싱만 — 재덤프 금지) ───────────────────────────────────────
function loadExisting() {
  const raw = readRaw(EXP_FILE);
  if (raw === null || raw.trim() === '') return { raw: raw ?? '', cards: [] };
  let parsed;
  try {
    parsed = parse(raw);
  } catch (e) {
    die(`${EXP_FILE} YAML 파싱 실패 — ${e.message}`);
  }
  if (parsed === null || parsed === undefined) return { raw, cards: [] };
  if (!Array.isArray(parsed)) die(`${EXP_FILE}: 최상위가 리스트가 아닙니다`);
  return { raw, cards: parsed };
}

function nextId(cards, dateCompact) {
  let max = 0;
  const re = new RegExp(`^exp-${dateCompact}-(\\d+)$`);
  for (const c of cards) {
    const m = re.exec(String(c?.id ?? ''));
    if (m) max = Math.max(max, parseInt(m[1], 10));
  }
  return `exp-${dateCompact}-${pad2(max + 1)}`;
}

// ── add ─────────────────────────────────────────────────────────────────────
function cmdAdd(flags) {
  let fromJson = {};
  if (typeof flags.json === 'string') {
    try {
      fromJson = JSON.parse(flags.json);
    } catch (e) {
      die(`--json 파싱 실패: ${e.message}`);
    }
    if (fromJson === null || typeof fromJson !== 'object' || Array.isArray(fromJson)) {
      die('--json 값은 객체여야 합니다');
    }
  }
  // 개별 플래그가 --json 블록보다 우선(둘 다 병행 가능)
  const pick = (key) => (typeof flags[key] === 'string' ? flags[key] : fromJson[key]);

  const title = pick('title');
  const problem = pick('problem');
  const role = pick('role');
  const action = pick('action');
  const change = pick('change');
  const numbers = pick('numbers') ?? '';

  const missing = [];
  if (!title) missing.push('--title');
  if (!problem) missing.push('--problem');
  if (!role) missing.push('--role');
  if (!action) missing.push('--action');
  if (!change) missing.push('--change');
  if (missing.length) die(`필수 인자 누락: ${missing.join(', ')}`);

  // job_link_tags: --tags "a,b" 가 --json 의 tags/job_link_tags 보다 우선
  let tags = fromJson.job_link_tags ?? fromJson.tags ?? [];
  if (typeof flags.tags === 'string') {
    tags = flags.tags.split(',').map((s) => s.trim()).filter(Boolean);
  }
  if (!Array.isArray(tags)) die('tags 는 배열(또는 --tags a,b 콤마 목록)이어야 합니다');
  tags = tags.map((t) => String(t));

  // ai_usage — 세 플래그는 함께 지정(부분 입력은 즉시 스키마 위반이 되므로 add 단계에서 막는다)
  const aiTool = pick('ai-usage-tool');
  const aiTask = pick('ai-usage-task');
  const aiEffect = pick('ai-usage-effect');
  let aiUsage = fromJson.ai_usage ?? null;
  if (aiTool || aiTask || aiEffect) {
    if (!(aiTool && aiTask && aiEffect)) {
      die('--ai-usage-tool / --ai-usage-task / --ai-usage-effect 는 함께 지정해야 합니다');
    }
    aiUsage = { tool: String(aiTool), task: String(aiTask), effect: String(aiEffect) };
  }
  if (aiUsage !== null && (typeof aiUsage !== 'object' || Array.isArray(aiUsage))) {
    die('ai_usage 는 null 또는 {tool, task, effect} 객체여야 합니다');
  }

  const { raw, cards } = loadExisting();
  const dateCompact = kstDateCompact();
  const id = nextId(cards, dateCompact);

  const card = {
    id,
    title: String(title),
    problem: String(problem),
    role: String(role),
    action: String(action),
    change: String(change),
    numbers: String(numbers),
    job_link_tags: tags,
    ai_usage: aiUsage,
    created_at: nowUtcIsoZ(),
  };

  const block = stringify([card]); // "- id: ...\n  ...\n" — 새 카드 1장짜리 블록 시퀀스
  let base = raw || '';
  if (base && !base.endsWith('\n')) base += '\n';
  const newContent = base + block;

  // append 후 전체 파싱 검증 — 실패하면 아무것도 쓰지 않고 종료(롤백 = 디스크 미변경 보장)
  let reparsed;
  try {
    reparsed = parse(newContent);
  } catch (e) {
    die(`append 검증 실패(롤백, 원본 파일 미변경) — ${e.message}`);
  }
  if (!Array.isArray(reparsed)) {
    die('append 검증 실패(롤백, 원본 파일 미변경) — 결과가 리스트가 아닙니다');
  }

  atomicWrite(EXP_FILE, newContent);
  process.stdout.write(`추가됨: ${id}\n경로: ${EXP_FILE}\n`);
}

// ── list ────────────────────────────────────────────────────────────────────
function verdictOf(card) {
  const n = card?.numbers;
  if (n === undefined || n === null || String(n).trim() === '') return 'X';
  if (String(n).includes('[수치 확인 필요]')) return '△';
  return 'O';
}

function cmdList(flags) {
  const { cards: all } = loadExisting();
  const today = kstDateDash();
  // --company 를 값 없이(또는 공백만) 주면 무필터로 조용히 폴백하지 않고 거부한다 — 전체 카드를 필터 결과로 오인하게 되므로
  let filter = null;
  if (flags.company !== undefined) {
    filter = typeof flags.company === 'string' ? flags.company.trim() : '';
    if (!filter) die('--company 값을 지정하세요 (jobstack-exp list --company <회사명>)');
  }
  const cards = filter ? all.filter((c) => matchPlans(c, filter).matches.length > 0) : all;
  const verdicts = cards.map(verdictOf);
  const needsNumbers = verdicts.filter((v) => v !== 'O').length;
  const withPlans = cards.filter((c) => applyPlansOf(c).length > 0).length;
  const ambiguous = filter ? cards.filter((c) => matchSummary(c, filter).ambiguous_company_match).length : 0;

  if (flags.json) {
    const out = {
      today_kst: today,
      total: cards.length,
      needs_numbers: needsNumbers,
      with_apply_plans: withPlans,
      ...(filter ? { company_filter: filter, ambiguous_company_matches: ambiguous } : {}),
      cards: cards.map((c, i) => ({
        ...c,
        numbers_verdict: verdicts[i],
        ai_usage_present: !!c?.ai_usage,
        apply_plans_count: applyPlansOf(c).length,
        ...(filter ? matchSummary(c, filter) : {}),
      })),
    };
    process.stdout.write(JSON.stringify(out, null, 2) + '\n');
    return;
  }

  const bar = '━'.repeat(56);
  console.log(`경험뱅크 요약  (기준일: ${today}${filter ? ` · 회사 필터: ${filter}` : ''})`);
  console.log(bar);
  console.log(`${'id'.padEnd(16)} ${'제목'.padEnd(24)} 수치   AI   적용  직무 태그`);
  cards.forEach((c, i) => {
    const id = String(c?.id ?? '').padEnd(16);
    const title = String(c?.title ?? '').padEnd(24);
    const verdict = verdicts[i].padEnd(4);
    const ai = (c?.ai_usage ? 'O' : '-').padEnd(3);
    const plans = applyPlansOf(c).length;
    const apply = (plans ? String(plans) : '-').padEnd(4);
    const tags = Array.isArray(c?.job_link_tags) ? c.job_link_tags.join(', ') : '';
    console.log(`${id} ${title} ${verdict}   ${ai} ${apply} ${tags}`);
  });
  console.log(bar);
  const ambiguousNote = ambiguous ? ` · 회사 필터 부분일치 모호 ${ambiguous}장(정확한 회사명으로 다시 조회)` : '';
  console.log(`카드 ${cards.length}장 · 수치 보강 필요 ${needsNumbers}장 · 입사 후 적용 ${withPlans}장${ambiguousNote}`);
}

// ── show ────────────────────────────────────────────────────────────────────
function cmdShow(positionals) {
  const id = positionals[0];
  if (!id) die('id 를 지정하세요 (jobstack-exp show <id>)');
  const { cards } = loadExisting();
  const card = cards.find((c) => c?.id === id);
  if (!card) die(`${id} 카드를 찾을 수 없습니다`);
  process.stdout.write(stringify(card));
}

// ── update ──────────────────────────────────────────────────────────────────
function cmdUpdate(positionals, flags) {
  const id = positionals[0];
  if (!id) die('id 를 지정하세요 (jobstack-exp update <id> --field value ...)');

  const raw = readRaw(EXP_FILE);
  if (raw === null || raw.trim() === '') die(`${id} 카드를 찾을 수 없습니다 (경험뱅크 파일 없음)`);

  let doc;
  try {
    doc = parseDocument(raw);
  } catch (e) {
    die(`${EXP_FILE} YAML 파싱 실패 — ${e.message}`);
  }
  const seq = doc.contents;
  if (!YAML.isSeq(seq)) die(`${EXP_FILE}: 최상위가 리스트가 아닙니다`);
  const item = seq.items.find((it) => YAML.isMap(it) && it.get('id') === id);
  if (!item) die(`${id} 카드를 찾을 수 없습니다`);

  let touched = false;
  for (const f of UPDATE_SIMPLE_FIELDS) {
    if (typeof flags[f] === 'string') {
      item.set(f, flags[f]);
      touched = true;
    }
  }
  if (typeof flags.tags === 'string') {
    const tags = flags.tags.split(',').map((s) => s.trim()).filter(Boolean);
    item.set('job_link_tags', tags);
    touched = true;
  }

  const aiTool = flags['ai-usage-tool'];
  const aiTask = flags['ai-usage-task'];
  const aiEffect = flags['ai-usage-effect'];
  if (typeof aiTool === 'string' || typeof aiTask === 'string' || typeof aiEffect === 'string') {
    const rawAi = item.get('ai_usage', true);
    const aiMap = YAML.isMap(rawAi) ? rawAi : doc.createNode({ tool: null, task: null, effect: null });
    if (!YAML.isMap(rawAi)) item.set('ai_usage', aiMap);
    if (typeof aiTool === 'string') aiMap.set('tool', aiTool);
    if (typeof aiTask === 'string') aiMap.set('task', aiTask);
    if (typeof aiEffect === 'string') aiMap.set('effect', aiEffect);
    // add 와 동일한 제약 — 갱신 후 tool/task/effect 중 하나라도 비면 스키마 위반이므로 막는다.
    // 카드에 이미 완전한 ai_usage 가 있었다면 나머지 필드가 그대로 남아 갱신 후에도 세 값이
    // 모두 채워져 있으므로, 그 경우의 "일부 필드만 갱신"은 허용된다(리뷰 반영).
    const finalTool = aiMap.get('tool');
    const finalTask = aiMap.get('task');
    const finalEffect = aiMap.get('effect');
    const complete = typeof finalTool === 'string' && finalTool
      && typeof finalTask === 'string' && finalTask
      && typeof finalEffect === 'string' && finalEffect;
    if (!complete) {
      die('--ai-usage-tool / --ai-usage-task / --ai-usage-effect 갱신 후 세 값이 모두 채워져 있어야 합니다'
        + ' (기존에 완전한 ai_usage 가 있는 카드라면 일부 필드만 갱신 가능)');
    }
    touched = true;
  }

  if (!touched) {
    die('수정할 필드를 최소 1개 지정하세요 (--title/--problem/--role/--action/--change/--numbers/--tags/--ai-usage-tool/--ai-usage-task/--ai-usage-effect)');
  }

  atomicWrite(EXP_FILE, doc.toString());
  process.stdout.write(`수정됨: ${id}\n경로: ${EXP_FILE}\n`);
}

// ── apply — 입사 후 적용(STAR-R 의 R) 항목을 회사당 1건 upsert ──────────────────────
function cmdApply(positionals, flags) {
  const id = positionals[0];
  if (!id) die('id 를 지정하세요 (jobstack-exp apply <id> --company C --plan P --basis B --source S [--position X])');
  const missing = APPLY_REQUIRED
    .filter((k) => typeof flags[k] !== 'string' || !flags[k].trim())
    .map((k) => `--${k}`);
  if (missing.length) {
    die(`필수 인자 누락: ${missing.join(', ')} (근거 --basis·출처 --source 없이는 입사 후 적용을 저장하지 않습니다)`);
  }
  // --position 을 값 없이 주면(다음 토큰이 플래그이거나 말미) 조용히 버리지 않고 거부한다
  if (flags.position !== undefined && typeof flags.position !== 'string') {
    die('--position 값이 비어 있습니다 (값을 지정하거나 --position 을 생략하세요)');
  }
  if (!normCompany(flags.company)) die('--company 값이 비어 있습니다 (보이지 않는 문자만으로는 회사명이 되지 않습니다)');

  const raw = readRaw(EXP_FILE);
  if (raw === null || raw.trim() === '') die(`${id} 카드를 찾을 수 없습니다 (경험뱅크 파일 없음)`);
  let doc;
  try {
    doc = parseDocument(raw);
  } catch (e) {
    die(`${EXP_FILE} YAML 파싱 실패 — ${e.message}`);
  }
  const seq = doc.contents;
  if (!YAML.isSeq(seq)) die(`${EXP_FILE}: 최상위가 리스트가 아닙니다`);
  const item = seq.items.find((it) => YAML.isMap(it) && it.get('id') === id);
  if (!item) die(`${id} 카드를 찾을 수 없습니다`);

  // 기존 apply_plans 시퀀스를 그대로 쓰고(주석 보존), 없거나 null 이면 새 블록 시퀀스를 만든다
  let plans = item.get('apply_plans', true);
  if (!YAML.isSeq(plans)) {
    plans = doc.createNode([]);
    item.set('apply_plans', plans);
  }
  if (plans.flow) plans.flow = false;

  // 표시명에서도 비가시 서식 문자는 뺀다 — 자소서·면접 산출물에 zero-width 문자가 실려 나가지 않게
  const entry = { company: flags.company.trim().replace(/\p{Cf}+/gu, '') };
  if (typeof flags.position === 'string' && flags.position.trim()) entry.position = flags.position.trim();
  entry.plan = flags.plan.trim();
  entry.basis = flags.basis.trim();
  entry.source = flags.source.trim();
  entry.created_at = nowUtcIsoZ();

  // 같은 회사(정규화 등치)는 교체, 아니면 추가 — 회사당 1건 계약
  const key = normCompany(entry.company);
  const idx = plans.items.findIndex((p) => YAML.isMap(p) && normCompany(p.get('company')) === key);
  const node = doc.createNode(entry);
  if (idx >= 0) {
    // 교체해도 항목에 붙은 주석은 남긴다 — 항목 뒤(다음 항목·다음 필드 앞) 주석은 yaml 이 이 항목 맵의 comment 로 붙인다
    const old = plans.items[idx];
    if (old.commentBefore) node.commentBefore = old.commentBefore;
    if (old.comment) node.comment = old.comment;
    if (old.spaceBefore) node.spaceBefore = old.spaceBefore;
    plans.items[idx] = node;
  } else {
    plans.add(node);
  }

  atomicWrite(EXP_FILE, doc.toString());
  process.stdout.write(`적용 저장됨: ${id} · ${entry.company} (${idx >= 0 ? '교체' : '신규'})\n경로: ${EXP_FILE}\n`);
}

// ── validate ────────────────────────────────────────────────────────────────
function cmdValidate(positionals) {
  const fileArg = positionals[0];
  const file = fileArg ? resolve(fileArg) : EXP_FILE;
  const raw = readRaw(file);
  if (raw === null || raw.trim() === '') {
    console.log('[PASS] 카드 0장');
    return 0;
  }

  let parsed;
  try {
    parsed = parse(raw);
  } catch (e) {
    console.log(`[FAIL] ${file}: YAML 파싱 실패 — ${e.message}`);
    return 1;
  }
  if (parsed === null || parsed === undefined) {
    console.log('[PASS] 카드 0장');
    return 0;
  }
  if (!Array.isArray(parsed)) {
    console.log(`[FAIL] ${file}: 최상위가 리스트가 아닙니다`);
    return 1;
  }

  const errors = [];
  const seenIds = new Set();
  parsed.forEach((card, idx) => {
    const hasId = card && typeof card === 'object' && typeof card.id === 'string' && card.id;
    const label = hasId ? card.id : `#${idx + 1}(id 없음)`;
    if (card === null || typeof card !== 'object' || Array.isArray(card)) {
      errors.push(`${label}: 카드가 객체가 아닙니다`);
      return;
    }
    for (const f of REQUIRED_FIELDS) {
      const v = card[f];
      if (v === undefined || v === null || v === '') errors.push(`${label}: 필수 필드 누락 (${f})`);
      else if (typeof v !== 'string') errors.push(`${label}: ${f} 필드는 문자열이어야 합니다`); // 숫자 id 는 show/update/apply 가 찾지 못한다(PR #18 리뷰)
      else if (!v.trim()) errors.push(`${label}: 필수 필드 누락 (${f} — 공백뿐)`);
    }
    if (hasId) {
      if (!ID_RE.test(card.id)) errors.push(`${label}: id 형식 오류 (exp-YYYYMMDD-NN 아님)`);
      if (seenIds.has(card.id)) errors.push(`${label}: id 중복`);
      seenIds.add(card.id);
    }
    if (typeof card.created_at === 'string' && card.created_at) {
      if (!ISO_RE.test(card.created_at) || Number.isNaN(Date.parse(card.created_at))) {
        errors.push(`${label}: created_at 형식 오류 (ISO 8601 아님)`);
      }
    }
    if (card.job_link_tags !== undefined && card.job_link_tags !== null) {
      const ok = Array.isArray(card.job_link_tags) && card.job_link_tags.every((t) => typeof t === 'string');
      if (!ok) errors.push(`${label}: job_link_tags 는 문자열 배열이어야 합니다`);
    }
    if (card.numbers !== undefined && card.numbers !== null && typeof card.numbers !== 'string') {
      errors.push(`${label}: numbers 는 문자열이어야 합니다`);
    }
    if (card.ai_usage !== undefined && card.ai_usage !== null) {
      const au = card.ai_usage;
      const ok = typeof au === 'object' && !Array.isArray(au)
        && typeof au.tool === 'string' && typeof au.task === 'string' && typeof au.effect === 'string';
      if (!ok) errors.push(`${label}: ai_usage 는 null 또는 {tool, task, effect} 문자열 객체여야 합니다`);
    }
    if (card.apply_plans !== undefined && card.apply_plans !== null) {
      const plans = card.apply_plans;
      if (!Array.isArray(plans)) {
        errors.push(`${label}: apply_plans 는 배열이어야 합니다`);
      } else {
        const seenCompanies = new Set();
        plans.forEach((p, j) => {
          const tag = `apply_plans[${j}]`;
          if (p === null || typeof p !== 'object' || Array.isArray(p)) {
            errors.push(`${label}: ${tag} 항목이 객체가 아닙니다`);
            return;
          }
          for (const k of APPLY_REQUIRED) {
            const blank = typeof p[k] !== 'string' || !p[k].trim() || (k === 'company' && !normCompany(p[k]));
            if (blank) errors.push(`${label}: ${tag} ${k} 가 비어 있습니다`);
          }
          if (p.position !== undefined && p.position !== null && typeof p.position !== 'string') {
            errors.push(`${label}: ${tag} position 은 문자열이어야 합니다`);
          }
          if (p.created_at === undefined || p.created_at === null || p.created_at === '') {
            errors.push(`${label}: ${tag} created_at 가 비어 있습니다`);
          } else if (typeof p.created_at !== 'string' || !ISO_RE.test(p.created_at) || Number.isNaN(Date.parse(p.created_at))) {
            errors.push(`${label}: ${tag} created_at 형식 오류 (ISO 8601 아님)`);
          }
          const key = normCompany(p.company);
          if (key) {
            if (seenCompanies.has(key)) errors.push(`${label}: ${tag} 회사 중복 (${p.company})`);
            seenCompanies.add(key);
          }
        });
      }
    }
  });

  if (errors.length) {
    for (const e of errors) console.log(`[FAIL] ${e}`);
    return 1;
  }
  console.log(`[PASS] 카드 ${parsed.length}장`);
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
      withLock(EXP_FILE, () => cmdAdd(flags)); // 동시 실행 lost update 방지(PR #17 리뷰 반영)
      break;
    case 'list':
      cmdList(flags);
      break;
    case 'show':
      cmdShow(positionals);
      break;
    case 'update':
      withLock(EXP_FILE, () => cmdUpdate(positionals, flags)); // 동시 실행 lost update 방지(PR #17 리뷰 반영)
      break;
    case 'apply':
      withLock(EXP_FILE, () => cmdApply(positionals, flags)); // add/update 와 같은 잠금 경로
      break;
    case 'validate':
      process.exit(cmdValidate(positionals));
      break;
    default:
      process.stderr.write(`알 수 없는 명령: ${cmd}\n\n${usage()}`);
      process.exit(1);
  }
} catch (e) {
  if (e?.code === LOCK_TIMEOUT_CODE) die(e.message); // 스택 트레이스 대신 jobstack-exp: 안내(PR #18 리뷰)
  throw e;
}
