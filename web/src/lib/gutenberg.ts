import type { Audiobook } from "./librivox";

const ID_PATTERNS = [/\/etext\/(\d+)/, /\/ebooks\/(\d+)/, /\/files\/(\d+)/, /\/epub\/(\d+)/];

/**
 * Extracts the Project Gutenberg ebook ID from a LibriVox `url_text_source`
 * value. Returns null when the source is not a gutenberg.org URL.
 */
export function ebookID(url: string): number | null {
  if (!url.includes("gutenberg.org")) return null;
  for (const pattern of ID_PATTERNS) {
    const match = url.match(pattern);
    if (match) return parseInt(match[1], 10);
  }
  return null;
}

/**
 * Removes the Project Gutenberg license header and footer, keeping only
 * the book body. Texts without markers are returned trimmed but intact.
 * CRLF endings are normalized first so the [^\n]* marker patterns match.
 */
export function stripBoilerplate(raw: string): string {
  let text = raw.replaceAll("\r\n", "\n");
  const start = text.match(/\*\*\* ?START OF TH(E|IS) PROJECT GUTENBERG EBOOK[^\n]*/i);
  if (start && start.index !== undefined) {
    text = text.slice(start.index + start[0].length);
  }
  const end = text.match(/\*\*\* ?END OF TH(E|IS) PROJECT GUTENBERG EBOOK/i);
  if (end && end.index !== undefined) {
    text = text.slice(0, end.index);
  }
  return text.trim();
}

export function gutenbergID(book: Audiobook): number | null {
  return book.textSourceURL === null ? null : ebookID(book.textSourceURL);
}

export function hasText(book: Audiobook): boolean {
  return gutenbergID(book) !== null;
}
