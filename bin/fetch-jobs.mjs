#!/usr/bin/env node
/**
 * Playwright-based job listing fetcher for JS-rendered platforms.
 * Usage: node fetch-jobs.mjs <platform> <keyword> [limit]
 * Platform: jumpit | programmers
 * Outputs JSON array to stdout.
 *
 * Note: saramin uses server-side rendering → use curl/WebFetch directly
 */

import { chromium } from 'playwright';

const [, , platform, keyword, limitArg] = process.argv;
const limit = parseInt(limitArg || '20', 10);

if (!platform || !keyword) {
  process.stderr.write('Usage: fetch-jobs.mjs <platform> <keyword> [limit]\n');
  process.exit(1);
}

const PLATFORMS = ['jumpit', 'programmers'];
if (!PLATFORMS.includes(platform)) {
  process.stderr.write(`Unknown platform: ${platform}. Supported: ${PLATFORMS.join(', ')}\n`);
  process.exit(1);
}

const browser = await chromium.launch({
  headless: true,
  args: ['--no-sandbox', '--disable-dev-shm-usage'],
});

const context = await browser.newContext({
  userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
  locale: 'ko-KR',
});

const page = await context.newPage();
let jobs = [];

try {
  if (platform === 'jumpit') {
    const url = `https://jumpit.saramin.co.kr/search?sort=rsp_rate&keyword=${encodeURIComponent(keyword)}`;
    await page.goto(url, { waitUntil: 'commit', timeout: 15000 });
    // Wait for React hydration
    await page.waitForTimeout(5000);

    jobs = await page.evaluate((lim) => {
      const links = Array.from(document.querySelectorAll('a[href*="/position/"]'));
      return links.slice(0, lim).map(a => {
        // title attr has clean job title (without span tags)
        const rawTitle = a.getAttribute('title') || '';
        // Remove residual <span> tags from title
        const title = rawTitle.replace(/<[^>]+>/g, '').trim();

        const lines = a.innerText.split('\n').map(l => l.trim()).filter(Boolean);
        // lines[0] = "D-7" / "D-day" / "상시채용"
        // lines[1] = company
        const dLine = lines[0] || '';
        const company = lines[1] || '';

        // Compute deadline label
        let deadline = '마감일 미확인';
        if (dLine === 'D-day') deadline = '오늘 마감!';
        else if (dLine.startsWith('D-')) deadline = `${dLine.replace('D-', '')}일 후 마감`;
        else if (dLine === '상시채용') deadline = '상시채용';

        return {
          platform: 'jumpit',
          company,
          title,
          deadline,
          dRemaining: dLine, // raw value e.g. "D-7"
          link: a.href,
        };
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
  }
} catch (err) {
  process.stderr.write(`Error fetching ${platform}: ${err.message}\n`);
} finally {
  await browser.close();
}

process.stdout.write(JSON.stringify(jobs, null, 2) + '\n');
