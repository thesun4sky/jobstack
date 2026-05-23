CREATE TABLE "billing_webhook_event" (
	"id" text PRIMARY KEY NOT NULL,
	"provider" text NOT NULL,
	"idempotencyKey" text NOT NULL,
	"eventKind" text,
	"payload" jsonb NOT NULL,
	"receivedAt" timestamp DEFAULT now() NOT NULL,
	"processingError" text,
	CONSTRAINT "billing_webhook_event_idempotencyKey_unique" UNIQUE("idempotencyKey")
);
--> statement-breakpoint
CREATE TABLE "subscription" (
	"id" text PRIMARY KEY NOT NULL,
	"userId" text NOT NULL,
	"planKey" text NOT NULL,
	"status" text NOT NULL,
	"provider" text NOT NULL,
	"providerPaymentId" text,
	"merchantOrderRef" text,
	"currentPeriodEnd" timestamp,
	"metadata" jsonb,
	"createdAt" timestamp DEFAULT now() NOT NULL,
	"updatedAt" timestamp DEFAULT now() NOT NULL,
	CONSTRAINT "subscription_userId_unique" UNIQUE("userId")
);
--> statement-breakpoint
ALTER TABLE "subscription" ADD CONSTRAINT "subscription_userId_user_id_fk" FOREIGN KEY ("userId") REFERENCES "public"."user"("id") ON DELETE cascade ON UPDATE no action;