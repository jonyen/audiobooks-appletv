import { parseRoman } from "./romanNumerals";

export interface TextChapter {
  title: string;
  body: string;
}

export function isHeading(line: string): boolean {
  if (/^(?:chapter|book|part|letter|stave|canto)\s+(\d+|[IVXLCDM]+|[A-Za-z]+)\b/i.test(line)) {
    return true;
  }
  const roman = line.match(/^([IVXLCDM]+)\.?\s*$/);
  if (roman && parseRoman(roman[1]) !== null) return true;
  return /^\d+\.?\s*$/.test(line);
}

/**
 * Splits a Gutenberg plain text into chapters by heading lines.
 * A heading is a short line, preceded by a blank line (or text start),
 * matching a chapter-keyword pattern or a bare Roman/Arabic numeral.
 */
export function splitChapters(text: string): TextChapter[] {
  const normalized = text.replaceAll("\r\n", "\n");
  const lines = normalized.split("\n");
  const headingIndices: number[] = [];

  lines.forEach((line, i) => {
    const trimmed = line.trim();
    if (trimmed.length === 0 || trimmed.length > 80) return;
    const previousBlank = i === 0 || lines[i - 1].trim().length === 0;
    if (previousBlank && isHeading(trimmed)) headingIndices.push(i);
  });

  if (headingIndices.length < 2) {
    return [{ title: "Full Text", body: normalized }];
  }

  return headingIndices.map((start, n) => {
    const end = n + 1 < headingIndices.length ? headingIndices[n + 1] : lines.length;
    return {
      title: lines[start].trim(),
      body: lines.slice(start + 1, end).join("\n").trim(),
    };
  });
}
