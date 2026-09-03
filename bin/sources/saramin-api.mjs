#!/usr/bin/env node
/**
 * saramin-api.mjs — 사람인 오픈API(job-search) 클라이언트(U-12 ③ — 공식 API 우선,
 * 실패 시 호출측이 현행 스크래핑으로 폴백).
 *
 * 공식 문서: https://oapi.saramin.co.kr/guide/job-search (이용 신청·승인제).
 * 이 샌드박스의 네트워크 프록시가 oapi.saramin.co.kr·api.saramin.co.kr 을 막아
 * (EGRESS_BLOCKED) 문서 원문을 이 자리에서 직접 대조하지 못했다. 아래 파라미터·응답
 * 필드명은 사람인과 무관한 다수의 공개 구현체(GitHub 코드 검색으로 대조, 2026-09
 * 확인 — jobstack 저장소 자신은 제외)에서 일관되게 쓰이는 값으로 채택했다. **실제
 * 계약(특히 exp_cd 의 "경력무관" 코드·복수값 콤마결합 지원 여부)은 승인받은 키로
 * 공식 문서와 재대조 필요** — 아래 상수 표의 주석 참조.
 *
 * 실패 규약: is-fetch-adapter.mjs 와 동일하게 throw 하지 않고 null 을 돌려준다.
 * 호출측(fetch-jobs.mjs 통합 시)은 null 을 "이 경로 사용 불가" 신호로 받아 현행
 * 스크래핑 경로로 폴백한다.
 */
import { spawnSync } from 'node:child_process';

const ENDPOINT = 'https://oapi.saramin.co.kr/job-search';

// 하루 500회 제한(이용 신청·승인제) — https://oapi.saramin.co.kr/guide/info 공지.
// 이 모듈 자체는 호출 횟수를 세지 않는다. fetch-jobs.mjs 통합 시 jobstack-config
// 상태 파일에 일별 카운터를 두고, 이 함수를 부르기 "전에" 상한을 걸러야 한다.
export const SARAMIN_DAILY_LIMIT = 500;

// 경력코드(exp_cd) — 공식 문서 원문 대조 불가(위 헤더 참조). 사람인과 무관한 다수의
// 공개 구현체가 exp_cd=1(신입)·exp_cd=2(경력)를 일관되게 쓴다.
// ⚠ 공식 문서로 확인 필요: "경력무관"(0 으로 추정, 미검증), 신입+경력 동시 지정 시
// 콤마결합("1,2") 지원 여부, exp_min/exp_max(연차 범위)와의 상호작용은 미검증이다.
const SARAMIN_EXP_CD = {
  entry: '1', // 신입
  experienced: '2', // 경력
};

// 참고: job_type 은 "고용형태"(정규직=1·계약직=2·인턴직=4 등) 코드로, 경력(exp_cd)과는
// 다른 별개 파라미터다. fetch-jobs.mjs 의 career 인자(entry|experienced)는 경력 구분을
// 뜻하므로 job_type 이 아니라 exp_cd 에 매핑한다. exp_lv 라는 이름의 파라미터는 대조한
// 어떤 공개 구현체에서도 확인되지 않았다.
export const SARAMIN_JOB_TYPE_NOTE =
  'job_type 은 고용형태 코드(정규직=1 등)이며 경력(exp_cd)과 별개 필드다 — 공식 문서로 확인 필요';

// 지역코드(loc_cd) — fetch-jobs.mjs 의 SARAMIN_LOC_CD 표를 그대로 복제(가나다 순).
export const SARAMIN_LOC_CD = {
  seoul: '101000', gyeonggi: '102000', gwangju: '103000', daegu: '104000',
  daejeon: '105000', busan: '106000', ulsan: '107000', incheon: '108000',
};

const TIMEOUT_MS = 10000;

/**
 * `expiration-timestamp`(초 단위 Unix epoch) 를 KST(UTC+9) 기준 YYYY-MM-DD 문자열로 변환.
 * Intl/타임존 데이터베이스 의존을 피하려고 UTC 계산에 9시간을 더하는 방식을 쓴다.
 * @returns {string|null} 유효하지 않은 입력(누락·0·비수치)이면 null.
 */
function epochSecondsToKstDate(epochSeconds) {
  const n = Number(epochSeconds);
  if (!Number.isFinite(n) || n <= 0) return null;
  const kst = new Date(n * 1000 + 9 * 60 * 60 * 1000);
  const y = kst.getUTCFullYear();
  const m = String(kst.getUTCMonth() + 1).padStart(2, '0');
  const d = String(kst.getUTCDate()).padStart(2, '0');
  return `${y}-${m}-${d}`;
}

/**
 * `jobstack-config get saramin_api_key` 로 저장된 사람인 오픈API 키를 읽는다.
 * @param {string} configBin `jobstack-config` 실행 파일 경로
 * @param {{spawn?: typeof spawnSync}} [opts] 테스트용 spawn 주입(기본은 실제 spawnSync)
 * @returns {string} 키 문자열, 또는 미설정·실행 실패 시 빈 문자열
 */
export function readSaraminKey(configBin, opts = {}) {
  const { spawn = spawnSync } = opts;
  try {
    const res = spawn(configBin, ['get', 'saramin_api_key'], { encoding: 'utf8' });
    if (!res || res.status !== 0 || !res.stdout) return '';
    return res.stdout.trim();
  } catch {
    return '';
  }
}

/**
 * 사람인 오픈API로 채용공고를 검색한다. fetch-jobs.mjs 의 스크래핑 파서와 같은
 * 객체 형태를 돌려준다.
 *
 * @param {object} params
 * @param {string} params.accessKey 사람인 오픈API 발급키 — 빈 값이면 네트워크 호출 없이 null.
 * @param {string} params.keyword 검색 키워드(공백으로 여러 단어 결합 가능 — 사람인 규약).
 * @param {number} [params.limit=20] 요청 건수(count 파라미터).
 * @param {'entry'|'experienced'|string} [params.career] 경력 구분 — SARAMIN_EXP_CD 에
 *   있는 값만 exp_cd 로 매핑되고, 그 외 값은 무시(전체 검색)된다.
 * @param {string} [params.location] fetch-jobs.mjs 의 LOCATION_KEYS 값(seoul 등).
 * @param {object} [opts]
 * @param {typeof fetch} [opts.fetchImpl=globalThis.fetch] 테스트용 fetch 주입.
 * @param {Date} [opts.now=new Date()] 예약 파라미터 — 응답의 expiration-timestamp 는
 *   절대 epoch 이라 현재는 now 를 쓰지 않지만, is-fetch-adapter.mjs 류 다른 소스와
 *   시그니처를 맞추고 향후 상대 표기(D-day 등) 확장 여지를 남긴다.
 * @returns {Promise<Array<{platform:'saramin', company:string, title:string,
 *   deadline:string, dRemaining:string, link:string, skills:string}>|null>}
 *   실패(HTTP 오류·비JSON·키 없음·네트워크 오류·타임아웃) 시 null — throw 하지 않는다.
 */
export async function fetchSaraminApi(
  { accessKey, keyword, limit = 20, career, location },
  { fetchImpl = globalThis.fetch, now = new Date() } = {},
) {
  void now; // 현재 미사용 — 위 JSDoc 참조.
  if (!accessKey) return null; // 키 없음 — 네트워크 호출 없이 스크래핑 폴백 신호

  const params = new URLSearchParams({
    'access-key': accessKey,
    keywords: keyword || '',
    count: String(limit),
    sort: 'pd', // 게시일 최신순
  });
  if (career && SARAMIN_EXP_CD[career]) params.set('exp_cd', SARAMIN_EXP_CD[career]);
  if (location && SARAMIN_LOC_CD[location]) params.set('loc_cd', SARAMIN_LOC_CD[location]);

  const url = `${ENDPOINT}?${params.toString()}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let res;
  try {
    res = await fetchImpl(url, { signal: controller.signal });
  } catch {
    return null; // 네트워크 오류·타임아웃(abort) — 폴백
  } finally {
    clearTimeout(timer);
  }

  if (!res || !res.ok) return null; // HTTP 오류 — 폴백

  let data;
  try {
    data = await res.json();
  } catch {
    return null; // 비JSON 응답 — 폴백
  }

  const rawJobs = data?.jobs?.job;
  const list = Array.isArray(rawJobs) ? rawJobs : rawJobs ? [rawJobs] : [];

  return list
    .map((job) => ({
      platform: 'saramin',
      company: job?.company?.detail?.name || '',
      title: job?.position?.title || '',
      deadline: epochSecondsToKstDate(job?.['expiration-timestamp']) || '마감일 미확인',
      dRemaining: '',
      link: job?.url || '',
      skills: job?.position?.['job-code']?.name || '',
    }))
    .filter((j) => j.title && j.company);
}
