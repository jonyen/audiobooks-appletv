import { gutenbergID, stripBoilerplate } from "./gutenberg";
import type { Audiobook } from "./librivox";
import { splitChapters, type TextChapter } from "./chapterSplitter";
import { alignSections, matchedCount } from "./sectionAligner";

export interface BookText {
  chapters: TextChapter[];
  alignment: (number | null)[];
}

/**
 * Fetch → strip → split → align, mirroring the tvOS BookTextModel.
 * Returns null when the book has no Gutenberg source (audio-only).
 */
export async function loadBookText(book: Audiobook): Promise<BookText | null> {
  const ebookID = gutenbergID(book);
  if (ebookID === null) return null;

  const response = await fetch(`/api/gutenberg/${ebookID}`);
  if (!response.ok) {
    throw new Error("The book text could not be found on Project Gutenberg.");
  }
  const text = stripBoilerplate(await response.text());
  const chapters = splitChapters(text);
  const alignment = alignSections(
    book.sections.map((s) => s.title),
    chapters.map((c) => c.title),
    chapters.map((c) => c.body)
  );
  return { chapters, alignment };
}

/** The matched text chapter for an audio section, or null when unmatched. */
export function chapterForSection(text: BookText, sectionIndex: number): TextChapter | null {
  if (sectionIndex < 0 || sectionIndex >= text.alignment.length) return null;
  const chapterIndex = text.alignment[sectionIndex];
  if (chapterIndex === null || chapterIndex >= text.chapters.length) return null;
  return text.chapters[chapterIndex];
}

export function matchSummary(text: BookText): string {
  return `Read-along: ${matchedCount(text.alignment)} of ${text.alignment.length} chapters matched`;
}
