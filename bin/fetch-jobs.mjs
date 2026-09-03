#!/usr/bin/env node
/**
 * Playwright-based job listing fetcher for JS-rendered platforms.
 * Usage: node fetch-jobs.mjs <platform> <keyword> [limit] [career] [location] [--source=api|scrape|auto]
 *        node fetch-jobs.mjs verify <url|id> [<url|id>...]
 * Platform: jumpit | jobkorea | saramin | wanted
 * Career: entry (신입) | experienced (경력) | (생략시 전체)
 * Location: seoul|gyeonggi|busan|incheon|daejeon|daegu|gwangju|remote (생략시 전체)
 * --source: saramin 전용 옵션 — api(오픈API만) | scrape(HTML 스크래핑만) | auto(기본값,
 *   오픈API 우선 시도 후 null/0건이면 스크래핑 폴백). 어느 값이든 사람인은 Chromium 을
 *   기동하지 않는다 — jumpit/jobkorea/wanted 만 필요할 때 Playwright 를 lazy 기동한다.
 * Outputs JSON array to stdout.
 */

import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { readFileSync } from 'node:fs';
import { logFailure } from './fetch-diag.mjs';
import { verifyWantedJobs, verifyInputs } from './wanted-verify.mjs';
import { fetchViaIsFetch } from './is-fetch-adapter.mjs';
import { parseSaraminSearch } from './parsers/saramin.mjs';
import { fetchSaraminApi, readSaraminKey, SARAMIN_LOC_CD } from './sources/saramin-api.mjs';

const BIN_DIR = dirname(fileURLToPath(import.meta.url));
const JOBSTACK_CONFIG_BIN = join(BIN_DIR, 'jobstack-config');

// ─── --source= 옵션 추출 — 위치 인수(platform/keyword/limit/career/location) 파싱보다
// 먼저 argv 에서 걷어낸다. argv 어디에 있든(맨 뒤 등) 나머지 위치 인수 순서는 그대로
// 유지된다 — 기존 위치 인자 호출 방식과 100% 호환(U-12 ② ③).
const SOURCE_FLAG_RE = /^--source=(.*)$/;
let sourceArg = null;
const positional = [];
for (const raw of process.argv.slice(2)) {
  const m = SOURCE_FLAG_RE.exec(raw);
  if (m) { sourceArg = m[1]; continue; }
  positional.push(raw);
}
const [platform, keyword, arg3, arg4, arg5] = positional;

// ─── verify 서브커맨드 — 원티드 공고 생사 확인 (Playwright 불필요) ─────────────
// WebSearch 유입 링크·캐시 재사용·"마감 여부 확인" 요청의 표준 판정 도구.
// HTML 페이지는 마감 배너를 JS 렌더링해 판정 불가 → detail API만 신뢰.
if (platform === 'verify') {
  const inputs = positional.slice(1);
  if (inputs.length === 0) {
    process.stderr.write('Usage: fetch-jobs.mjs verify <wanted-url|id> [<wanted-url|id>...]\n');
    process.exit(1);
  }
  const verdicts = await verifyInputs(inputs);
  // write 콜백으로 flush 완료를 기다린 뒤 종료 — 즉시 process.exit(0)하면 대량 출력이
  // OS 버퍼로 flush되기 전에 잘릴 수 있다(리뷰 반영).
  await new Promise((resolve) => {
    process.stdout.write(JSON.stringify(verdicts, null, 2) + '\n', resolve);
  });
  // 전건 판정 불가(bad_input/전건 unknown)면 비정상 종료로 오케스트레이터가 실패를 구분하게 한다.
  const allBad = verdicts.length > 0 && verdicts.every((v) => v.verdict === 'unknown');
  process.exit(allBad ? 2 : 0);
}

// ─── --source 값 검증 (U-12 ③ — 사람인 api|scrape|auto 분기, 기본 auto) ────────────
const SOURCE_MODES = ['api', 'scrape', 'auto'];
const sourceMode = sourceArg === null ? 'auto' : sourceArg;
if (!SOURCE_MODES.includes(sourceMode)) {
  process.stderr.write(`Unknown --source: ${sourceMode}. Supported: ${SOURCE_MODES.join(', ')}\n`);
  process.exit(1);
}

// arg3이 숫자가 아니면 career로 해석 (limit 생략 호출: fetch-jobs.mjs platform keyword entry)
let limit, career;
if (arg3 && isNaN(parseInt(arg3, 10))) {
  limit = 20;
  career = arg3.toLowerCase();
} else {
  limit = parseInt(arg3 || '20', 10);
  career = (arg4 || '').toLowerCase();
}
// 지역 필터: 6번째 인수 또는 arg4가 지역 코드인 경우
const LOCATION_KEYS = ['seoul','gyeonggi','busan','incheon','daejeon','daegu','gwangju','remote'];
let location = '';
if (arg5 && LOCATION_KEYS.includes(arg5.toLowerCase())) {
  location = arg5.toLowerCase();
} else if (arg4 && LOCATION_KEYS.includes(arg4.toLowerCase())) {
  location = arg4.toLowerCase();
}

// 한국어 지역명 (키워드 임베딩용 — jumpit/jobkorea 전용)
const LOCATION_KO = {
  seoul: '서울', gyeonggi: '경기', busan: '부산', incheon: '인천',
  daejeon: '대전', daegu: '대구', gwangju: '광주', remote: '재택근무',
};
// 사람인 loc_cd 매핑은 bin/sources/saramin-api.mjs 의 SARAMIN_LOC_CD 를 그대로 쓴다
// (U-12 ④ — fetch-jobs.mjs·saramin-api.mjs 양쪽에 흩어져 있던 표를 단일화, import 로 대체).

if (!platform || !keyword) {
  process.stderr.write(
    'Usage: fetch-jobs.mjs <platform> <keyword> [limit] [career] [location] [--source=api|scrape|auto]\n'
    + '       fetch-jobs.mjs verify <wanted-url|id> [<wanted-url|id>...]\n',
  );
  process.exit(1);
}

const PLATFORMS = ['jumpit', 'jobkorea', 'saramin', 'wanted'];
if (!PLATFORMS.includes(platform)) {
  process.stderr.write(`Unknown platform: ${platform}. Supported: ${PLATFORMS.join(', ')}\n`);
  process.exit(1);
}

// ─── Playwright lazy 기동 헬퍼 (U-12 ② — 필요한 플랫폼 분기에서 처음 호출될 때만 기동) ──
// jumpit/jobkorea/wanted 만 Chromium 이 필요하다. 사람인 분기는 이 함수를 절대 호출하지
// 않는다 — 사람인은 어떤 --source 값이든 브라우저 없이 동작해야 한다(요구사항 2).
let browser = null;
let context = null;
let currentPage = null; // 0건 진단(page.content() 폴백)이 참조 — 브라우저 미기동 플랫폼(사람인)에선 null 유지

async function getPage() {
  if (!context) {
    let chromium;
    try {
      ({ chromium } = await import('playwright'));
    } catch (err) {
      // 이 분기(jumpit/jobkorea/wanted)에서만 발생한다 — 명확한 오류만 남기고 상위
      // try/catch 가 빈 배열로 처리하게 던진다(사람인 경로는 이 함수를 부르지 않으므로 무관).
      process.stderr.write(
        `[fetch-jobs] playwright 모듈을 찾을 수 없습니다 — bin/ 에서 npm install 을 실행하세요. (${err.message})\n`,
      );
      throw err;
    }
    browser = await chromium.launch({
      headless: true,
      args: [
        '--no-sandbox',
        '--disable-dev-shm-usage',
        '--disable-blink-features=AutomationControlled',
        '--disable-infobars',
        '--window-size=1366,768',
      ],
    });

    context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
      locale: 'ko-KR',
      viewport: { width: 1366, height: 768 },
      timezoneId: 'Asia/Seoul',
      extraHTTPHeaders: {
        'Accept-Language': 'ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7',
      },
    });

    // webdriver 감지 우회
    await context.addInitScript(() => {
      Object.defineProperty(navigator, 'webdriver', { get: () => false });
      delete window.__playwright;
      delete window.__pw_manual;
      Object.defineProperty(navigator, 'plugins', { get: () => [1, 2, 3] });
      Object.defineProperty(navigator, 'languages', { get: () => ['ko-KR', 'ko', 'en-US'] });
    });
  }
  currentPage = await context.newPage();
  return currentPage;
}

// ─── 사람인 오픈API 경로 (U-12 ③) ──────────────────────────────────────────────
/**
 * jobstack-config 에 저장된 사람인 오픈API 키(또는 테스트 픽스처)로 fetchSaraminApi 를
 * 호출한다. 키·픽스처가 둘 다 없으면 네트워크 호출 없이 no_key 로 반환한다.
 * @returns {Promise<{ok: true, jobs: Array}|{ok: false, reason: 'no_key'|'fetch_failed'}>}
 */
async function trySaraminApi({ keyword: kw, limit: lim, career: car, location: loc }) {
  const apiFixturePath = process.env.JOBSTACK_SARAMIN_API_FIXTURE;
  let accessKey = readSaraminKey(JOBSTACK_CONFIG_BIN);
  const opts = {};
  if (apiFixturePath) {
    // 테스트 훅 — JOBSTACK_SARAMIN_API_FIXTURE 가 있으면 실제 키가 없어도 API 경로를
    // 실행한다(픽스처 JSON을 fetchImpl로 주입해 네트워크를 타지 않는다). 테스트 전용.
    if (!accessKey) accessKey = 'fixture-key';
    const fixtureJson = JSON.parse(readFileSync(apiFixturePath, 'utf8'));
    opts.fetchImpl = async () => ({ ok: true, status: 200, json: async () => fixtureJson });
  }
  if (!accessKey) return { ok: false, reason: 'no_key' };
  const result = await fetchSaraminApi(
    { accessKey, keyword: kw, limit: lim, career: car, location: loc },
    opts,
  );
  if (result === null) return { ok: false, reason: 'fetch_failed' };
  return { ok: true, jobs: result };
}

// ─── 사람인 스크래핑 경로 (U-12 ②) ─────────────────────────────────────────────
/**
 * is-fetch 어댑터 우선 → 실패 시 브라우저 컨텍스트 없이 전역 fetch() 로 HTML을 확보해
 * parseSaraminSearch 로 파싱한다. 사람인은 어떤 경로에서도 Chromium 을 기동하지 않는다.
 * @returns {Promise<{jobs: Array, html: string, status: number}>}
 */
async function scrapeSaramin(url, lim) {
  const htmlFixturePath = process.env.JOBSTACK_SARAMIN_HTML_FIXTURE;
  if (htmlFixturePath) {
    // 테스트 훅 — JOBSTACK_SARAMIN_HTML_FIXTURE 가 있으면 네트워크(is-fetch·전역 fetch)
    // 대신 그 HTML 파일을 읽는다. 테스트 전용.
    const html = readFileSync(htmlFixturePath, 'utf8');
    process.stderr.write('[fetch-jobs:diag] saramin fetch_via=fixture\n');
    return { jobs: parseSaraminSearch(html, lim), html, status: 200 };
  }

  // item_recruit(사람인 검색 카드 클래스)를 셀렉터로 넘겨, 로그인/soft-block 페이지처럼
  // 크기·상태만 충족하고 카드가 없는 HTML은 too_small로 강등→전역 fetch 폴백하게 한다.
  const adapted = fetchViaIsFetch(url, { selectors: ['item_recruit'] });
  if (adapted) {
    process.stderr.write(`[fetch-jobs:diag] saramin fetch_via=is-fetch verdict=${adapted.verdict}\n`);
    return { jobs: parseSaraminSearch(adapted.html, lim), html: adapted.html, status: adapted.status };
  }

  // is-fetch 미가용/실패 — 브라우저 컨텍스트 없이 전역 fetch() 로 HTML 확보(Chromium 미기동).
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 15000);
  try {
    const resp = await fetch(url, {
      signal: controller.signal,
      headers: { 'Accept-Language': 'ko-KR,ko;q=0.9' },
    });
    const html = await resp.text();
    process.stderr.write(`[fetch-jobs:diag] saramin fetch_via=fetch status=${resp.status}\n`);
    // ok 여부와 무관하게 html/status 를 돌려준다 — 0건 진단(logFailure)이 에러 페이지를 분류할 수 있게.
    if (!resp.ok) return { jobs: [], html, status: resp.status };
    return { jobs: parseSaraminSearch(html, lim), html, status: resp.status };
  } finally {
    clearTimeout(timer);
  }
}

let jobs = [];
let lastHtml = '';   // 진단용: 마지막으로 확보한 HTML (fetch/is-fetch/fixture 또는 page DOM)
let lastStatus = 0;  // 진단용: 마지막 HTTP 상태 코드
let wantedScraped = 0; // wanted 검증 전 수집 건수 — 전량 제외 시 0건 진단 오분류 방지

try {
  if (platform === 'jumpit') {
    const page = await getPage();
    // career: entry → min_career=0&max_career=0, experienced → min_career=1
    const jtParams = new URLSearchParams({ sort: 'rsp_rate', keyword });
    if (career === 'entry') { jtParams.set('min_career', '0'); jtParams.set('max_career', '0'); }
    else if (career === 'experienced') { jtParams.set('min_career', '1'); }
    // 지역 필터: 점핏은 지역명을 키워드에 포함
    if (location && LOCATION_KO[location]) jtParams.set('keyword', `${keyword} ${LOCATION_KO[location]}`);
    const url = `https://jumpit.saramin.co.kr/search?${jtParams.toString()}`;
    const _resp = await page.goto(url, { waitUntil: 'commit', timeout: 15000 });
    lastStatus = _resp?.status() || 0;
    await page.waitForTimeout(5000);

    jobs = await page.evaluate((lim) => {
      const NOISE_RE = /D-\d|마감|상시|경력|신입|원격|재택|\d+년/;
      const links = Array.from(document.querySelectorAll('a[href*="/position/"]'));
      return links.slice(0, lim).map(a => {
        const rawTitle = a.getAttribute('title') || '';
        const title = rawTitle.replace(/<[^>]+>/g, '').trim();
        const lines = a.innerText.split('\n').map(l => l.trim()).filter(Boolean);
        const dLine = lines[0] || '';
        const company = lines[1] || '';
        let deadline = '마감일 미확인';
        if (dLine === 'D-day') deadline = '오늘 마감!';
        else if (dLine.startsWith('D-')) deadline = `${dLine.replace('D-', '')}일 후 마감`;
        else if (dLine === '상시채용') deadline = '상시채용';
        const LOCATION_RE = /[시구군동로]\s*\d*$|^서울|^경기|^부산|^인천|^대전|^대구|^광주/;
        const tagEls = Array.from(a.querySelectorAll('[class*="tag"] span, [class*="skill"] span, ul li, [class*="chip"]'));
        const skills = tagEls
          .map(el => el.innerText.replace(/^·\s*/, '').trim())
          .filter(s => s && s.length > 0 && s.length < 30 && !NOISE_RE.test(s) && !LOCATION_RE.test(s))
          .slice(0, 8).join(', ');
        return { platform: 'jumpit', company, title, deadline, dRemaining: dLine, link: a.href, skills };
      }).filter(j => j.title && j.company);
    }, limit);

  } else if (platform === 'saramin') {
    // career: URL 파라미터 미지원 → 키워드에 신입/경력 추가(스크래핑 경로 전용 — 오픈API는
    // career 를 exp_cd 파라미터로 직접 받으므로 아래 trySaraminApi 에는 원본 keyword 를 넘긴다).
    const srKeyword = career === 'entry' ? `${keyword} 신입`
      : career === 'experienced' ? `${keyword} 경력` : keyword;
    const srParams = new URLSearchParams({ searchword: srKeyword, poster_duration: '7', sort: 'RD' });
    // 지역 필터: loc_cd 파라미터 (서울=101000, 경기=102000, ...)
    if (location && SARAMIN_LOC_CD[location]) srParams.set('loc_cd', SARAMIN_LOC_CD[location]);
    if (location === 'remote') srParams.set('searchword', `${srKeyword} 재택`);
    const url = `https://www.saramin.co.kr/zf_user/search?${srParams.toString()}`;

    try {
      if (sourceMode === 'scrape') {
        const scraped = await scrapeSaramin(url, limit);
        jobs = scraped.jobs; lastHtml = scraped.html; lastStatus = scraped.status;
      } else {
        // api 또는 auto — 오픈API 먼저 시도(키·픽스처 둘 다 없으면 네트워크 없이 즉시 폴백 신호)
        const apiResult = await trySaraminApi({ keyword, limit, career, location });
        if (apiResult.ok && apiResult.jobs.length > 0) {
          jobs = apiResult.jobs;
          process.stderr.write(`[fetch-jobs:diag] saramin fetch_via=api count=${jobs.length}\n`);
        } else if (sourceMode === 'api') {
          // api 전용 모드 — 스크래핑 폴백 없음(요구사항 명시). 키 없음/호출 실패/0건 모두 빈 배열로 종료.
          jobs = [];
          const cause = apiResult.ok ? 'empty_result' : apiResult.reason;
          process.stderr.write(`[fetch-jobs:diag] saramin fetch_via=api cause=${cause}\n`);
        } else {
          // auto — null(키 없음·호출 실패) 또는 0건이면 스크래핑으로 폴백
          const cause = apiResult.ok ? 'empty_result' : apiResult.reason;
          process.stderr.write(`[fetch-jobs:diag] saramin fetch_via=api cause=${cause} fallback=scrape\n`);
          const scraped = await scrapeSaramin(url, limit);
          jobs = scraped.jobs; lastHtml = scraped.html; lastStatus = scraped.status;
        }
      }
    } catch (err) {
      process.stderr.write(`saramin scrape error: ${err.message}\n`);
    }

  } else if (platform === 'wanted') {
    // career·location 은 검색 쿼리에 임베딩하지 않는다. wanted 검색은 추가 단어를
    // AND 텍스트 매칭으로 처리해 결과를 과도하게 좁힌다(엔트리: query='백엔드 신입'
    // → 3건 vs query='백엔드' → 17건, prod 검증 2026-06-20). career 는 아래 years
    // 파라미터 + 카드 텍스트 후필터(신입/경력 N년)로 거른다.
    // ⚠️ location: wanted 카드 innerText 에 근무지가 안정적으로 노출되지 않아(후필터
    //    적용 시 결과 0건 over-narrow, prod 검증) location 필터는 미지원 — wanted 는
    //    전 지역 결과를 반환한다(수율 우선). jobkorea/saramin 은 정식 필터 파라미터를
    //    쓰므로 location 임베딩 유지(이 변경은 wanted 한정).
    const wKeyword = keyword;
    const wParams = new URLSearchParams({ query: wKeyword, tab: 'position' });
    if (career === 'entry') wParams.set('years', '0'); // 신입만 명시
    const url = `https://www.wanted.co.kr/search?${wParams.toString()}`;

    try {
      const page = await getPage();
      // 원티드 SPA 트래커가 계속 폴링해 networkidle 도달이 어려움 → domcontentloaded + 카드 셀렉터 대기.
      const _resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 25000 });
      lastStatus = _resp?.status() || 0;
      // state: 'attached' — Wanted 카드는 viewport 밖 lazy-render라 기본값 'visible'은 timeout.
      // try-catch — 검색 결과 0건이면 카드가 안 나타나므로 정상 케이스로 처리, 5초 단축.
      try {
        await page.waitForSelector('a[href*="/wd/"]', { state: 'attached', timeout: 5000 });
      } catch {
        // 0건 — 무한스크롤/추출 단계로 진행하면 빈 배열 반환.
      }

      // 무한스크롤 — scrollHeight 변화 없으면 조기 종료 (최대 5회).
      // 카드가 아예 없으면 (0건 케이스) 스크롤 건너뜀.
      await page.evaluate(async () => {
        if (document.querySelectorAll('a[href*="/wd/"]').length === 0) return;
        let prevHeight = 0;
        let stableCount = 0;
        for (let i = 0; i < 5; i++) {
          window.scrollTo(0, document.body.scrollHeight);
          await new Promise(r => setTimeout(r, 800));
          const h = document.body.scrollHeight;
          if (h === prevHeight) {
            if (++stableCount >= 2) break;
          } else {
            stableCount = 0;
            prevHeight = h;
          }
        }
      });

      jobs = await page.evaluate(({ lim, careerArg }) => {
        const seen = new Set();
        const results = [];

        // 검색 결과 카드만 — data-position-id가 있는 a 태그가 정상 카드.
        // Wanted SPA는 트래킹용으로 data-position-name / data-company-name 등을 카드에 심어놓음.
        // 추천/사이드바 등의 anchor는 이 attribute가 없어 자연스럽게 제외됨.
        const root = document.querySelector('main') || document;
        const cards = Array.from(root.querySelectorAll('a[href*="/wd/"][data-position-id]'));

        for (const card of cards) {
          const id = card.getAttribute('data-position-id');
          if (!id || seen.has(id)) continue;
          seen.add(id);

          const title = (card.getAttribute('data-position-name') || '').trim();
          const company = (card.getAttribute('data-company-name') || '').trim();
          if (!title || !company) continue;

          const fullText = (card.innerText || '').trim();

          // career 필터 — Wanted 검색 URL의 years 파라미터는 SPA가 무시하므로 카드 텍스트 매칭이 가장 정확.
          // 카드 텍스트 예: "...경력 5-12년합격보상금 100만원" / "...신입-경력 3년..."
          if (careerArg === 'entry') {
            if (!/신입/.test(fullText)) continue;
          } else if (careerArg === 'experienced') {
            // '경력 N-M년' 또는 '경력 N년' — N >= 1이면 experienced 대상.
            const em = fullText.match(/경력\s*(\d+)/);
            if (!em || parseInt(em[1], 10) < 1) continue;
          }

          // 마감일 추출 — D-day / D-N / 상시채용 / 채용시 라벨 탐색, 없으면 미확인 폴백.
          let deadline = '마감일 미확인';
          if (/D-?day|오늘\s?마감/.test(fullText)) {
            deadline = '오늘 마감!';
          } else {
            const dMatch = fullText.match(/D-(\d+)/);
            if (dMatch) deadline = `${dMatch[1]}일 후 마감`;
            else if (fullText.includes('상시채용')) deadline = '상시채용';
            else if (fullText.includes('채용시')) deadline = '채용시마감';
          }

          const tagEls = Array.from(
            card.querySelectorAll('[class*="tag"] span, [class*="skill"] span, [class*="badge"] span, [class*="chip"] span')
          ).filter(el => {
            const t = el.innerText.trim();
            return t && t.length > 0 && t.length < 30 && !/D-\d|마감|상시|경력|신입|\d+년/.test(t);
          });
          const skills = tagEls.map(el => el.innerText.trim()).slice(0, 8).join(', ');

          results.push({
            platform: 'wanted',
            company,
            title,
            deadline,
            dRemaining: '',
            link: `https://www.wanted.co.kr/wd/${id}`,
            skills,
          });

          if (results.length >= lim) break;
        }
        return results;
      }, { lim: limit, careerArg: career });

      // 마감 검증(전수, fail-closed) — 카드 텍스트는 마감일을 거의 못 뽑고
      // (prod 실측 136/136 "마감일 미확인") 마감 공고 감지도 불가하므로,
      // detail API로 생사 판정 + deadline 을 due_time 실값으로 교체한다.
      wantedScraped = jobs.length;
      const verifyResult = await verifyWantedJobs(jobs);
      jobs = verifyResult.jobs;
    } catch (err) {
      process.stderr.write(`wanted scrape error: ${err.message}\n`);
      jobs = []; // fail-closed: 검증을 못 거친 수집분은 내보내지 않는다
    }

  } else if (platform === 'jobkorea') {
    // jobkorea redesigned with Tailwind CSS — use link-based approach
    // career: 키워드에 신입/경력 추가 (URL 파라미터 대신 키워드 임베딩)
    // location: 키워드에 지역명 추가
    let jkKeyword = career === 'entry' ? `${keyword} 신입`
      : career === 'experienced' ? `${keyword} 경력` : keyword;
    if (location && LOCATION_KO[location]) jkKeyword += ` ${LOCATION_KO[location]}`;
    const jkParams = new URLSearchParams({ stext: jkKeyword, posted: '7', ord: 'RegDate' });
    const url = `https://www.jobkorea.co.kr/Search/?${jkParams.toString()}`;
    try {
      const page = await getPage();
      const _resp = await page.goto(url, { waitUntil: 'networkidle', timeout: 25000 });
      lastStatus = _resp?.status() || 0;
      await page.waitForTimeout(3000);

      jobs = await page.evaluate((lim) => {
        const seen = new Set();
        const results = [];

        // Find all anchor links to job detail pages (title links have text)
        const titleLinks = Array.from(document.querySelectorAll('a[href*="/Recruit/GI_Read/"]'))
          .filter(a => a.innerText?.trim().length > 3);

        for (const titleLink of titleLinks) {
          const baseHref = titleLink.href.split('?')[0];
          if (seen.has(baseHref)) continue;
          seen.add(baseHref);

          // Walk up to find the card container that has deadline info
          let card = titleLink.parentElement;
          for (let i = 0; i < 6; i++) {
            if (!card) break;
            const txt = card.innerText || '';
            if (txt.includes('마감') || txt.includes('채용') || txt.includes('등록')) break;
            card = card.parentElement;
          }

          const fullText = card?.innerText || '';

          // Extract company name — try CSS selector first, then text heuristic
          const companySpan = card?.querySelector('span a[href*="/company/"], span a[href*="/corp/"]');
          let companyText = companySpan?.innerText?.trim() || '';
          if (!companyText) {
            // Heuristic: title is in the link text, company is usually the line after it in the card
            const lines = fullText.split('\n').map(l => l.trim()).filter(Boolean);
            const titleIdx = lines.findIndex(l => l === titleLink.innerText.trim());
            if (titleIdx >= 0 && titleIdx + 1 < lines.length) {
              const candidate = lines[titleIdx + 1];
              // Company names are short and don't contain slashes or Korean location suffixes
              if (candidate.length < 40 && !candidate.includes('/') && !candidate.includes('마감')) {
                companyText = candidate;
              }
            }
          }

          // Extract deadline from text: "MM/DD(요일) 마감" or "상시채용"
          const dMatch = fullText.match(/(\d{2})\/(\d{2})\([월화수목금토일]\)\s*마감/);
          const deadline = dMatch ? dMatch[0]
            : fullText.includes('상시채용') ? '상시채용'
            : fullText.includes('채용시') ? '채용시마감'
            : '마감일 미확인';

          const tagEls = card?.querySelectorAll('[class*="tag"] span, [class*="chip"] span, [class*="skill"] span, [class*="badge"] span') || [];
          const skills = Array.from(tagEls)
            .map(el => el.innerText.trim())
            .filter(s => s && s.length > 0 && s.length < 30 && !/마감|채용|모집/.test(s))
            .slice(0, 8).join(', ');

          results.push({
            platform: 'jobkorea',
            company: companyText,
            title: titleLink.innerText.trim(),
            deadline,
            dRemaining: '',
            link: baseHref,
            skills,
          });

          if (results.length >= lim) break;
        }
        return results.filter(j => j.title && j.company);
      }, limit);
    } catch (err) {
      process.stderr.write(`jobkorea scrape error: ${err.message}\n`);
    }
  }

  // 0건 수집 시 실패 원인 진단 — "차단"과 "결과 없음"을 구분해 stderr에 남긴다.
  // wanted 는 수집은 됐지만 검증에서 전량 제외된 경우가 있어(verify_outage/전부 마감)
  // 그때는 challenge/empty_result 로 오분류하지 않도록 건너뛴다(검증 진단 라인이 이미 남음).
  if (jobs.length === 0 && !(platform === 'wanted' && wantedScraped > 0)) {
    let diagHtml = lastHtml;
    // 사람인/직접 fetch 계열은 이미 확보한 HTML(lastHtml)을 쓰고, page.goto 계열(jumpit/
    // jobkorea/wanted)은 로드된 DOM을 확보한다. 사람인은 currentPage 가 null 이라 건너뛴다
    // (브라우저를 기동하지 않았으므로 — 요구사항 2).
    if (!diagHtml && currentPage) {
      try { diagHtml = await currentPage.content(); } catch { /* page 미로드 */ }
    }
    logFailure(platform, diagHtml, lastStatus);
  }
} catch (err) {
  process.stderr.write(`Error fetching ${platform}: ${err.message}\n`);
} finally {
  if (browser) await browser.close(); // 기동됐을 때만 종료 — 사람인 경로는 애초에 기동하지 않는다.
}

process.stdout.write(JSON.stringify(jobs, null, 2) + '\n');
