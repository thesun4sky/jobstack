CREATE TABLE "job_event" (
	"id" text PRIMARY KEY NOT NULL,
	"jobId" text NOT NULL,
	"phase" text NOT NULL,
	"detail" jsonb NOT NULL,
	"at" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "job" (
	"id" text PRIMARY KEY NOT NULL,
	"userId" text NOT NULL,
	"skillKey" text NOT NULL,
	"status" text NOT NULL,
	"inputPayload" jsonb NOT NULL,
	"resultRef" jsonb,
	"createdAt" timestamp DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "job_event" ADD CONSTRAINT "job_event_jobId_job_id_fk" FOREIGN KEY ("jobId") REFERENCES "public"."job"("id") ON DELETE cascade ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "job" ADD CONSTRAINT "job_userId_user_id_fk" FOREIGN KEY ("userId") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;