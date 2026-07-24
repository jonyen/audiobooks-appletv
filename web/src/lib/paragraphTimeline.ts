/**
 * Estimated narration start times for each paragraph of a chapter.
 *
 * LibriVox audio has no timing metadata, so times are estimated by
 * splitting the section's duration across paragraphs in proportion to
 * their character counts. Recordings open with a short spoken preamble;
 * a known preamble length is passed as leadIn and shifts every start.
 */
export interface ParagraphTimeline {
  /**
   * The paragraph being narrated at a playback position. Positions before
   * the first start clamp to the first paragraph; positions at or past the
   * end clamp to the last.
   */
  paragraphIndex(seconds: number): number | null;
}

interface Entry {
  start: number;
  end: number;
}

/**
 * Splits a chapter body into paragraphs on blank lines (lines that are
 * empty or whitespace-only), trimming each paragraph and dropping empties.
 * Handles CRLF input.
 */
export function paragraphsFrom(body: string): string[] {
  const lines = body.replaceAll("\r\n", "\n").split("\n");
  const paragraphs: string[] = [];
  let current: string[] = [];
  for (const line of lines) {
    if (line.trim().length === 0) {
      if (current.length > 0) {
        paragraphs.push(current.join("\n").trim());
        current = [];
      }
    } else {
      current.push(line);
    }
  }
  if (current.length > 0) paragraphs.push(current.join("\n").trim());
  return paragraphs.filter((p) => p.length > 0);
}

export function makeParagraphTimeline(
  paragraphs: string[],
  duration: number,
  leadIn = 0
): ParagraphTimeline | null {
  if (!Number.isFinite(duration) || duration <= 0 || paragraphs.length === 0) return null;
  const counts = paragraphs.map((p) => p.length);
  const total = counts.reduce((a, b) => a + b, 0);
  if (total === 0) return null;

  // A preamble is never half the section; clamping keeps a bogus cached
  // offset from wrecking the whole timeline.
  const clampedLeadIn = Math.min(Math.max(0, leadIn), duration * 0.5);
  const spoken = duration - clampedLeadIn;
  let start = clampedLeadIn;
  const entries: Entry[] = counts.map((count) => {
    const length = (spoken * count) / total;
    const entry = { start, end: start + length };
    start += length;
    return entry;
  });

  return {
    paragraphIndex(seconds: number): number | null {
      if (entries.length === 0) return null;
      if (seconds < entries[0].start) return 0;
      if (seconds >= entries[entries.length - 1].end) return entries.length - 1;
      const index = entries.findIndex((e) => seconds >= e.start && seconds < e.end);
      return index >= 0 ? index : null;
    },
  };
}
