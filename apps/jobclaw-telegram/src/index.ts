import { config } from "./config.js";
import { createBot } from "./bot.js";
import { UserRegistry } from "./user-registry.js";

const registry = new UserRegistry(config.userRegistryPath);
await registry.load();

const bot = createBot(registry);
await bot.start();
console.log("[jobclaw-telegram] polling started");
