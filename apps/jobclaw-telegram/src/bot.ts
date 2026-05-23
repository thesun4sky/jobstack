import { Bot, GrammyError, HttpError } from "grammy";
import { config } from "./config.js";
import { chunkMessage, escapeMarkdownV2 } from "./format/telegram.js";
import { callbackTokens, mainMenuKeyboard } from "./keyboards.js";
import { evaluateSubscription } from "./subscription.js";
import { SKILL_MENU } from "./skills-catalog.js";
import { ensureSession, getSession, setActiveSkill } from "./session-state.js";
import type { UserRegistry } from "./user-registry.js";
import { runClaudeCliBridge } from "./claude-bridge.js";

function skillTitle(slug: string): string {
  return SKILL_MENU.find((s) => s.slug === slug)?.title ?? slug;
}

export function createBot(registry: UserRegistry): Bot {
  const bot = new Bot(config.telegramBotToken);

  bot.command("start", async (ctx) => {
    const uid = ctx.from?.id;
    if (uid === undefined) return;
    const sub = evaluateSubscription(uid);
    if (!sub.ok) {
      await ctx.reply(
        [
          "안녕하세요. JobClaw(JobStack) 봇입니다.",
          "",
          sub.reason,
          "",
          `웹앱: ${config.jobstackWebUrl}`,
        ].join("\n"),
      );
      return;
    }
    await registry.register({
      telegramUserId: uid,
      subscriptionTier: sub.tier,
    });
    ensureSession(uid, sub.tier);
    await ctx.reply(
      [
        "등록되었습니다.",
        `플랜: ${sub.tier}`,
        "",
        "아래에서 스킬을 고른 뒤 메시지를 보내면 Claude CLI 브릿지로 전달됩니다 (로컬에 CLI가 있을 때).",
      ].join("\n"),
      { reply_markup: mainMenuKeyboard() },
    );
  });

  bot.command("menu", async (ctx) => {
    const uid = ctx.from?.id;
    if (uid === undefined) return;
    const sub = evaluateSubscription(uid);
    if (!sub.ok) {
      await ctx.reply(sub.reason);
      return;
    }
    await registry.register({
      telegramUserId: uid,
      subscriptionTier: sub.tier,
    });
    ensureSession(uid, sub.tier);
    await ctx.reply("스킬을 선택하세요.", { reply_markup: mainMenuKeyboard() });
  });

  bot.on("callback_query:data", async (ctx) => {
    const uid = ctx.from?.id;
    const data = ctx.callbackQuery.data;
    if (uid === undefined || !data) return;
    await ctx.answerCallbackQuery();

    if (data === callbackTokens.help) {
      await ctx.reply(
        [
          "명령:",
          "/start — 등록 및 메뉴",
          "/menu — 스킬 메뉴",
          "",
          "스킬을 고른 뒤 일반 메시지를 보내면 해당 스킬 컨텍스트로 CLI에 전달됩니다.",
        ].join("\n"),
      );
      return;
    }

    if (data === callbackTokens.mainMenu) {
      await ctx.reply("메인 메뉴", { reply_markup: mainMenuKeyboard() });
      return;
    }

    if (data.startsWith("s:")) {
      const slug = data.slice(2);
      const sub = evaluateSubscription(uid);
      if (!sub.ok) {
        await ctx.reply(sub.reason);
        return;
      }
      ensureSession(uid, sub.tier);
      setActiveSkill(uid, slug);
      await registry.setActiveSkill(uid, slug, sub.tier);
      await ctx.reply(
        `선택됨: ${escapeMarkdownV2(skillTitle(slug))} \\(${escapeMarkdownV2(slug)}\\)`,
        { parse_mode: "MarkdownV2" },
      );
      return;
    }
  });

  bot.on("message:text", async (ctx) => {
    const uid = ctx.from?.id;
    const text = ctx.message.text;
    if (uid === undefined || !text) return;
    if (text.startsWith("/")) return;

    const sub = evaluateSubscription(uid);
    if (!sub.ok) {
      await ctx.reply(sub.reason);
      return;
    }

    const sess = getSession(uid) ?? ensureSession(uid, sub.tier);
    const slug = sess.activeSkillSlug ?? registry.get(uid)?.activeSkillSlug;
    if (!slug) {
      await ctx.reply("먼저 스킬 메뉴에서 항목을 선택하세요. /menu", {
        reply_markup: mainMenuKeyboard(),
      });
      return;
    }

    const prompt = [
      `[JobStack skill=${slug} telegramUserId=${uid}]`,
      text,
    ].join("\n\n");

    await ctx.replyWithChatAction("typing");
    const result = await runClaudeCliBridge(prompt);
    if (!result.ok) {
      await ctx.reply(
        [
          "Claude CLI 실행에 실패했습니다.",
          result.error,
          "",
          "로컬에 Claude Code CLI가 설치되어 있고 PATH에 있어야 합니다.",
        ].join("\n"),
      );
      return;
    }

    const out = result.stdout.trim() || "(stdout 비어 있음)";
    for (const part of chunkMessage(out)) {
      await ctx.reply(part);
    }
    if (result.stderr.trim()) {
      await ctx.reply(`stderr:\n${result.stderr}`);
    }
  });

  /** 문서에 명시된 PDF/파일 업로드 경로 — Phase 1은 스텁 */
  bot.on("message:document", async (ctx) => {
    const file = await ctx.getFile();
    const link = `https://api.telegram.org/file/bot${config.telegramBotToken}/${file.file_path}`;
    await ctx.reply(
      `문서를 받았습니다. Phase 1에서는 파일 내용 대신 링크만 기록합니다.\n${link}`,
    );
  });

  bot.catch((err) => {
    const e = err.error;
    if (e instanceof GrammyError) {
      console.error("GrammyError:", e.description);
    } else if (e instanceof HttpError) {
      console.error("HttpError:", e);
    } else {
      console.error("Bot error:", e);
    }
  });

  return bot;
}
