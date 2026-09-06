/**
 * lockfile.mjs — 상태 파일 읽기-수정-쓰기 구간의 프로세스 간 잠금 (PR #17 리뷰 반영, PR #18 리뷰 보강).
 *
 * jobstack-exp.mjs·jobstack-defense-map.mjs 는 "파일 전체 읽기 → 수정 → 임시 파일 + rename" 으로
 * 쓰는데, 잠금 없이는 동시에 실행된 두 프로세스가 서로의 변경을 덮어써 카드가 조용히 유실된다
 * (병렬 add 20건 → 3장만 남는 재현). 외부 의존성 없이 `O_EXCL` 로 만든 `<대상>.lock` 파일을
 * 잠금으로 쓴다. 잠금 파일에는 소유자 `{pid, started_at}` 를 적어 두고, 오래된 잠금(staleMs 초과)은
 * 소유 프로세스가 죽었을 때만 치운다 — 살아 있는 프로세스(긴 임계 구역·디버거 중단)의 잠금은
 * 훔치지 않고 timeoutMs 까지 기다린 뒤 오류로 안내한다.
 *
 * withLock(targetPath, fn, { timeoutMs, staleMs = 30000 }) → fn() 의 반환값
 *   timeoutMs 기본값은 환경변수 JOBSTACK_LOCK_TIMEOUT_MS, 없으면 10000.
 *   잠금을 얻지 못하면 code = 'JOBSTACK_LOCK_TIMEOUT' 인 Error 를 던진다(호출자가 die 로 바꿔 exit 1).
 */
import { closeSync, mkdirSync, openSync, readFileSync, statSync, unlinkSync, writeSync } from 'node:fs';
import { dirname } from 'node:path';

export const LOCK_TIMEOUT_CODE = 'JOBSTACK_LOCK_TIMEOUT';

const sleepSync = (ms) => {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
};

// 잠금 파일의 소유자 정보 — 구 형식(내용 없음)이거나 깨졌으면 null
function lockOwner(lockPath) {
  try {
    const o = JSON.parse(readFileSync(lockPath, 'utf8'));
    return Number.isInteger(o?.pid) && o.pid > 0 ? o : null;
  } catch {
    return null;
  }
}

// pid 생존 확인 — 신호 0 은 보내지 않고 존재만 검사한다. EPERM 은 살아 있지만 남의 프로세스
function isAlive(pid) {
  try {
    process.kill(pid, 0);
    return true;
  } catch (e) {
    return e.code === 'EPERM';
  }
}

export function withLock(targetPath, fn, { timeoutMs, staleMs = 30000 } = {}) {
  const timeout = timeoutMs ?? (Number(process.env.JOBSTACK_LOCK_TIMEOUT_MS) || 10000);
  const lockPath = `${targetPath}.lock`;
  mkdirSync(dirname(lockPath), { recursive: true, mode: 0o700 }); // 상태 디렉토리는 소유자 전용(PR #18 재리뷰)
  const started = Date.now();
  let fd = -1;
  for (;;) {
    try {
      fd = openSync(lockPath, 'wx', 0o600); // 잠금 파일도 소유자 전용
      break;
    } catch (e) {
      if (e.code !== 'EEXIST') throw e;
      try {
        if (Date.now() - statSync(lockPath).mtimeMs > staleMs) {
          const owner = lockOwner(lockPath);
          if (!owner || !isAlive(owner.pid)) {
            unlinkSync(lockPath); // 죽은 프로세스(또는 소유자 정보 없는 구 형식)의 잔여 잠금
            continue;
          }
          // 소유 프로세스가 살아 있으면 훔치지 않는다 — 아래에서 timeout 까지 기다린다
        }
      } catch {
        // 그 사이 다른 프로세스가 지웠으면 다음 루프에서 다시 시도
      }
      if (Date.now() - started > timeout) {
        const owner = lockOwner(lockPath);
        const who = owner
          ? `소유자 pid ${owner.pid}${owner.started_at ? `, ${owner.started_at} 시작` : ''}`
          : '소유자 정보 없음';
        const err = new Error(
          `잠금 대기 시간 초과(${timeout}ms): ${lockPath} (${who}) — 다른 jobstack 프로세스가 같은 파일을 쓰고 있습니다. `
          + '그 프로세스가 끝난 뒤 다시 실행하고, 살아 있는 프로세스가 없는데도 반복되면 잠금 파일을 지우세요',
        );
        err.code = LOCK_TIMEOUT_CODE;
        throw err;
      }
      sleepSync(15 + Math.floor(Math.random() * 30));
    }
  }
  try {
    writeSync(fd, JSON.stringify({ pid: process.pid, started_at: new Date().toISOString() }));
  } catch {
    // 소유자 정보를 못 적어도 잠금 자체는 유효하다(구 형식으로 취급됨)
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
