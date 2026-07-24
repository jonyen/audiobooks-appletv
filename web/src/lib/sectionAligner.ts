import { parseRoman } from "./romanNumerals";

/**
 * Lowercases, splits on non-alphanumerics, converts Roman-numeral tokens
 * and zero-padded numbers to plain Arabic, rejoins with single spaces.
 */
export function normalizeTitle(title: string): string {
  const tokens = title.toLowerCase().split(/[^\p{L}\p{N}]+/u).filter(Boolean);
  return tokens
    .map((token) => {
      if (/^\d+$/.test(token)) return String(parseInt(token, 10));
      if ([...token].every((c) => "ivxlcdm".includes(c))) {
        const n = parseRoman(token);
        if (n !== null) return String(n);
      }
      return token;
    })
    .join(" ");
}

/**
 * Chapter bodies below this length are presumed to be table-of-contents
 * stubs (e.g. a lone "CHAPTER I." line) rather than real chapter text.
 */
const MIN_ELIGIBLE_BODY_LENGTH = 200;

export function matchedCount(alignment: (number | null)[]): number {
  return alignment.filter((i) => i !== null).length;
}

/**
 * Aligns audio section titles to text chapter titles: exact normalized
 * match, then padded containment (so "chapter 1" can't match inside
 * "chapter 12"), then positional fallback when nothing matched and counts
 * agree. When bodies are provided, TOC stubs (< MIN_ELIGIBLE_BODY_LENGTH
 * chars) are ineligible unless every chapter is a stub.
 */
export function alignSections(
  sectionTitles: string[],
  chapterTitles: string[],
  chapterBodies?: string[]
): (number | null)[] {
  const chapters = chapterTitles.map(normalizeTitle);

  let eligible = chapters.map(() => true);
  if (chapterBodies) {
    eligible = chapterBodies.map((body) => body.length >= MIN_ELIGIBLE_BODY_LENGTH);
    if (!eligible.includes(true)) eligible = chapters.map(() => true);
  }

  let result: (number | null)[] = sectionTitles.map((sectionTitle) => {
    const section = normalizeTitle(sectionTitle);
    const exact = chapters.findIndex((chapter, i) => eligible[i] && chapter === section);
    if (exact >= 0) return exact;

    const padded = ` ${section} `;
    const contained = chapters.findIndex((chapter, i) => {
      if (!eligible[i] || chapter.length === 0) return false;
      const paddedChapter = ` ${chapter} `;
      return padded.includes(paddedChapter) || paddedChapter.includes(padded);
    });
    return contained >= 0 ? contained : null;
  });

  if (result.every((i) => i === null) && sectionTitles.length === chapterTitles.length) {
    result = sectionTitles.map((_, i) => i);
  }
  return result;
}
