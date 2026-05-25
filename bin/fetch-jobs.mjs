#!/usr/bin/env node
/**
 * Playwright-based job listing fetcher for JS-rendered platforms.
 * Usage: node fetch-jobs.mjs <platform> <keyword> [limit] [career] [location]
 * Platform: jumpit | jobkorea | saramin | wanted
 * Career: entry (신입) | experienced (경력) | (생략시 전체)
 * Location: seoul|gyeonggi|busan|incheon|daejeon|daegu|gwangju|remote (생략시 전체)
 * Outputs JSON array to stdout.
 */

import { chromium } from 'playwright';

const [, , platform, keyword, arg3, arg4, arg5] = process.argv;
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

// 사람인 loc_cd 매핑 (가나다 순: 광주<대구<대전<부산<서울...)
const SARAMIN_LOC_CD = {
  seoul: '101000', gyeonggi: '102000', gwangju: '103000', daegu: '104000',
  daejeon: '105000', busan: '106000', ulsan: '107000', incheon: '108000',
};
// 한국어 지역명 (키워드 임베딩용)
const LOCATION_KO = {
  seoul: '서울', gyeonggi: '경기', busan: '부산', incheon: '인천',
  daejeon: '대전', daegu: '대구', gwangju: '광주', remote: '재택근무',
};

if (!platform || !keyword) {
  process.stderr.write('Usage: fetch-jobs.mjs <platform> <keyword> [limit] [career] [location]\n');
  process.exit(1);
}

const PLATFORMS = ['jumpit', 'programmers', 'jobkorea', 'saramin', 'wanted'];
if (!PLATFORMS.includes(platform)) {
  process.stderr.write(`Unknown platform: ${platform}. Supported: ${PLATFORMS.join(', ')}\n`);
  process.exit(1);
}

// ─── Playwright-based platforms (stealth) ─────────────────────────────────────
const browser = await chromium.launch({
  headless: true,
  args: [
    '--no-sandbox',
    '--disable-dev-shm-usage',
    '--disable-blink-features=AutomationControlled',
    '--disable-infobars',
    '--window-size=1366,768',
  ],
});

const context = await browser.newContext({
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

const page = await context.newPage();
let jobs = [];

try {
  if (platform === 'jumpit') {
    // career: entry → min_career=0&max_career=0, experienced → min_career=1
    const jtParams = new URLSearchParams({ sort: 'rsp_rate', keyword });
    if (career === 'entry') { jtParams.set('min_career', '0'); jtParams.set('max_career', '0'); }
    else if (career === 'experienced') { jtParams.set('min_career', '1'); }
    // 지역 필터: 점핏은 지역명을 키워드에 포함
    if (location && LOCATION_KO[location]) jtParams.set('keyword', `${keyword} ${LOCATION_KO[location]}`);
    const url = `https://jumpit.saramin.co.kr/search?${jtParams.toString()}`;
    await page.goto(url, { waitUntil: 'commit', timeout: 15000 });
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

  } else if (platform === 'programmers') {
    const url = `https://career.programmers.co.kr/job_positions?query=${encodeURIComponent(keyword)}`;
    await page.goto(url, { waitUntil: 'commit', timeout: 15000 });
    await page.waitForTimeout(5000);

    jobs = await page.evaluate((lim) => {
      const items = document.querySelectorAll('[class*="List"] li, article, [class*="job-item"]');
      return Array.from(items).slice(0, lim).map(item => {
        const titleEl = item.querySelector('h2, h3, [class*="title"]');
        const companyEl = item.querySelector('[class*="company"]');
        const deadlineEl = item.querySelector('[class*="due"], [class*="deadline"], time');
        const link = item.querySelector('a')?.href || '';
        return {
          platform: 'programmers',
          company: companyEl?.innerText?.trim() || '',
          title: titleEl?.innerText?.trim() || '',
          deadline: deadlineEl?.innerText?.trim() || '마감일 미확인',
          link,
        };
      }).filter(j => j.title);
    }, limit);

  } else if (platform === 'saramin') {
    // page.goto()는 TLS 핑거프린팅으로 차단됨 → context.request.get()으로 HTML fetch 후 setContent 파싱
    // career: URL 파라미터 미지원 → 키워드에 신입/경력 추가
    const srKeyword = career === 'entry' ? `${keyword} 신입`
      : career === 'experienced' ? `${keyword} 경력` : keyword;
    const srParams = new URLSearchParams({ searchword: srKeyword, poster_duration: '7', sort: 'RD' });
    // 지역 필터: loc_cd 파라미터 (서울=101000, 경기=102000, ...)
    if (location && SARAMIN_LOC_CD[location]) srParams.set('loc_cd', SARAMIN_LOC_CD[location]);
    if (location === 'remote') srParams.set('searchword', `${srKeyword} 재택`);
    const url = `https://www.saramin.co.kr/zf_user/search?${srParams.toString()}`;
    try {
      const resp = await context.request.get(url, {
        timeout: 15000,
        headers: { 'Accept-Language': 'ko-KR,ko;q=0.9' },
      });
      if (!resp.ok()) throw new Error(`HTTP ${resp.status()}`);
      const html = await resp.text();
      await page.setContent(html, { waitUntil: 'domcontentloaded', timeout: 10000 });

      jobs = await page.evaluate((lim) => {
        const items = Array.from(document.querySelectorAll('.item_recruit'));
        return items.slice(0, lim).map(item => {
          const titleEl = item.querySelector('.job_tit a');
          const companyEl = item.querySelector('.corp_name a');
          const fullText = item.innerText || '';
          const dateText = item.querySelector('.date, .job_date')?.innerText?.trim() || '';

          let deadline = '마감일 미확인';
          // "~ 06/06(토)" 형식
          const mdMatch = dateText.match(/~\s*(\d{2})\/(\d{2})/);
          // "2026.06.06" 형식
          const ymMatch = fullText.match(/(\d{4})\.(\d{2})\.(\d{2})/);
          if (mdMatch) {
            const month = parseInt(mdMatch[1], 10);
            const day = parseInt(mdMatch[2], 10);
            let year = new Date().getFullYear();
            // 오늘 자정 기준: 오늘 마감은 올해, 어제 이전만 내년으로 롤오버
            const today = new Date(); today.setHours(0, 0, 0, 0);
            const parsed = new Date(year, month - 1, day);
            if (parsed < today) year++;
            deadline = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
          } else if (ymMatch) {
            deadline = `${ymMatch[1]}-${ymMatch[2]}-${ymMatch[3]}`;
          } else if (fullText.includes('상시채용') || dateText.includes('상시채용')) {
            deadline = '상시채용';
          } else if (fullText.includes('채용시')) {
            deadline = '채용시마감';
          }

          // 사람인 list page는 기술태그를 노출하지 않음.
          // .job_sector는 날짜/등록일 텍스트 → 빈 문자열 반환.
          const skills = '';

          // setContent로 로드된 경우 절대 URL로 복원
          const href = titleEl?.getAttribute('href') || '';
          const link = href.startsWith('http') ? href : `https://www.saramin.co.kr${href}`;
          return {
            platform: 'saramin',
            company: companyEl?.innerText?.trim() || '',
            title: titleEl?.innerText?.trim() || '',
            deadline,
            dRemaining: '',
            link,
            skills,
          };
        }).filter(j => j.title && j.company);
      }, limit);
    } catch (err) {
      process.stderr.write(`saramin scrape error: ${err.message}\n`);
    }

  } else if (platform === 'wanted') {
    // career → 키워드 임베딩 (jobkorea/saramin과 일관).
    // years 파라미터는 연차 단위로 추정되어 experienced일 때 생략 — 1년차만 잡히는 누락 방지.
    let wKeyword = career === 'entry' ? `${keyword} 신입`
      : career === 'experienced' ? `${keyword} 경력` : keyword;
    if (location && LOCATION_KO[location]) wKeyword += ` ${LOCATION_KO[location]}`;
    const wParams = new URLSearchParams({ query: wKeyword, tab: 'position' });
    if (career === 'entry') wParams.set('years', '0'); // 신입만 명시
    const url = `https://www.wanted.co.kr/search?${wParams.toString()}`;

    try {
      // 원티드 SPA 트래커가 계속 폴링해 networkidle 도달이 어려움 → domcontentloaded + 카드 셀렉터 대기.
      await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 25000 });
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
    } catch (err) {
      process.stderr.write(`wanted scrape error: ${err.message}\n`);
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
      await page.goto(url, { waitUntil: 'networkidle', timeout: 25000 });
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
} catch (err) {
  process.stderr.write(`Error fetching ${platform}: ${err.message}\n`);
} finally {
  await browser.close();
}

process.stdout.write(JSON.stringify(jobs, null, 2) + '\n');
