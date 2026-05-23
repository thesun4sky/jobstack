import {
  integer,
  jsonb,
  pgTable,
  primaryKey,
  text,
  timestamp,
  unique,
} from "drizzle-orm/pg-core";

/** Auth.js default user table (singular name matches @auth/drizzle-adapter). */
export const users = pgTable("user", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  name: text("name"),
  email: text("email").notNull(),
  emailVerified: timestamp("emailVerified", { mode: "date" }),
  image: text("image"),
});

export const accounts = pgTable(
  "account",
  {
    userId: text("userId")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    type: text("type").notNull(),
    provider: text("provider").notNull(),
    providerAccountId: text("providerAccountId").notNull(),
    refresh_token: text("refresh_token"),
    access_token: text("access_token"),
    expires_at: integer("expires_at"),
    token_type: text("token_type"),
    scope: text("scope"),
    id_token: text("id_token"),
    session_state: text("session_state"),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.provider, t.providerAccountId] }),
  }),
);

export const sessions = pgTable("session", {
  sessionToken: text("sessionToken").primaryKey(),
  userId: text("userId")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  expires: timestamp("expires", { mode: "date" }).notNull(),
});

export const verificationTokens = pgTable(
  "verificationToken",
  {
    identifier: text("identifier").notNull(),
    token: text("token").notNull(),
    expires: timestamp("expires", { mode: "date" }).notNull(),
  },
  (t) => ({
    pk: primaryKey({ columns: [t.identifier, t.token] }),
  }),
);

/** App-specific profile row keyed by Auth user id. */
export const profiles = pgTable("profile", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  userId: text("userId")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  displayName: text("displayName"),
  createdAt: timestamp("createdAt", { mode: "date" }).defaultNow(),
});

/** Long-running skill execution unit (Phase 2 PR-C). */
export const jobs = pgTable("job", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  userId: text("userId")
    .notNull()
    .references(() => users.id, { onDelete: "cascade" }),
  skillKey: text("skillKey").notNull(),
  status: text("status").notNull(),
  inputPayload: jsonb("inputPayload").$type<Record<string, unknown>>().notNull(),
  resultRef: jsonb("resultRef").$type<Record<string, unknown> | null>(),
  createdAt: timestamp("createdAt", { mode: "date" }).defaultNow().notNull(),
});

export const jobEvents = pgTable("job_event", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  jobId: text("jobId")
    .notNull()
    .references(() => jobs.id, { onDelete: "cascade" }),
  phase: text("phase").notNull(),
  detail: jsonb("detail").$type<Record<string, unknown>>().notNull(),
  at: timestamp("at", { mode: "date" }).defaultNow().notNull(),
});

/**
 * Billing subscription (Phase 3 PR-D, PortOne MVP).
 * `planKey` free | basic | pro — product entitlements and job quotas read this via getEffectivePlan().
 */
export const subscriptions = pgTable(
  "subscription",
  {
    id: text("id")
      .primaryKey()
      .$defaultFn(() => crypto.randomUUID()),
    userId: text("userId")
      .notNull()
      .references(() => users.id, { onDelete: "cascade" }),
    planKey: text("planKey").notNull(),
    status: text("status").notNull(),
    provider: text("provider").notNull(),
    /** PortOne payment id (V2) or subscription order ref (Subscription Link). */
    providerPaymentId: text("providerPaymentId"),
    /** Merchant-side idempotency key (e.g. custom order id). */
    merchantOrderRef: text("merchantOrderRef"),
    currentPeriodEnd: timestamp("currentPeriodEnd", { mode: "date" }),
    metadata: jsonb("metadata").$type<Record<string, unknown>>(),
    createdAt: timestamp("createdAt", { mode: "date" }).defaultNow().notNull(),
    updatedAt: timestamp("updatedAt", { mode: "date" }).defaultNow().notNull(),
  },
  (t) => ({
    userUnique: unique("subscription_userId_unique").on(t.userId),
  }),
);

/** Raw webhook receipts for idempotency and audit (provider-agnostic). */
export const billingWebhookEvents = pgTable("billing_webhook_event", {
  id: text("id")
    .primaryKey()
    .$defaultFn(() => crypto.randomUUID()),
  provider: text("provider").notNull(),
  /** Dedup key: e.g. payment_id:tx_id (V2) or order_ref:status (Subscription Link). */
  idempotencyKey: text("idempotencyKey").notNull().unique(),
  eventKind: text("eventKind"),
  payload: jsonb("payload").$type<Record<string, unknown>>().notNull(),
  receivedAt: timestamp("receivedAt", { mode: "date" }).defaultNow().notNull(),
  processingError: text("processingError"),
});
