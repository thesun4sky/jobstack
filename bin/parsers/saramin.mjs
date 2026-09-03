#!/usr/bin/env node
/**
 * saramin.mjs — 사람인 검색결과 HTML 파서(cheerio 기반, 브라우저 불필요).
 *
 * fetch-jobs.mjs 의 saramin 분기(page.evaluate 파서, 155~245행 부근)를 그대로 옮긴
 * 정적 버전이다. 셀렉터·마감일 규칙·절대 URL 복원·title/company 없는 카드 제외를
 * 동일하게 유지해, 반환하는 객체 배열이 브라우저 파서 결과와 같은 모양이 되게 한다
 * (U-12 ② — 사람인 파싱을 cheerio 로 이관해 브라우저 없이 동작).
 *
 * innerText 대신 cheerio 의 .text() 를 쓰므로, 정규식으로 비교하기 전에 공백(개행·
 * 연속 공백)을 한 칸으로 정리한다(normalizeWhitespace) — cheerio 는 브라우저의
 * innerText 와 달리 블록 요소 사이에 줄바꿈을 넣어주지 않기 때문이다.
 *
 * now 파라미터로 "오늘"을 주입할 수 있어 "~ MM/DD" 마감일의 연도 롤오버(올해/내년)를
 * 결정적으로 테스트할 수 있다.
 */
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);

let cheerioLoad;
try {
  ({ load: cheerioLoad } = require('cheerio'));
} catch (err) {
  // 명확한 오류 — 이 모듈을 import 하는 즉시(함수 호출 전) 던진다.
  throw new Error(
    `cheerio 모듈을 찾을 수 없습니다. bin/ 에서 npm install 을 실행하세요. (원본 오류: ${err.message})`,
  );
}

/** cheerio .text() 결과의 개행·연속 공백을 한 칸으로 정리(innerText 대체). */
function normalizeWhitespace(text) {
  return (text || '').replace(/\s+/g, ' ').trim();
}

/**
 * 사람인 검색결과 HTML을 파싱한다.
 *
 * @param {string} html 사람인 검색결과 페이지(또는 그 조각) HTML
 * @param {number} [limit=20] 반환할 최대 건수 — 원본 파서처럼 title/company 필터
 *   "이전"에 slice 한다(깨진 카드가 앞쪽에 있으면 결과가 limit 보다 적을 수 있음, 원본과 동일).
 * @param {Date} [now=new Date()] "오늘" 기준일 — "~ MM/DD" 마감일의 연도 롤오버 판정에 사용.
 * @returns {{platform:'saramin', company:string, title:string, deadline:string,
 *   dRemaining:string, link:string, skills:string}[]}
 */
export function parseSaraminSearch(html, limit = 20, now = new Date()) {
  const $ = cheerioLoad(html || '');
  const items = $('.item_recruit').toArray().slice(0, limit);

  return items
    .map((el) => {
      const $item = $(el);
      const titleEl = $item.find('.job_tit a').first();
      const companyEl = $item.find('.corp_name a').first();
      const fullText = normalizeWhitespace($item.text());
      const dateText = normalizeWhitespace($item.find('.date, .job_date').first().text());

      let deadline = '마감일 미확인';
      // "~ 06/06(토)" 형식
      const mdMatch = dateText.match(/~\s*(\d{2})\/(\d{2})/);
      // "2026.06.06" 형식
      const ymMatch = fullText.match(/(\d{4})\.(\d{2})\.(\d{2})/);
      if (mdMatch) {
        const month = parseInt(mdMatch[1], 10);
        const day = parseInt(mdMatch[2], 10);
        let year = now.getFullYear();
        // 오늘 자정 기준: 오늘 마감은 올해, 어제 이전만 내년으로 롤오버
        const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
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

      // 사람인 list page는 기술태그를 노출하지 않음(fetch-jobs.mjs 원본 주석과 동일).
      const skills = '';

      // 정적 HTML(고정 픽스처·is-fetch 확보본)에서도 절대 URL로 복원
      const href = titleEl.attr('href') || '';
      const link = href.startsWith('http') ? href : `https://www.saramin.co.kr${href}`;

      return {
        platform: 'saramin',
        company: normalizeWhitespace(companyEl.text()),
        title: normalizeWhitespace(titleEl.text()),
        deadline,
        dRemaining: '',
        link,
        skills,
      };
    })
    .filter((j) => j.title && j.company);
}
