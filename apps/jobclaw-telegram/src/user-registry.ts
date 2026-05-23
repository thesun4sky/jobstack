import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname } from "node:path";
import type { SubscriptionTier, TelegramUserRecord } from "./types.js";

type RegistryFile = {
  users: Record<string, TelegramUserRecord>;
};

function isRegistryFile(x: unknown): x is RegistryFile {
  return (
    typeof x === "object" &&
    x !== null &&
    "users" in x &&
    typeof (x as RegistryFile).users === "object"
  );
}

export class UserRegistry {
  private readonly path: string;
  private cache: Map<number, TelegramUserRecord> = new Map();
  private loaded = false;

  constructor(registryFilePath: string) {
    this.path = registryFilePath;
  }

  async load(): Promise<void> {
    if (this.loaded) return;
    try {
      const raw = await readFile(this.path, "utf8");
      const parsed: unknown = JSON.parse(raw);
      if (!isRegistryFile(parsed)) {
        this.loaded = true;
        return;
      }
      for (const [k, v] of Object.entries(parsed.users)) {
        const id = Number.parseInt(k, 10);
        if (!Number.isNaN(id)) this.cache.set(id, v);
      }
    } catch (e: unknown) {
      const err = e as NodeJS.ErrnoException;
      if (err.code !== "ENOENT") throw e;
    }
    this.loaded = true;
  }

  private async persist(): Promise<void> {
    await mkdir(dirname(this.path), { recursive: true });
    const users: Record<string, TelegramUserRecord> = {};
    for (const [id, rec] of this.cache) {
      users[String(id)] = rec;
    }
    const body: RegistryFile = { users };
    await writeFile(this.path, JSON.stringify(body, null, 2), "utf8");
  }

  get(telegramUserId: number): TelegramUserRecord | undefined {
    return this.cache.get(telegramUserId);
  }

  async register(input: {
    telegramUserId: number;
    subscriptionTier: SubscriptionTier;
  }): Promise<TelegramUserRecord> {
    await this.load();
    const prev = this.cache.get(input.telegramUserId);
    const rec: TelegramUserRecord = {
      telegramUserId: input.telegramUserId,
      subscriptionTier: input.subscriptionTier,
      registeredAt: prev?.registeredAt ?? new Date().toISOString(),
      activeSkillSlug: prev?.activeSkillSlug,
    };
    this.cache.set(input.telegramUserId, rec);
    await this.persist();
    return rec;
  }

  async setActiveSkill(
    telegramUserId: number,
    slug: string | undefined,
    tier: SubscriptionTier,
  ): Promise<void> {
    await this.load();
    let prev = this.cache.get(telegramUserId);
    if (!prev) {
      prev = {
        telegramUserId,
        subscriptionTier: tier,
        registeredAt: new Date().toISOString(),
      };
    }
    const next: TelegramUserRecord = { ...prev, activeSkillSlug: slug };
    this.cache.set(telegramUserId, next);
    await this.persist();
  }
}
