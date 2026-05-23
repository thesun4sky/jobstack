const TG_MAX = 4096;

/** Telegram MarkdownV2에서 의미 있는 문자 이스케이프 */
export function escapeMarkdownV2(text: string): string {
  return text.replace(/([_*\[\]()~`>#+\-=|{}.!\\])/g, "\\$1");
}

/** 긴 텍스트를 4096자 청크로 분할 (코드펜스 없이 순수 텍스트 기준) */
export function chunkMessage(text: string, maxLen = TG_MAX): string[] {
  if (text.length <= maxLen) return [text];
  const chunks: string[] = [];
  let i = 0;
  while (i < text.length) {
    chunks.push(text.slice(i, i + maxLen));
    i += maxLen;
  }
  return chunks;
}

/** 표 형태를 단순 텍스트 테이블로 (MarkdownV2 이전 단계) */
export function formatTable(rows: string[][]): string {
  if (rows.length === 0) return "";
  const widths = rows[0].map((_, col) =>
    Math.max(...rows.map((r) => (r[col] ?? "").length)),
  );
  return rows
    .map((r) => r.map((cell, i) => (cell ?? "").padEnd(widths[i])).join("  "))
    .join("\n");
}
