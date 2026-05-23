import { getDb, jobEvents, jobs } from "@jobstack/db";
import { eq } from "drizzle-orm";

/**
 * PR-C: server-side tracker skill execution (stub).
 * Queued → running → succeeded with job_events rows.
 * Phase 1 MVP: this runs in-process after the API creates a queued job.
 * It is not durable on serverless/runtime shutdown; Phase 2 should move
 * execution to a real queue/worker before supporting critical or long jobs.
 */
export function enqueueTrackerJob(jobId: string): void {
  void runTrackerJob(jobId).catch(async (err: unknown) => {
    const db = getDb();
    const message = err instanceof Error ? err.message : String(err);
    await db
      .update(jobs)
      .set({
        status: "failed",
        resultRef: { error: message },
      })
      .where(eq(jobs.id, jobId));
    await db.insert(jobEvents).values({
      jobId,
      phase: "failed",
      detail: { error: message },
      at: new Date(),
    });
  });
}

async function runTrackerJob(jobId: string): Promise<void> {
  const db = getDb();

  await db.update(jobs).set({ status: "running" }).where(eq(jobs.id, jobId));
  await db.insert(jobEvents).values({
    jobId,
    phase: "running",
    detail: {},
    at: new Date(),
  });

  await new Promise((r) => setTimeout(r, 50));

  const resultRef = {
    kind: "tracker.stub",
    message: "JobStack tracker job finished (PR-C stub).",
  };
  await db
    .update(jobs)
    .set({ status: "succeeded", resultRef })
    .where(eq(jobs.id, jobId));
  await db.insert(jobEvents).values({
    jobId,
    phase: "succeeded",
    detail: resultRef,
    at: new Date(),
  });
}
