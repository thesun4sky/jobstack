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
        return { platform: 'jumpit', company, title, deadline, dRemaining: dLine, link: a.href };
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
          };
        }).filter(j => j.title && j.company);
      }, limit);
    } catch (err) {
      process.stderr.write(`saramin scrape error: ${err.message}\n`);
    }

  } else if (platform === 'wanted') {
    // career → years 매핑 (URL 파라미터로 사용)
    let yearsParam = '-1';
    if (career === 'entry') yearsParam = '0';
    else if (career === 'experienced') yearsParam = '1';

    // 원티드는 검색 페이지의 직군 탭(/search?query=...&tab=position) 사용.
    // 지역 필터는 jumpit/jobkorea와 동일하게 키워드 임베딩 방식.
    let wKeyword = keyword;
    if (location && LOCATION_KO[location]) wKeyword += ` ${LOCATION_KO[location]}`;
    const wParams = new URLSearchParams({ query: wKeyword, tab: 'position' });
    if (yearsParam !== '-1') wParams.set('years', yearsParam);
    const url = `https://www.wanted.co.kr/search?${wParams.toString()}`;

    try {
      await page.goto(url, { waitUntil: 'networkidle', timeout: 25000 });
      await page.waitForTimeout(3000);

      // 무한스크롤 트리거 — 카드를 더 로드
      await page.evaluate(async () => {
        for (let i = 0; i < 3; i++) {
          window.scrollTo(0, document.body.scrollHeight);
          await new Promise(r => setTimeout(r, 800));
        }
      });
      await page.waitForTimeout(1000);

      jobs = await page.evaluate((lim) => {
        const seen = new Set();
        const results = [];

        // /wd/{id} 형식 채용공고 카드 링크
        const cards = Array.from(document.querySelectorAll('a[href*="/wd/"]'));

        for (const card of cards) {
          const m = card.href.match(/\/wd\/(\d+)/);
          if (!m) continue;
          const id = m[1];
          if (seen.has(id)) continue;
          seen.add(id);

          // 카드 내부 텍스트 — 보통 [직무명, 회사명, 지역, 응답률...] 순서
          const fullText = (card.innerText || '').trim();
          const lines = fullText.split('\n').map(l => l.trim()).filter(Boolean);
          if (lines.length < 2) continue;

          const title = lines[0];
          const company = lines[1];
          if (!title || !company) continue;
          if (title.length < 2 || company.length < 2) continue;

          results.push({
            platform: 'wanted',
            company,
            title,
            deadline: '상시채용',
            dRemaining: '',
            link: `https://www.wanted.co.kr/wd/${id}`,
          });

          if (results.length >= lim) break;
        }
        return results;
      }, limit);
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

          results.push({
            platform: 'jobkorea',
            company: companyText,
            title: titleLink.innerText.trim(),
            deadline,
            dRemaining: '',
            link: baseHref,
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
