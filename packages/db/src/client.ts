import { drizzle } from "drizzle-orm/node-postgres";
import { Pool } from "pg";
import * as schema from "./schema";

/** Default matches docker-compose.yml for local dev; override in production. */
function databaseUrl(): string {
  return (
    process.env.DATABASE_URL ??
    "postgresql://postgres:postgres@127.0.0.1:5432/jobstack"
  );
}

const globalForDb = globalThis as unknown as {
  pool?: Pool;
  db?: ReturnType<typeof drizzle<typeof schema>>;
};

function getPool(): Pool {
  if (!globalForDb.pool) {
    globalForDb.pool = new Pool({ connectionString: databaseUrl() });
  }
  return globalForDb.pool;
}

export function getDb() {
  if (!globalForDb.db) {
    globalForDb.db = drizzle(getPool(), { schema });
  }
  return globalForDb.db;
}

export type Db = ReturnType<typeof getDb>;
