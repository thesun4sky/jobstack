import { InlineKeyboard } from "grammy";
import { SKILL_MENU } from "./skills-catalog.js";

const CB = {
  mainMenu: "m:main",
  help: "m:help",
} as const;

export function mainMenuKeyboard(): InlineKeyboard {
  const kb = new InlineKeyboard();
  for (let i = 0; i < SKILL_MENU.length; i += 2) {
    const a = SKILL_MENU[i];
    const b = SKILL_MENU[i + 1];
    kb.text(a.title, `s:${a.slug}`);
    if (b) kb.text(b.title, `s:${b.slug}`);
    kb.row();
  }
  kb.text("도움말", CB.help).text("처음으로", CB.mainMenu);
  return kb;
}

export const callbackTokens = CB;
