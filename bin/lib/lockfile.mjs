/**
 * lockfile.mjs — 상태 파일 읽기-수정-쓰기 구간의 프로세스 간 잠금 (PR #17 리뷰 반영).
 *
 * jobstack-exp.mjs·jobstack-defense-map.mjs 는 "파일 전체 읽기 → 수정 → 임시 파일 + rename" 으로
 * 쓰는데, 잠금 없이는 동시에 실행된 두 프로세스가 서로의 변경을 덮어써 카드가 조용히 유실된다
 * (병렬 add 20건 → 3장만 남는 재현). 외부 의존성 없이 `O_EXCL` 로 만든 `<대상>.lock` 파일을
 * 잠금으로 쓰고, 죽은 프로세스가 남긴 오래된 잠금(staleMs 초과)은 치운다.
 *
 * withLock(targetPath, fn, { timeoutMs = 10000, staleMs = 30000 }) → fn() 의 반환값
 *   잠금을 timeoutMs 안에 못 얻으면 Error 를 던진다(호출자가 die 로 바꿔 exit 1).
 */
import { closeSync, mkdirSync, openSync, statSync, unlinkSync } from 'node:fs';
import { dirname } from 'node:path';

const sleepSync = (ms) => {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
};

export function withLock(targetPath, fn, { timeoutMs = 10000, staleMs = 30000 } = {}) {
  const lockPath = `${targetPath}.lock`;
  mkdirSync(dirname(lockPath), { recursive: true });
  const started = Date.now();
  let fd = -1;
  for (;;) {
    try {
      fd = openSync(lockPath, 'wx');
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      try {
        if (Date.now() - statSync(lockPath).mtimeMs > staleMs) {
          unlinkSync(lockPath); // 죽은 프로세스의 잔여 잠금
          continue;
        }
      } catch {
        // 그 사이 다른 프로세스가 지웠으면 다음 루프에서 다시 시도
      }
      if (Date.now() - started > timeoutMs) {
        throw new Error(`잠금 대기 시간 초과(${timeoutMs}ms): ${lockPath} — 다른 jobstack 프로세스가 같은 파일을 쓰고 있거나 잔여 잠금입니다`);
      }
      sleepSync(15 + Math.floor(Math.random() * 30));
    }
  }
  // fn() 안에서 die() → process.exit() 로 끝나면 finally 가 돌지 않으므로 'exit' 훅으로도 잠금을
  // 치운다 — 그렇지 않으면 사용법 오류 한 번이 잔여 잠금을 남겨 다음 호출이 staleMs 까지 기다린다.
  let released = false;
  const release = () => {
    if (released) return;
    released = true;
    try { closeSync(fd); } catch { /* 무시 */ }
    try { unlinkSync(lockPath); } catch { /* 무시 */ }
  };
  process.once('exit', release);
  try {
    return fn();
  } finally {
    release();
    process.off('exit', release);
  }
}
