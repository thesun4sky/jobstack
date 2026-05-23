import { auth } from "@/auth";
import { enqueueTrackerJob } from "@/lib/jobs/run-tracker-job";
import { getDb, jobEvents, jobs } from "@jobstack/db";
import { desc, eq } from "drizzle-orm";
import { NextResponse } from "next/server";

const ALLOWED_SKILL = "tracker";

type PostBody = {
  skillKey?: string;
  input?: Record<string, unknown>;
};

/** List current user's jobs (newest first). Query: limit (1–100, default 20), offset (≥0, default 0). */
export async function GET(req: Request) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  const url = new URL(req.url);
  let limit = Number.parseInt(url.searchParams.get("limit") ?? "20", 10);
  let offset = Number.parseInt(url.searchParams.get("offset") ?? "0", 10);
  if (Number.isNaN(limit) || limit < 1) limit = 20;
  if (limit > 100) limit = 100;
  if (Number.isNaN(offset) || offset < 0) offset = 0;

  const db = getDb();
  const rows = await db
    .select({
      id: jobs.id,
      skillKey: jobs.skillKey,
      status: jobs.status,
      createdAt: jobs.createdAt,
    })
    .from(jobs)
    .where(eq(jobs.userId, session.user.id))
    .orderBy(desc(jobs.createdAt))
    .limit(limit)
    .offset(offset);

  return NextResponse.json({
    items: rows.map((r) => ({
      id: r.id,
      skillKey: r.skillKey,
      status: r.status,
      createdAt: r.createdAt?.toISOString() ?? null,
    })),
    limit,
    offset,
  });
}

export async function POST(req: Request) {
  const session = await auth();
  if (!session?.user?.id) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 401 });
  }

  let body: PostBody;
  try {
    body = (await req.json()) as PostBody;
  } catch {
    return NextResponse.json({ error: "Invalid JSON body" }, { status: 400 });
  }

  const skillKey = body.skillKey?.trim();
  if (skillKey !== ALLOWED_SKILL) {
    return NextResponse.json(
      {
        error: "Unsupported skillKey",
        detail: `Only "${ALLOWED_SKILL}" is supported in PR-C.`,
      },
      { status: 400 },
    );
  }

  const inputPayload = body.input ?? {};
  if (JSON.stringify(inputPayload).length > 8_000) {
    return NextResponse.json({ error: "input payload too large (max 8 KB)" }, { status: 400 });
  }
  const db = getDb();
  const [row] = await db
    .insert(jobs)
    .values({
      userId: session.user.id,
      skillKey: ALLOWED_SKILL,
      status: "queued",
      inputPayload,
    })
    .returning({ id: jobs.id });

  if (!row) {
    return NextResponse.json({ error: "Failed to create job" }, { status: 500 });
  }

  await db.insert(jobEvents).values({
    jobId: row.id,
    phase: "queued",
    detail: { input: inputPayload },
    at: new Date(),
  });

  enqueueTrackerJob(row.id);

  return NextResponse.json({ jobId: row.id }, { status: 202 });
}
