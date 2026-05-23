import { auth } from "@/auth";
import { getDb, jobEvents, jobs } from "@jobstack/db";
import { and, asc, eq } from "drizzle-orm";
import { NextResponse } from "next/server";

type RouteContext = { params: Promise<{ id: string }> };

export async function GET(_req: Request, context: RouteContext) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const { id } = await context.params;
  const db = getDb();

  const [job] = await db
    .select()
    .from(jobs)
    .where(and(eq(jobs.id, id), eq(jobs.userId, session.user.id)))
    .limit(1);

  if (!job) {
    return NextResponse.json({ error: "Not found" }, { status: 404 });
  }

  const events = await db
    .select({
      phase: jobEvents.phase,
      detail: jobEvents.detail,
      at: jobEvents.at,
    })
    .from(jobEvents)
    .where(eq(jobEvents.jobId, id))
    .orderBy(asc(jobEvents.at));

  return NextResponse.json({
    id: job.id,
    skillKey: job.skillKey,
    status: job.status,
    inputPayload: job.inputPayload,
    resultRef: job.resultRef,
    createdAt: job.createdAt?.toISOString() ?? null,
    events,
  });
}
